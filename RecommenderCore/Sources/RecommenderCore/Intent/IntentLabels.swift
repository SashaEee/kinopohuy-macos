import Foundation

/// Russian wording for intents: the chips («до 1,5 ч», «КП от 7», «90-е») and the longer phrases the picker uses when it
/// drops a constraint («убрал «до 90 минут»»).
enum IntentLabels {
    /// «7», «7,5».
    static func number(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    static func kind(_ kind: TitleKind) -> String {
        switch kind {
        case .film: "фильм"
        case .series: "сериал"
        case .cartoon: "мульт"
        case .anime: "аниме"
        case .show: "шоу"
        }
    }

    /// «фильм», «фильм или сериал», «не аниме», «не аниме и не мульт».
    static func kinds(_ kinds: Set<TitleKind>) -> String {
        let ordered = TitleKind.allCases.filter(kinds.contains)
        let missing = TitleKind.allCases.filter { !kinds.contains($0) }
        if ordered.count == 1, let only = ordered.first { return kind(only) }
        if missing.count == 1, let only = missing.first { return "не \(kind(only))" }
        if ordered.count == 2 { return ordered.map(kind).joined(separator: " или ") }
        if missing.count == 2 { return missing.map { "не \(kind($0))" }.joined(separator: " и ") }
        return ordered.map(kind).joined(separator: ", ")
    }

    /// The chip: «до 1,5 ч», «до 90 мин», «серия 20–45 мин», «фильм на вечер».
    static func timeChip(_ time: TimeBudget) -> String {
        switch time {
        case .maxMinutes(let minutes):
            if let hours = wholeOrHalfHours(minutes) { return "до \(hours) ч" }
            return "до \(minutes) мин"
        case .episode(let range):
            return range.lowerBound <= 1
                ? "серия до \(range.upperBound) мин"
                : "серия \(range.lowerBound)–\(range.upperBound) мин"
        case .filmNight:
            return "фильм на вечер"
        case .weekendSeries:
            return "сериал на выходные"
        }
    }

    /// The phrase: «до 90 минут», «до 1,5 часа», «серия до 45 минут».
    static func timePhrase(_ time: TimeBudget) -> String {
        switch time {
        case .maxMinutes(let minutes):
            if minutes % 60 == 0 {
                let hours = minutes / 60
                return "до \(hours) \(hours % 10 == 1 && hours % 100 != 11 ? "часа" : "часов")"
            }
            if let hours = wholeOrHalfHours(minutes) { return "до \(hours) часа" }
            return "до \(minutes) \(minutesGenitive(minutes))"
        case .episode(let range):
            return range.lowerBound <= 1
                ? "серия до \(range.upperBound) \(minutesGenitive(range.upperBound))"
                : "серия \(range.lowerBound)–\(range.upperBound) минут"
        case .filmNight:
            return "фильм на вечер"
        case .weekendSeries:
            return "сериал на выходные"
        }
    }

    /// «КП от 7», «IMDb от 7,5», «RT от 80 %», «рейтинг от 7,5».
    static func rating(_ floor: RatingFloor) -> String {
        let value = number(floor.value)
        switch floor.source {
        case .kp: return "КП от \(value)"
        case .imdb: return "IMDb от \(value)"
        case .rt: return "RT от \(value) %"
        case .any: return "рейтинг от \(value)"
        }
    }

    /// «90-е», «2010-е», «с 2023», «до 2000», «2019», «2015–2020».
    static func years(_ range: ClosedRange<Int>, currentYear: Int) -> String {
        let lower = range.lowerBound
        let upper = range.upperBound
        if lower <= 1900 {
            return (upper + 1) % 10 == 0 ? "до \(upper + 1)" : "до \(upper)"
        }
        if lower % 10 == 0, upper == lower + 9 || (upper >= currentYear && upper < lower + 10) {
            return lower < 2000 ? "\(lower % 100)-е" : "\(lower)-е"
        }
        if lower == upper { return "\(lower)" }
        if upper >= currentYear { return "с \(lower)" }
        return "\(lower)–\(upper)"
    }

    /// «без насилия», «не про войну».
    static func avoid(_ term: String) -> String {
        let lower = IntentText.normalize(term)
        if lower.hasPrefix("про ") || lower.hasPrefix("о ") || lower.hasPrefix("об ") { return "не \(term)" }
        return "без \(term)"
    }

    static func minutesGenitive(_ minutes: Int) -> String {
        minutes % 10 == 1 && minutes % 100 != 11 ? "минуты" : "минут"
    }

    /// «1», «1,5», «2» for budgets phrased in hours (half hours carry five minutes of slack: 95 = «полтора часа»).
    private static func wholeOrHalfHours(_ minutes: Int) -> String? {
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60)" }
        if minutes > 60, (minutes - 5) % 60 == 30 { return "\((minutes - 5) / 60),5" }
        return nil
    }
}

/// The calendar year of a moment, for «посвежее» (the last three years) and the year chips.
enum IntentCalendar {
    static func year(of seconds: Double) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.component(.year, from: Date(timeIntervalSince1970: seconds))
    }
}
