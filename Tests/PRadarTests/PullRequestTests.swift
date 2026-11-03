import Foundation
import Testing

@testable import PRadar

struct PullRequestTests {
    private static let myReviewAt = "2026-01-01T10:00:00Z"
    private static let beforeMyReview = "2026-01-01T08:00:00Z"
    private static let afterMyReview = "2026-01-01T11:00:00Z"

    private func pullRequest(
        myReviewAt: String? = myReviewAt,
        colleagueCommentAt: String = beforeMyReview,
        ownCommentAt: String? = beforeMyReview,
        mergeable: String = "MERGEABLE",
        reviewDecision: String = "\"APPROVED\"",
        latestReviewStates: [String] = ["APPROVED"],
        url: String = "https://github.com/a/b/pull/1"
    ) throws -> PullRequest {
        let latestReviews = latestReviewStates.map { #"{"state":"\#($0)"}"# }.joined(separator: ",")
        let ownComment = ownCommentAt.map { #",{"createdAt":"\#($0)","author":{"login":"me"}}"# } ?? ""
        let myReviews = myReviewAt.map { #"[{"submittedAt":"\#($0)","author":{"login":"me"}}]"# } ?? "[]"
        let json = """
            {
              "number": 1, "title": "Test", "url": "\(url)", "isDraft": false,
              "reviewDecision": \(reviewDecision), "mergeable": "\(mergeable)",
              "repository": { "nameWithOwner": "a/b" },
              "commits": { "nodes": [{ "commit": { "committedDate": "\(Self.beforeMyReview)", "statusCheckRollup": null } }] },
              "myReviews": { "nodes": \(myReviews) },
              "reviews": { "nodes": [] },
              "latestReviews": { "nodes": [\(latestReviews)] },
              "reviewThreads": { "nodes": [{ "comments": { "totalCount": 3 } }, { "comments": { "totalCount": 1 } }] },
              "comments": { "totalCount": 2, "nodes": [
                { "createdAt": "\(colleagueCommentAt)", "author": { "login": "colleague" } }\(ownComment)
              ] }
            }
            """

        return try GitHubClient.decoder.decode(PullRequest.self, from: Data(json.utf8))
    }

    @Test func colleagueCommentAfterMyReviewIsNewActivity() throws {
        #expect(try pullRequest(colleagueCommentAt: Self.afterMyReview).hasUnseenActivity(login: "me", seenAt: nil))
    }

    @Test func ownCommentAfterMyReviewIsNotNewActivity() throws {
        #expect(try !pullRequest(ownCommentAt: Self.afterMyReview).hasUnseenActivity(login: "me", seenAt: nil))
    }

    @Test func withoutAnyInteractionThereIsNoNewActivity() throws {
        #expect(
            try !pullRequest(myReviewAt: nil, colleagueCommentAt: Self.afterMyReview, ownCommentAt: nil)
                .hasUnseenActivity(login: "me", seenAt: nil))
    }

    @Test func commentCountAddsConversationAndReviewThreadComments() throws {
        #expect(try pullRequest().commentCount == 6)
    }

    @Test func approvedMergeablePullRequestWithoutChecksIsReadyToMerge() throws {
        #expect(try pullRequest().isReadyToMerge)
    }

    @Test func conflictingPullRequestIsNotReadyToMerge() throws {
        #expect(try !pullRequest(mergeable: "CONFLICTING").isReadyToMerge)
    }

    @Test func approvalCountOnlyCountsApprovedReviews() throws {
        #expect(try pullRequest(latestReviewStates: ["APPROVED", "COMMENTED", "APPROVED"]).approvalCount == 2)
    }

    @Test func approvalWithoutRequiredReviewsCountsAsApproved() throws {
        #expect(try pullRequest(reviewDecision: "null").isApproved)
    }

    @Test func approvalBelowRequiredCountIsNotApproved() throws {
        #expect(try !pullRequest(reviewDecision: "\"REVIEW_REQUIRED\"").isApproved)
    }

    @Test func openingAfterColleagueCommentMarksItSeen() throws {
        let seenAt = try #require(ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))

        #expect(try !pullRequest(colleagueCommentAt: Self.afterMyReview).hasUnseenActivity(login: "me", seenAt: seenAt))
    }

    @Test func colleagueCommentAfterOpeningWithoutReviewIsUnseen() throws {
        let seenAt = try #require(ISO8601DateFormatter().date(from: Self.myReviewAt))

        #expect(
            try pullRequest(myReviewAt: nil, colleagueCommentAt: Self.afterMyReview, ownCommentAt: nil)
                .hasUnseenActivity(login: "me", seenAt: seenAt))
    }

    @Test func onlyHttpsGitHubUrlsAreOpenable() throws {
        #expect(try pullRequest().isGitHubWebUrl)
        #expect(try !pullRequest(url: "file:///Applications/Calculator.app").isGitHubWebUrl)
        #expect(try !pullRequest(url: "https://github.com.evil.example/a/b/pull/1").isGitHubWebUrl)
    }
}
