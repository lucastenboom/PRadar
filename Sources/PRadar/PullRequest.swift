import Foundation

struct PullRequest: Decodable, Identifiable, Sendable {
    private static let webScheme = "https"
    private static let webHost = "github.com"

    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let reviewDecision: ReviewDecision?
    let mergeable: MergeableState
    let repository: Repository
    let author: Actor?
    let commits: Connection<CommitNode>
    let myReviews: Connection<SubmittedReview>
    let reviews: Connection<Review>
    let latestReviews: Connection<LatestReview>
    let comments: Connection<Comment>
    let reviewThreads: Connection<ReviewThread>

    var id: URL { url }

    var isGitHubWebUrl: Bool {
        url.scheme == Self.webScheme && url.host() == Self.webHost
    }

    var commentCount: Int {
        (comments.totalCount ?? 0) + reviewThreads.nodes.map(\.comments.totalCount).reduce(0, +)
    }

    var approvalCount: Int {
        latestReviews.nodes.filter { $0.state == .approved }.count
    }

    var isApproved: Bool {
        reviewDecision == .approved || (reviewDecision == nil && approvalCount > 0)
    }

    var isReadyToMerge: Bool {
        !isDraft
            && isApproved
            && mergeable == .mergeable
            && (checkState == nil || checkState == .success)
    }

    var checkState: CheckState? {
        commits.nodes.first?.commit.statusCheckRollup?.state
    }

    var myLastReviewAt: Date? {
        myReviews.nodes.first?.submittedAt
    }

    func lastActivity(byOthersThan login: String) -> Date? {
        let commentDates = comments.nodes
            .filter { $0.author?.login != login }
            .map(\.createdAt)
        let reviewDates = reviews.nodes
            .filter { $0.author?.login != login }
            .compactMap(\.submittedAt)
        let commitDates = commits.nodes.map(\.commit.committedDate)

        return (commentDates + reviewDates + commitDates).max()
    }

    func lastInteraction(by login: String, seenAt: Date?) -> Date? {
        let ownCommentDates = comments.nodes
            .filter { $0.author?.login == login }
            .map(\.createdAt)

        return (ownCommentDates + [myLastReviewAt, seenAt].compactMap { $0 }).max()
    }

    func hasUnseenActivity(login: String, seenAt: Date?) -> Bool {
        guard let lastInteraction = lastInteraction(by: login, seenAt: seenAt),
            let lastActivity = lastActivity(byOthersThan: login)
        else {
            return false
        }

        return lastActivity > lastInteraction
    }
}

struct Connection<Node: Decodable & Sendable>: Decodable, Sendable {
    let nodes: [Node]
    let totalCount: Int?
}

struct ReviewThread: Decodable, Sendable {
    let comments: Count
}

struct Count: Decodable, Sendable {
    let totalCount: Int
}

struct Repository: Decodable, Sendable {
    let nameWithOwner: String
}

struct Actor: Decodable, Sendable {
    let login: String
}

struct SubmittedReview: Decodable, Sendable {
    let submittedAt: Date?
}

struct Review: Decodable, Sendable {
    let submittedAt: Date?
    let author: Actor?
}

struct LatestReview: Decodable, Sendable {
    let state: ReviewState
}

enum ReviewState: String, Decodable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case dismissed = "DISMISSED"
    case pending = "PENDING"
}

struct Comment: Decodable, Sendable {
    let createdAt: Date
    let author: Actor?
}

struct CommitNode: Decodable, Sendable {
    let commit: Commit
}

struct Commit: Decodable, Sendable {
    let committedDate: Date
    let statusCheckRollup: StatusCheckRollup?
}

struct StatusCheckRollup: Decodable, Sendable {
    let state: CheckState
}

enum CheckState: String, Decodable, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case error = "ERROR"
    case pending = "PENDING"
    case expected = "EXPECTED"
}

enum MergeableState: String, Decodable, Sendable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

enum ReviewDecision: String, Decodable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}
