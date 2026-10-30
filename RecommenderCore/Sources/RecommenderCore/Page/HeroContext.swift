import Foundation

/// What «Сегодня вечером» looks for at this moment (§4.8): a weekday evening wants a film up to 110 minutes or a
/// mini-series; after 23:00 an episode of 20–45 minutes; Friday and Saturday evenings a film for the evening;
/// Saturday daytime a series for the weekend; other daytime something light and short.
struct HeroContext: Sendable, Hashable {
    enum Slot: Sendable, Hashable {
        case lateNight
        case weekdayEvening
        case weekendEvening
        case saturdayDay
        case daytime
    }

    let slot: Slot
    let label: String
    let weights: Weights

    init(context: EngineContext, weights: Weights) {
        self.weights = weights
        let hour = context.hour
        let weekday = context.weekday
        if hour >= 23 || hour < 5 {
            slot = .lateNight
            label = "Серия на \(weights.heroEpisodeMinMinutes)–\(weights.heroEpisodeMaxMinutes) минут"
        } else if hour >= 17 {
            if weekday == 5 || weekday == 6 {
                slot = .weekendEvening
                label = "Фильм на вечер"
            } else {
                slot = .weekdayEvening
                label = "Фильм до \(RussianText.duration(weights.heroWeekdayMaxMinutes)) или мини-сериал"
            }
        } else if weekday == 6, hour >= 10 {
            slot = .saturdayDay
            label = "Сериал на выходные"
        } else {
            slot = .daytime
            label = "Что-нибудь лёгкое и недолгое"
        }
    }

    /// Whether a title fits the moment. Unknown lengths don't fit: the label promises them.
    func matches(_ title: TitleFeatures) -> Bool {
        switch slot {
        case .lateNight:
            guard title.isSeries, let minutes = title.durationMin else { return false }
            return minutes >= weights.heroEpisodeMinMinutes && minutes <= weights.heroEpisodeMaxMinutes
        case .weekdayEvening:
            if isMiniSeries(title) { return true }
            guard !title.isSeries, let minutes = title.durationMin else { return false }
            return minutes <= weights.heroWeekdayMaxMinutes
        case .weekendEvening:
            guard !title.isSeries else { return false }
            return (title.durationMin ?? 90) >= 70
        case .saturdayDay:
            return title.isSeries && !isMiniSeries(title)
        case .daytime:
            guard isLight(title) else { return false }
            if title.isSeries { return (title.durationMin ?? 0) > 0 && (title.durationMin ?? 0) <= weights.heroEpisodeMaxMinutes }
            return (title.durationMin ?? 0) > 0 && (title.durationMin ?? 0) <= 100
        }
    }

    /// One season of at most ten episodes.
    func isMiniSeries(_ title: TitleFeatures) -> Bool {
        guard title.isSeries, (title.seasons ?? 1) <= 1, let episodes = title.releasedEpisodes else { return false }
        return episodes > 0 && episodes <= weights.miniSeriesMaxEpisodes
    }

    static let lightGenres: Set<String> = [
        "комедии", "комедия", "семейные", "семейный", "мультфильмы", "мультфильм", "приключения", "мюзиклы",
        "мюзикл", "ситкомы", "ситком", "фэнтези",
    ]

    func isLight(_ title: TitleFeatures) -> Bool {
        guard let genre = title.genres.first else { return false }
        return Self.lightGenres.contains(TextKey.normalized(genre))
    }
}
