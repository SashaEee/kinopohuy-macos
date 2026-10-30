import Foundation
import SQLiteData

/// What this Mac last played of a title: the voice-over, season and episode, how far in and how long it runs. One row
/// per title, written by the player every ~15 s, on pause and on closing; posters show it as a thin bar and «Продолжить
/// просмотр» as «Осталось 42 мин».
@Table("watch_history")
struct WatchHistory: Identifiable, Hashable, Sendable {
    /// The title's number on the site (the one in its page's path).
    let id: String
    let acting: String
    let season: String
    let episode: String
    /// Seconds in; `PlayerFeature.watchedMark` once watched (the credits reached or played to the end).
    let position: Double
    /// The stream's real length, in seconds.
    let duration: Double
    /// When it was written (seconds since 1970).
    let updatedAt: Double
}

extension WatchHistory {
    /// How far in (0…1): from 30 s until it's watched, at least a sliver so the bar shows.
    var fraction: Double? {
        guard position >= 30, position < PlayerFeature.watchedMark, duration > 0 else { return nil }
        let fraction = position / duration
        return fraction < 0.985 ? max(0.04, fraction) : nil
    }

    /// «Осталось 42 мин», «Осталось 1 ч 5 мин».
    var remainingText: String? {
        guard fraction != nil else { return nil }
        let minutes = max(1, Int(((duration - position) / 60).rounded()))
        let hours = minutes / 60
        return hours > 0
            ? "Осталось \(hours) ч" + (minutes % 60 > 0 ? " \(minutes % 60) мин" : "")
            : "Осталось \(minutes) мин"
    }
}
