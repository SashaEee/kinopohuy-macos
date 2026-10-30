import Combine
import Sparkle
import SwiftUI

/// Asks Sparkle for a new version now. Off while it can't (a check is running, or the updater isn't started).
struct UpdateButton: View {
    private let updater: SPUUpdater
    /// nil: «Проверить наличие обновлений…», the menu item's wording.
    private let title: String?

    @State private var canCheckForUpdates: Bool = false

    init(updater: SPUUpdater, title: String? = nil) {
        self.updater = updater
        self.title = title
    }

    var body: some View {
        Button {
            updater.checkForUpdates()
        } label: {
            if let title {
                Text(verbatim: title)
            } else {
                Text("key.checkUpdates")
            }
        }
        .disabled(!canCheckForUpdates)
        .onReceive(updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main)) { canCheckForUpdates in
            self.canCheckForUpdates = canCheckForUpdates
        }
    }
}
