import RecommenderCore
import SwiftUI

extension TitleFeatures {
    /// The card a view opens for it (the site's path, name and poster).
    var simple: MovieSimple { MovieSimple(movieId: path, name: name, poster: poster) }

    /// The card's corner: Kinopoisk's rating, else IMDb's, else the site's, as the site's own cards show one.
    var cornerRating: Float? { (kpRating ?? imdbRating ?? siteRating).map(Float.init) }

    /// Under the card's name: «2019 · Комедия», or the country when the genre isn't known yet.
    var cardSubtitle: String? {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let genre = genres.first {
            parts.append(genre)
        } else if let country = countries.first {
            parts.append(country)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «2019 · 1 ч 38 мин · Комедия, Драма · 16+», or «Сериал · 3 сезона» for a series.
    var recFacts: [String] {
        var facts: [String] = []
        if let year { facts.append(String(year)) }
        if isSeries {
            if let seasons, seasons > 0 {
                facts.append(RecText.count(seasons, "сезон", "сезона", "сезонов"))
            } else if let releasedEpisodes, releasedEpisodes > 0 {
                facts.append(RecText.count(releasedEpisodes, "серия", "серии", "серий"))
            }
        } else if let durationMin, durationMin > 0 {
            facts.append(RecText.duration(durationMin))
        }
        if !genres.isEmpty { facts.append(genres.prefix(2).joined(separator: ", ")) }
        if let age { facts.append("\(age)+") }
        return facts
    }

    /// The ratings as the banner's chips: IMDb and Kinopoisk, the site's own when neither is known.
    var recRatings: [(source: String, value: String)] {
        var ratings: [(source: String, value: String)] = []
        if let imdbRating { ratings.append(("IMDb", KP.ratingText(Float(imdbRating)))) }
        if let kpRating { ratings.append(("КП", KP.ratingText(Float(kpRating)))) }
        if let rtCritic { ratings.append(("RT", "\(rtCritic) %")) }
        if ratings.isEmpty, let siteRating { ratings.append(("Сайт", KP.ratingText(Float(siteRating)))) }
        return ratings
    }
}

/// Russian numbers and lengths for the recommendations' lines.
enum RecText {
    /// «1 сезон», «3 сезона», «5 сезонов».
    static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tens = n % 100
        let ones = n % 10
        let word = (11 ... 14).contains(tens) ? many : ones == 1 ? one : (2 ... 4).contains(ones) ? few : many
        return "\(n) \(word)"
    }

    /// «1 ч 38 мин», «45 мин».
    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? (minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes / 60) ч \(minutes % 60) мин") : "\(minutes) мин"
    }
}

/// A recommended title with what it needs to be drawn.
struct RecItem: Equatable, Identifiable {
    let rec: Recommendation
    let title: TitleFeatures

    var id: String { rec.titleId }
}

/// A personal row on Home, ready to draw.
struct RecRowModel: Equatable, Identifiable {
    let id: String
    let kind: RecRow.Kind
    let title: String
    var items: [RecItem]
}

/// A recommended title on Home: a clean poster, the name and the reason under it («Похоже на «Мост»»); the reason in
/// full under the pointer. Opening it goes through `onOpen` (the recommender learns an
/// opened card isn't one to tire of).
struct RecCardView: View {
    let item: RecItem
    var width: CGFloat?
    let onOpen: () -> Void

    @Environment(\.kpNavigate) private var navigate

    var body: some View {
        Button {
            onOpen()
            navigate(.details(item.title.simple))
        } label: {
            // A clean poster, as in the site's rows; the reason is the line under the name, where the year usually is.
            KPPosterCard(
                title: item.title.name,
                subtitle: item.rec.reason.short.isEmpty ? item.title.cardSubtitle : item.rec.reason.short,
                rating: item.title.cornerRating.map(KP.ratingText),
                ratingColor: item.title.cornerRating.map(KP.ratingColor) ?? .black.opacity(0.62),
                width: width
            ) {
                KPRemoteImage(url: item.title.poster, downsample: KP.cardPosterPixels())
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
        .help(item.rec.reason.long)
    }
}

extension RecCardView: Equatable {
    nonisolated static func == (lhs: RecCardView, rhs: RecCardView) -> Bool {
        lhs.item == rhs.item && lhs.width == rhs.width
    }
}
