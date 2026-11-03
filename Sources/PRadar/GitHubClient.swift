import Foundation

private struct SearchResult: Decodable {
    let search: Connection<PullRequest>
}

private struct Viewer: Decodable {
    let viewer: Actor
}

enum GitHubError: LocalizedError {
    case missingToken
    case graphQL([String])
    case http(Int)

    private static let unauthorizedStatusCode = 401

    var needsNewToken: Bool {
        switch self {
        case .missingToken:
            true
        case .http(let statusCode):
            statusCode == Self.unauthorizedStatusCode
        case .graphQL:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No GitHub token found."
        case .graphQL(let messages):
            messages.joined(separator: "\n")
        case .http(let statusCode) where statusCode == Self.unauthorizedStatusCode:
            "GitHub rejected the token. It may have expired or been revoked."
        case .http(let statusCode):
            "GitHub responded with HTTP \(statusCode), retrying soon."
        }
    }
}

struct GitHubClient: Sendable {
    private static let endpoint = URL(string: "https://api.github.com/graphql")!

    private static let viewerQuery = "query { viewer { login } }"

    private static let searchQuery = """
        query($search: String!, $login: String!) {
          search(type: ISSUE, query: $search, first: 50) { nodes { ...PullRequestFields } }
        }

        fragment PullRequestFields on PullRequest {
          number title url isDraft reviewDecision mergeable
          repository { nameWithOwner }
          commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
          myReviews: reviews(author: $login, last: 1, states: [APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED]) {
            nodes { submittedAt }
          }
          reviews(last: 10) { nodes { submittedAt author { login } } }
          latestReviews(first: 20) { nodes { state } }
          comments(last: 10) { totalCount nodes { createdAt author { login } } }
          reviewThreads(first: 50) { nodes { comments { totalCount } } }
        }
        """

    let token: String

    static func resolve() throws -> GitHubClient {
        if let token = KeychainTokenStore.app.read() {
            return GitHubClient(token: token)
        }

        return GitHubClient(token: try ghCliToken())
    }

    func viewerLogin() async throws -> String {
        let viewer: Viewer = try await send(query: Self.viewerQuery, variables: [:])

        return viewer.viewer.login
    }

    func inbox(login: String) async throws -> (mine: [PullRequest], requested: [PullRequest], reviewed: [PullRequest]) {
        async let mine = pullRequests(matching: "author:\(login)", login: login)
        async let requested = pullRequests(matching: "review-requested:\(login)", login: login)
        async let reviewed = pullRequests(matching: "reviewed-by:\(login) -author:\(login)", login: login)

        return try await (mine, requested, reviewed)
    }

    private func pullRequests(matching filter: String, login: String) async throws -> [PullRequest] {
        let result: SearchResult = try await send(
            query: Self.searchQuery,
            variables: [
                "search": "is:pr is:open archived:false \(filter)",
                "login": login,
            ])

        return result.search.nodes
    }

    private func send<Payload: Decodable>(query: String, variables: [String: String]) async throws -> Payload {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))

        let data = try await responseData(for: request)
        let graphQLResponse = try Self.decoder.decode(GraphQLResponse<Payload>.self, from: data)

        guard let payload = graphQLResponse.data else {
            throw GitHubError.graphQL(graphQLResponse.errors?.map(\.message) ?? ["Empty response"])
        }

        return payload
    }

    private func responseData(for request: URLRequest, attempt: Int = 1) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200

        if Self.serverErrorStatusCodes.contains(statusCode), attempt < Self.maximumAttempts {
            return try await responseData(for: request, attempt: attempt + 1)
        }

        guard statusCode == 200 else {
            throw GitHubError.http(statusCode)
        }

        return data
    }

    private static let maximumAttempts = 3
    private static let serverErrorStatusCodes = 500..<600

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let ghCliPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private static func ghCliToken() throws -> String {
        guard let ghCliPath = ghCliPaths.first(where: FileManager.default.isExecutableFile) else {
            throw GitHubError.missingToken
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: ghCliPath)
        process.arguments = ["auth", "token"]
        process.standardOutput = output
        try process.run()

        let token = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()

        guard process.terminationStatus == 0, !token.isEmpty else {
            throw GitHubError.missingToken
        }

        return token
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

private struct GraphQLResponse<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}
