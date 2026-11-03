import AppKit
import SwiftUI

@main
struct PRadarApp: App {
    @State private var store = PullRequestStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            InboxView(store: store)
        } label: {
            Image(systemName: "arrow.triangle.pull")
            if store.attentionCount > 0 {
                Text("\(store.attentionCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
