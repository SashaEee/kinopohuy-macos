import ComposableArchitecture
import Defaults
import SwiftUI

/// A big search field under the top bar (typing searches as you go), the results in a grid under it. With nothing
/// typed: «Недавние запросы» (the last searches that led to a title) and «Популярно сейчас».
struct SearchView: View {
    @Bindable var store: StoreOf<SearchFeature>

    @FocusState private var fieldFocused: Bool
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap - 6) {
                field

                if let movies = store.movies.data, !movies.isEmpty {
                    KPGrid(items: movies) { movie in
                        CardView(movie: movie) {
                            store.send(.resultOpened)
                        }
                        .equatable()
                        .onAppear {
                            if store.paginationState == .idle, movies.suffix(12).contains(where: { $0.id == movie.id }) {
                                store.send(.loadMore)
                            }
                        }
                    }
                } else if let error = store.movies.error {
                    KPErrorView(message: error.kpMessage) { store.send(.reload) }
                        .frame(height: 300)
                } else if store.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    idle
                } else if let movies = store.movies.data, movies.isEmpty {
                    KPEmptyView(message: "Ничего не нашлось", symbol: "magnifyingglass")
                        .frame(height: 300)
                } else if store.movies.isLoading {
                    KPLoadingView().frame(height: 200)
                }

                if store.paginationState == .loading {
                    placeholders(6)
                }
            }
            .kpBelowTopBar()
            .padding(.bottom, metrics.screenBottom)
        }
        .scrollIndicators(.automatic)
        .onAppear {
            store.send(.onAppear)
            fieldFocused = true
        }
        .kpScreenBackground()
    }

    private var field: some View {
        let compact = metrics.compact
        let radius: CGFloat = compact ? 12 : 14
        return HStack(spacing: compact ? 10 : 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundStyle(KP.fg55)
            TextField(text: $store.query) {
                Text(verbatim: "Фильмы, сериалы, мультфильмы…")
                    .foregroundStyle(KP.fg38)
            }
            .textFieldStyle(.plain)
            .font(KP.font(compact ? 19 : 21, .semibold))
            .foregroundStyle(KP.fg)
            .focused($fieldFocused)
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(KPIconButtonStyle(diameter: 26))
            }
        }
        .padding(.horizontal, compact ? 16 : 18)
        .padding(.vertical, compact ? 10 : 12)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(KP.surface))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(fieldFocused ? KP.fg38 : KP.line, lineWidth: 1))
        .frame(maxWidth: compact ? 680 : 760)
        .padding(.horizontal, KP.gutter)
    }

    /// Nothing typed yet: where you searched lately, then what's watched now.
    @ViewBuilder
    private var idle: some View {
        VStack(alignment: .leading, spacing: metrics.sectionGap) {
            if !store.recent.isEmpty {
                VStack(alignment: .leading, spacing: metrics.stackGap) {
                    HStack(alignment: .firstTextBaseline) {
                        KPSectionTitle(title: "Недавние запросы")
                        Spacer()
                        QuietTextButton(title: "Очистить") {
                            store.send(.recentCleared, animation: .smooth(duration: 0.3))
                        }
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(store.recent, id: \.self) { query in
                            KPPill(title: query) {
                                store.send(.recentTapped(query))
                                fieldFocused = true
                            }
                            .contextMenu {
                                Button {
                                    store.send(.recentRemoved(query), animation: .smooth(duration: 0.3))
                                } label: {
                                    Text(verbatim: "Убрать из недавних")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, KP.gutter)
                .transition(.opacity)
            }

            if let popular = store.popular.data, !popular.isEmpty {
                VStack(alignment: .leading, spacing: metrics.stackGap) {
                    KPSectionTitle(title: "Популярно сейчас")
                        .padding(.horizontal, KP.gutter)
                    KPGrid(items: popular) { movie in
                        CardView(movie: movie)
                            .equatable()
                    }
                }
                .transition(.opacity)
            } else if store.popular.isLoading {
                VStack(alignment: .leading, spacing: metrics.stackGap) {
                    KPSectionTitle(title: "Популярно сейчас")
                        .padding(.horizontal, KP.gutter)
                    placeholders(6)
                }
            } else if store.recent.isEmpty {
                KPEmptyView(message: "Начните вводить название — результаты появятся сразу", symbol: "text.magnifyingglass")
                    .frame(height: 300)
            }
        }
    }

    private func placeholders(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: metrics.cardGap) {
            ForEach(0 ..< count, id: \.self) { _ in KPPosterPlaceholder() }
        }
        .padding(.horizontal, KP.gutter)
    }
}

/// «Очистить»: a quiet text button that brightens under the pointer.
private struct QuietTextButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(KP.font(13, .semibold))
                .foregroundStyle(hover ? KP.fg : KP.fg55)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}
