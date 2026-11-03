import AppKit
import SwiftUI

struct InboxView: View {
    private static let screenHeightRatio: CGFloat = 0.85
    private static let fallbackHeight: CGFloat = 800

    let store: PullRequestStore

    @State private var expandedContentHeight: CGFloat = 0
    @State private var isEditingToken = false
    @State private var displayedContentHeight: CGFloat = 0

    private var maximumListHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? Self.fallbackHeight) * Self.screenHeightRatio
    }

    private var truncatesLongSections: Bool {
        expandedContentHeight > maximumListHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding()
            }

            if store.needsToken || isEditingToken {
                TokenForm(store: store) { isEditingToken = false }
                Divider()
            }

            ScrollView {
                sections(truncatesLongSections: truncatesLongSections)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { displayedContentHeight = $0 }
            }
            .frame(height: min(displayedContentHeight, maximumListHeight))
            .background {
                sections(truncatesLongSections: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { expandedContentHeight = $0 }
            }

            Divider()
            footer
        }
        .frame(width: 620)
    }

    private var sectionContents: [(title: String, pullRequests: [PullRequest])] {
        [
            ("Review requested", store.requested),
            ("Reviewed by me", store.reviewed),
            ("My pull requests", store.mine),
            ("Ready to merge", store.readyToMerge),
        ]
    }

    private func sections(truncatesLongSections: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sectionContents, id: \.title) { section in
                InboxSection(
                    title: section.title, pullRequests: section.pullRequests, store: store,
                    truncatesLongSections: truncatesLongSections)
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = store.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LaunchAtLoginToggle()
            Button("Token…") { isEditingToken.toggle() }
            Button("Refresh") { Task { await store.refresh() } }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .font(.caption)
        .padding(10)
    }
}

private struct InboxSection: View {
    private static let collapsedLimit = 10

    let title: String
    let pullRequests: [PullRequest]
    let store: PullRequestStore
    let truncatesLongSections: Bool

    @State private var isExpanded = false

    private var isTruncated: Bool {
        truncatesLongSections && !isExpanded
    }

    private var visiblePullRequests: ArraySlice<PullRequest> {
        isTruncated ? pullRequests.prefix(Self.collapsedLimit) : pullRequests[...]
    }

    private var hiddenCount: Int {
        pullRequests.count - Self.collapsedLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(pullRequests.count)")
                .font(.headline)

            if pullRequests.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(.secondary)
            }

            ForEach(visiblePullRequests) { pullRequest in
                PullRequestRow(pullRequest: pullRequest, hasNewActivity: store.hasUnseenActivity(pullRequest)) {
                    guard pullRequest.isGitHubWebUrl else {
                        return
                    }

                    store.markSeen(pullRequest)
                    NSWorkspace.shared.open(pullRequest.url)
                }
            }

            if truncatesLongSections && hiddenCount > 0 {
                Button(isExpanded ? "Show less" : "Show all (\(hiddenCount) more)") {
                    isExpanded.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}

private struct PullRequestRow: View {
    private static let countColumnWidth: CGFloat = 40
    private static let iconColumnWidth: CGFloat = 16

    let pullRequest: PullRequest
    let hasNewActivity: Bool
    let open: () -> Void

    private var subtitle: String {
        let reference = "\(pullRequest.repository.nameWithOwner) #\(pullRequest.number)"

        guard let author = pullRequest.author else {
            return reference
        }

        return "\(reference) · by \(author.login)"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(hasNewActivity ? Color.blue : Color.clear)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pullRequest.title)
                            .lineLimit(2)
                            .foregroundStyle(pullRequest.isDraft ? .secondary : .primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    RowColumn(width: Self.countColumnWidth) {
                        CommentCountLabel(count: pullRequest.commentCount, hasNewActivity: hasNewActivity)
                    }
                    RowColumn(width: Self.countColumnWidth) {
                        ReviewStatusLabel(pullRequest: pullRequest)
                    }
                    RowColumn(width: Self.iconColumnWidth) {
                        CheckStateIcon(state: pullRequest.checkState)
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RowColumn<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: width, height: 0)
            content
        }
    }
}

private struct CommentCountLabel: View {
    let count: Int
    let hasNewActivity: Bool

    var body: some View {
        if count > 0 {
            Label("\(count)", systemImage: "bubble.left")
                .foregroundStyle(hasNewActivity ? Color.blue : Color.secondary)
                .help(hasNewActivity ? "New activity since you last looked" : "Comments")
        }
    }
}

private struct CheckStateIcon: View {
    let state: CheckState?

    var body: some View {
        switch state {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Checks passed")
        case .failure, .error:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Checks failed")
        case .pending, .expected:
            Image(systemName: "clock.fill").foregroundStyle(.orange).help("Checks running")
        case nil:
            EmptyView()
        }
    }
}

private struct ReviewStatusLabel: View {
    let pullRequest: PullRequest

    var body: some View {
        if pullRequest.reviewDecision == .changesRequested {
            Image(systemName: "hand.thumbsdown.fill").foregroundStyle(.red).help("Changes requested")
        } else if pullRequest.approvalCount > 0 {
            Label("\(pullRequest.approvalCount)", systemImage: "hand.thumbsup.fill")
                .foregroundStyle(pullRequest.isApproved ? Color.green : Color.secondary)
                .help(pullRequest.isApproved ? "Approved" : "More approvals required")
        }
    }
}
