import SwiftUI

/// This Mac's history by title number (see `WatchHistory`), for the posters' progress bars and «Осталось N мин». The
/// shell reads it once, live, and hands it down; it changes every ~15 s at most while something plays.
struct KPWatchHistory: Equatable, Sendable {
    var byId: [String: WatchHistory] = [:]

    subscript(id: String?) -> WatchHistory? {
        id.flatMap { byId[$0] }
    }
}

extension EnvironmentValues {
    @Entry var kpWatchHistory = KPWatchHistory()
}
