import ComposableArchitecture
import SwiftUI

/// A list of titles (a category, genre, country, collection, the site's lists): the big title, its filters, a grid
/// that loads more as the end comes into view.
struct ListView: View {
    @Bindable var store: StoreOf<ListFeature>

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap - 6) {
                KPScreenHeader(title: store.title) {
                    if !store.isCustomMovies, !store.isList {
                        filters
                    }
                }

                if let movies = store.movies.data, !movies.isEmpty {
                    KPGrid(items: movies) { movie in
                        CardView(movie: movie)
                            .equatable()
                            .onAppear {
                                if store.paginationState == .idle, movies.suffix(12).contains(where: { $0.id == movie.id }) {
                                    store.send(.loadMore)
                                }
                            }
                    }
                }

                if store.paginationState == .loading {
                    HStack(spacing: metrics.cardGap) {
                        ForEach(0 ..< 6, id: \.self) { _ in KPPosterPlaceholder() }
                    }
                    .padding(.horizontal, KP.gutter)
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
                KPEmptyView(message: "Ничего не нашлось — попробуйте другой фильтр", symbol: "line.3.horizontal.decrease.circle")
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
        .kpScreenBackground()
    }

    private var filters: some View {
        Menu {
            if store.isGenre || store.isCollection || store.isCountry {
                Picker("key.filter.select", selection: $store.filter) {
                    ForEach(Filters.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            }

            if store.state.isCategory(.newest) {
                Picker("key.filter.select", selection: $store.newFilter) {
                    ForEach(NewFilters.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            }

            if store.isCategory || store.isCountry {
                Picker("key.genre.select", selection: $store.filterGenre) {
                    ForEach(Genres.allCases.filter { $0 != .show || !store.state.isCategory(.hot) }) { genre in
                        Text(genre.rawValue).tag(genre)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Фильтры", systemImage: "line.3.horizontal.decrease")
        }
        .menuStyle(.button)
        .buttonStyle(KPSecondaryButtonStyle(size: 13))
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(store.movies.isLoading)
    }
}
