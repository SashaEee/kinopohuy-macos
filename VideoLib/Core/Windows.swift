import SwiftUI

enum Windows: String, CaseIterable, Identifiable {
    case videolib
    case player
    case imageViewer
    case licenses
    case about

    var id: String {
        rawValue
    }

    @MainActor var window: NSWindow? {
        NSApp.windows.first(where: { $0.identifier?.rawValue.localizedCaseInsensitiveContains(rawValue) ?? false })
    }
}
