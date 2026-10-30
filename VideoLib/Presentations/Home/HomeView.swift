import ComposableArchitecture
import Kingfisher
import SwiftUI

/// The banner (a few of the first row's titles taking turns) under the top bar; when signed in «Продолжить просмотр»
/// (a click goes on watching), «Новые серии» and «Похоже на «…»»; then the site's rows, each scrolling sideways, more
/// loading as the last one comes into view.
struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>

    @Environment(\.kpMetrics) private var metrics
    @Environment(\.appearsActive) private var appearsActive
    @State private var heroOnScreen = true

    /// The banner's picture decoded at about its drawn size (see `hero`).
    static let heroPixels = CGSize(width: 1400, height: 2100)

    var body: some View {
        ScrollView(.vertical) {
            // A plain stack: Home has a handful of rows, built once, rather than each one (a scroll view with its cards)
            // being made the moment it scrolls into view, mid-gesture. Each row stays lazy sideways.
            VStack(alignment: .leading, spacing: metrics.sectionGap) {
                hero
                    .onScrollVisibilityChange(threshold: 0.2) { heroOnScreen = $0 }

                if !store.continueWatching.isEmpty {
                    KPRow(title: "Продолжить просмотр", count: KPDemo.isOn ? nil : store.continueWatching.count, items: store.continueWatching, seeAll: {
                        store.send(.delegate(.showWatchingLater), animation: .spring(response: 0.38, dampingFraction: 0.82))
                    }) { movie in
                        WatchingLaterCardView(movie: movie)
                            .equatable()
                            .kpWatchingMenu(movie) {
                                store.send(.switchWatched(movie))
                            } remove: {
                                store.send(.remove(movie))
                            }
                    }
                    .transition(.opacity)
                }

                if !store.newEpisodes.isEmpty {
                    KPRow(title: "Новые серии", items: store.newEpisodes, seeAll: {
                        store.send(.seriesUpdatesTapped)
                    }) { episode in
                        NewEpisodeCardView(episode: episode)
                            .equatable()
                    }
                    .transition(.opacity)
                }

                if let similar = store.similar {
                    KPRow(title: "Похоже на «\(Self.short(similar.name))»", items: similar.movies) { movie in
                        CardView(movie: movie)
                            .equatable()
                    }
                    .transition(.opacity)
                }

                if let categories = store.categories.data {
                    ForEach(categories) { category in
                        KPRow(title: category.title, items: category.movies, seeAll: {
                            store.send(.delegate(.push(.category(category.category))))
                        }) { movie in
                            CardView(movie: movie)
                                .equatable()
                        }
                    }

                    // The next row once this comes into view.
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            if store.paginationState == .idle {
                                store.send(.loadMore())
                            }
                        }
                }

                if store.paginationState.error != nil {
                    HStack {
                        Text(verbatim: "Не удалось загрузить следующий ряд")
                            .font(KP.font(metrics.body, .medium))
                            .foregroundStyle(KP.fg55)
                        Button("Повторить") { store.send(.loadMore(reset: true)) }
                            .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    }
                    .padding(.horizontal, KP.gutter)
                } else if store.paginationState == .loading {
                    HStack(spacing: metrics.cardGap) {
                        ForEach(0 ..< 7, id: \.self) { _ in KPPosterPlaceholder() }
                    }
                    .padding(.horizontal, KP.gutter)
                }
            }
            .padding(.bottom, metrics.screenBottom)
        }
        .scrollIndicators(.automatic)
        .kpReportsScrolling()
        // The banner turns only while it's on screen and the window is in front.
        .onChange(of: heroOnScreen && appearsActive, initial: true) { _, visible in
            store.send(.heroVisible(visible))
        }
        .ignoresSafeArea(edges: .top)
        .overlay {
            if let error = store.categories.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
            } else if let categories = store.categories.data, categories.isEmpty {
                KPEmptyView(message: "На главной пока ничего нет")
            }
        }
        .background {
            Button("") { store.send(.reload) }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .dialogSeverity(.critical)
        .kpScreenBackground()
    }

    /// A long name cut, so the row's heading stays on one line.
    private static func short(_ name: String) -> String {
        name.count > 40 ? name.prefix(38).trimmingCharacters(in: .whitespaces) + "…" : name
    }

    @ViewBuilder
    private var hero: some View {
        if store.hero.indices.contains(store.heroIndex) {
            let movie = store.hero[store.heroIndex]
            let simple = MovieSimple(movieId: movie.movieId, name: movie.nameRussian, poster: movie.poster)

            KPHero(
                kicker: "Сейчас в тренде",
                title: movie.nameRussian,
                original: movie.nameOriginal,
                facts: movie.heroFacts,
                ratings: movie.heroRatings,
                description: movie.description
            ) {
                // Decoded at about the size it's drawn (the sharp side is at most ~620 pt wide, 2×), its card-sized copy
                // (already in memory from the first row) showing until then.
                KPRemoteImage(url: movie.hposter, fallback: movie.poster, downsample: Self.heroPixels, fallbackDownsample: KP.cardPosterPixels())
            } actions: {
                Button {
                    store.send(.delegate(.push(.watch(simple))))
                } label: {
                    Label("Смотреть", systemImage: "play.fill")
                }
                .buttonStyle(KPPrimaryButtonStyle())

                Button {
                    store.send(.delegate(.push(.details(simple))))
                } label: {
                    Label("Подробнее", systemImage: "info.circle")
                }
                .buttonStyle(KPSecondaryButtonStyle())
            }
            .id(movie.movieId)
            .transition(.opacity)
            .onHover { store.send(.heroHeld($0)) }
            .overlay(alignment: .bottomTrailing) {
                if store.hero.count > 1 {
                    HeroDots(count: store.hero.count, index: store.heroIndex, held: store.heroHeld) { index in
                        store.send(.heroSelected(index), animation: .easeInOut(duration: 0.5))
                    }
                    .padding(.trailing, KP.gutter)
                    .padding(.bottom, metrics.heroBottom + 8) // level with the buttons' row
                }
            }
            .task(id: store.hero.map(\.movieId)) {
                // The other banners' pictures are fetched ahead, so a change is a crossfade, not a blank.
                ImagePrefetcher(urls: store.hero.compactMap { URL(string: $0.hposter) }, options: [.processor(DownsamplingImageProcessor(size: Self.heroPixels))]).start()
            }
        } else if store.heroFailed || store.categories.error != nil {
            // No banner: the rows start under the top bar.
            Color.clear.frame(height: KP.topBarHeight)
        } else {
            // The first titles' pages are still coming: the banner's space, so the rows don't jump.
            KPLoadingView()
                .frame(height: metrics.heroHome)
        }
    }
}

extension MovieDetailed {
    /// «2024 · США, Великобритания · Драма, Триллер · 2 ч 4 мин · 16+».
    var heroFacts: [String] {
        var facts: [String] = []
        if let year = displayYear { facts.append(year) }
        if let countries, !countries.isEmpty { facts.append(countries.prefix(2).map(\.name).joined(separator: ", ")) }
        if let genres, !genres.isEmpty { facts.append(genres.prefix(2).map(\.name).joined(separator: ", ")) }
        if let duration, duration > 0 {
            facts.append(duration >= 60 ? "\(duration / 60) ч \(duration % 60) мин" : "\(duration) мин")
        }
        if let ageRestriction, !ageRestriction.isEmpty { facts.append(ageRestriction) }
        return facts
    }

    /// The year, from «Год» or, for a film that has only a release date, from that date.
    var displayYear: String? {
        if let year, !year.isEmpty { return year }
        guard let releaseDate, let range = releaseDate.range(of: "(19|20)\\d\\d", options: .regularExpression) else { return nil }
        return String(releaseDate[range])
    }

    var heroRatings: [(source: String, value: String)] {
        var ratings: [(source: String, value: String)] = []
        if let imdbRating { ratings.append(("IMDb", KP.ratingText(imdbRating.value))) }
        if let kpRating { ratings.append(("КП", KP.ratingText(kpRating.value))) }
        if ratings.isEmpty, let rating { ratings.append(("Сайт", KP.ratingText(rating))) }
        return ratings
    }
}

/// The banners' dots: the current one long, filling up as its 10 s run out (full and still while the pointer is on
/// the banner).
private struct HeroDots: View {
    let count: Int
    let index: Int
    let held: Bool
    let select: (Int) -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { i in
                Button {
                    select(i)
                } label: {
                    Capsule()
                        .fill(KP.fg38)
                        .overlay(alignment: .leading) {
                            if i == index {
                                Capsule()
                                    .fill(KP.fg)
                                    .frame(width: max(8, 26 * progress))
                            }
                        }
                        .frame(width: i == index ? 26 : 8, height: 8)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: "\(index)-\(held)") {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { progress = held ? 1 : 0 }
            guard !held else { return }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 9.97)) { progress = 1 }
        }
    }
}

/// A card in «Новые серии»: «Новая» at the corner, the episode on the poster («5 сезон, 8 серия»), the day and the
/// voice-over under it. A followed series that isn't in the continue list gets its poster from its page a moment later.
private struct NewEpisodeCardView: View {
    let episode: HomeFeature.NewEpisode

    var body: some View {
        KPRouteLink(route: .details(episode.simple)) {
            KPPosterCard(title: episode.name, subtitle: episode.detail, kind: "Новая", note: episode.place) {
                ZStack {
                    KP.surface
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(KP.fg38)
                    if let poster = episode.poster {
                        KPRemoteImage(url: poster, downsample: KP.cardPosterPixels(), clearPlaceholder: true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

extension NewEpisodeCardView: Equatable {
    nonisolated static func == (lhs: NewEpisodeCardView, rhs: NewEpisodeCardView) -> Bool {
        lhs.episode == rhs.episode
    }
}
