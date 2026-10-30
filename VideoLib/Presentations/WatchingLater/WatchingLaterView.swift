import ComposableArchitecture
import SwiftUI

/// «Досмотреть»: the site's continue list, what's started first, narrowed by the pills (not finished, series, films).
/// A click goes on watching; right-click a poster for its page, to mark it watched or take it off.
struct WatchingLaterView: View {
    @Bindable var store: StoreOf<WatchingLaterFeature>

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap - 6) {
                VStack(alignment: .leading, spacing: metrics.stackGap + 6) {
                    KPScreenHeader(title: "Досмотреть", subtitle: subtitle)

                    if let movies = store.movies.data, !movies.isEmpty {
                        filters
                    }
                }

                if store.movies.data?.isEmpty == false {
                    let movies = store.filtered
                    if movies.isEmpty {
                        KPEmptyView(message: "Здесь пусто", symbol: "line.3.horizontal.decrease.circle")
                            .frame(height: 220)
                    } else {
                        KPGrid(items: movies) { movie in
                            WatchingLaterCardView(movie: movie)
                                .equatable()
                                .kpWatchingMenu(movie) {
                                    store.send(.switchWatched(movie))
                                } remove: {
                                    store.send(.remove(movie))
                                }
                        }
                    }
                }
            }
            .kpBelowTopBar()
            .padding(.bottom, metrics.screenBottom)
        }
        .scrollIndicators(.automatic)
        .overlay {
            if let error = store.movies.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
            } else if let movies = store.movies.data, movies.isEmpty {
                KPEmptyView(message: "Здесь появится то, что вы начали смотреть", symbol: "clock.arrow.circlepath")
            } else if store.movies.isLoading {
                KPLoadingView()
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

    /// «Все · Не досмотрено · Сериалы · Фильмы», each with how many it holds.
    private var filters: some View {
        let movies = store.movies.data ?? []
        return HStack(spacing: 8) {
            ForEach(WatchingLaterFeature.Filter.allCases) { filter in
                KPPill(
                    title: filter.title,
                    detail: "\(movies.filter(filter.includes).count)",
                    selected: store.filter == filter
                ) {
                    store.send(.filterSelected(filter), animation: .smooth(duration: 0.3))
                }
            }
        }
        .padding(.horizontal, KP.gutter)
    }

    /// «12 в процессе · 30 досмотрено»; under a pill, how many it shows of all.
    private var subtitle: String? {
        guard let movies = store.movies.data, !movies.isEmpty else { return nil }
        guard store.filter == .all else { return "\(store.filtered.count) из \(movies.count)" }
        let unwatched = movies.filter { !$0.watched }.count
        return "\(unwatched) в процессе · \(movies.count - unwatched) досмотрено"
    }
}
