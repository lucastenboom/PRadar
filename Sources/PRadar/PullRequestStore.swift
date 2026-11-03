import Foundation
import Observation

@MainActor
@Observable
final class PullRequestStore {
    private static let refreshInterval: Duration = .seconds(60)
    private static let retryInterval: Duration = .seconds(10)
    private static let seenAtDefaultsKey = "seenAt"

    private(set) var readyToMerge: [PullRequest] = []
    private(set) var mine: [PullRequest] = []
    private(set) var requested: [PullRequest] = []
    private(set) var reviewed: [PullRequest] = []
    private(set) var login = ""
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var seenAt: [URL: Date] = loadSeenAt()
    private(set) var needsToken = false
    private(set) var hasSavedToken = KeychainTokenStore.app.read() != nil

    private var client: GitHubClient?

    var attentionCount: Int {
        requested.count + (reviewed + mine + readyToMerge).filter(hasUnseenActivity).count
    }

    init() {
        Task { await poll() }
    }

    func hasUnseenActivity(_ pullRequest: PullRequest) -> Bool {
        pullRequest.hasUnseenActivity(login: login, seenAt: seenAt[pullRequest.url])
    }

    func markSeen(_ pullRequest: PullRequest) {
        seenAt[pullRequest.url] = .now
        saveSeenAt()
    }

    func refresh() async {
        do {
            let client = try await resolvedClient()
            if login.isEmpty {
                login = try await client.viewerLogin()
            }

            let inbox = try await client.inbox(login: login)
            let requestedUrls = Set(inbox.requested.map(\.url))

            readyToMerge = inbox.mine.filter(\.isReadyToMerge)
            mine = inbox.mine.filter { !$0.isReadyToMerge }
            requested = inbox.requested
            reviewed = inbox.reviewed.filter { !requestedUrls.contains($0.url) }
            forgetClosedPullRequests(openUrls: Set((inbox.mine + inbox.requested + inbox.reviewed).map(\.url)))
            lastUpdated = .now
            errorMessage = nil
            needsToken = false
        } catch {
            errorMessage = error.localizedDescription
            needsToken = (error as? GitHubError)?.needsNewToken ?? false
            if needsToken {
                client = nil
            }
        }
    }

    func saveToken(_ token: String) async {
        do {
            try KeychainTokenStore.app.save(token)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        hasSavedToken = true
        await reconnect()
    }

    func removeSavedToken() async {
        KeychainTokenStore.app.delete()
        hasSavedToken = false
        await reconnect()
    }

    private func reconnect() async {
        client = nil
        login = ""
        await refresh()
    }

    private func forgetClosedPullRequests(openUrls: Set<URL>) {
        seenAt = seenAt.filter { openUrls.contains($0.key) }
        saveSeenAt()
    }

    private func saveSeenAt() {
        UserDefaults.standard.set(try? JSONEncoder().encode(seenAt), forKey: Self.seenAtDefaultsKey)
    }

    private static func loadSeenAt() -> [URL: Date] {
        guard let data = UserDefaults.standard.data(forKey: seenAtDefaultsKey) else {
            return [:]
        }

        return (try? JSONDecoder().decode([URL: Date].self, from: data)) ?? [:]
    }

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: errorMessage == nil ? Self.refreshInterval : Self.retryInterval)
        }
    }

    private func resolvedClient() async throws -> GitHubClient {
        if let client {
            return client
        }

        let client = try await Task.detached { try GitHubClient.resolve() }.value
        self.client = client

        return client
    }
}
