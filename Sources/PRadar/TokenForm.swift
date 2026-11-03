import SwiftUI

struct TokenForm: View {
    private static let createTokenUrl = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    let store: PullRequestStore
    let close: () -> Void

    @State private var token = ""

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub token")
                .font(.headline)
            Text(
                "PRadar only reads data. Create a fine-grained token with read-only access to "
                    + "Pull requests, Contents and Commit statuses. It is stored in your Keychain."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Link("Create a token on GitHub", destination: Self.createTokenUrl)
                .font(.caption)

            HStack {
                SecureField("Paste a GitHub token", text: $token)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(trimmedToken.isEmpty)
            }

            if store.hasSavedToken {
                Button("Remove saved token") {
                    Task { await store.removeSavedToken() }
                    close()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding()
    }

    private func save() {
        guard !trimmedToken.isEmpty else {
            return
        }

        let token = trimmedToken
        self.token = ""
        Task { await store.saveToken(token) }
        close()
    }
}
