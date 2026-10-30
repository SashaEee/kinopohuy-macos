import SwiftUI

struct CardView: View {
    private let movie: MovieSimple
    private let draggable: Bool
    private let fixedWidth: CGFloat?
    private let onOpen: (() -> Void)?
    private let feedbackMenu: Bool

    @Environment(\.kpMetrics) private var metrics
    @Environment(\.kpNavigate) private var navigate
    @Environment(\.kpWatchHistory) private var history
    private var width: CGFloat { fixedWidth ?? metrics.card }

    /// reservesSpace: kept for the callers; every card now keeps two lines for its name. width: nil is the size tier's.
    /// onOpen: runs as the card opens its title (search remembers the query that led there).
    /// feedbackMenu: right-click «Не моё · Скрыть · Уже смотрел · Не сегодня»; by default on, except on draggable cards
    /// (a bookmarks folder), whose caller puts its own menu on them and an inner one would hide it.
    init(movie: MovieSimple, draggable: Bool = false, reservesSpace _: Bool = false, width: CGFloat? = nil, feedbackMenu: Bool? = nil, onOpen: (() -> Void)? = nil) {
        self.movie = movie
        self.draggable = draggable
        fixedWidth = width
        self.feedbackMenu = feedbackMenu ?? !draggable
        self.onOpen = onOpen
    }

    /// How far this Mac got into it, for a film only: a series' row is its last episode played here, which may be long
    /// behind where you are (watched on, say, the TV since); «Продолжить просмотр» checks that against the site.
    private var filmProgress: Double? {
        guard let entry = history[movie.movieId.id], entry.season.isEmpty, entry.episode.isEmpty else { return nil }
        return entry.fraction
    }

    var body: some View {
        Group {
            if let onOpen {
                // KPRouteLink's button, with `onOpen` run first.
                Button {
                    onOpen()
                    navigate(.details(movie))
                } label: {
                    card
                }
                .accessibilityAddTraits(.isLink)
            } else {
                KPRouteLink(route: .details(movie)) {
                    card
                }
            }
        }
        .buttonStyle(.plain)
        // Acted on from the menu: the poster says so, with «Вернуть» (over the link, so its buttons get the clicks).
        .overlay(alignment: .top) {
            RecCardMarkOverlay(titleId: movie.movieId.id, width: width)
        }
        .viewModifier { view in
            if feedbackMenu {
                view.kpTitleFeedbackMenu(movie.movieId.id)
            } else {
                view
            }
        }
    }

    private var card: some View {
        KPPosterCard(
            title: movie.name,
            subtitle: movie.details,
            rating: movie.cat?.rating.map(KP.ratingText),
            ratingColor: movie.cat?.rating.map(KP.ratingColor) ?? .black.opacity(0.62),
            note: movie.info?.title,
            progress: filmProgress,
            width: width,
            interactive: RecCardMarks.shared.mark(movie.movieId.id) == nil
        ) {
            KPRemoteImage(url: movie.poster, downsample: KP.cardPosterPixels())
        }
        .viewModifier { view in
            if draggable {
                view.draggable(movie)
            } else {
                view
            }
        }
    }
}

extension CardView: Equatable {
    nonisolated static func == (lhs: CardView, rhs: CardView) -> Bool {
        lhs.movie.id == rhs.movie.id
    }
}
