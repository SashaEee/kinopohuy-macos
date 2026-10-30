import ComposableArchitecture
import SwiftUI

/// «Закладки»: the folders as capsules (drop a poster on one to move it there, right-click to rename or delete),
/// the chosen folder's titles in a grid.
struct BookmarksView: View {
    @Bindable var store: StoreOf<BookmarksFeature>

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap - 10) {
                KPScreenHeader(title: "Закладки", subtitle: subtitle) {
                    Button {
                        store.send(.createTapped)
                    } label: {
                        Label("Новая папка", systemImage: "plus")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.bookmarks.data == nil)

                    filters
                }

                if let bookmarks = store.bookmarks.data, !bookmarks.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(bookmarks) { bookmark in
                            FolderPill(bookmark: bookmark, selected: store.selectedBookmark == bookmark.bookmarkId)
                                .environment(store)
                        }
                    }
                    .padding(.horizontal, KP.gutter)
                }

                if let movies = store.movies.data, !movies.isEmpty {
                    KPGrid(items: movies) { movie in
                        CardView(movie: movie, draggable: true)
                            .equatable()
                            .contextMenu {
                                Button("Убрать из закладок", role: .destructive) {
                                    if let movieId = movie.movieId.id {
                                        store.send(.removeMovies([movieId]))
                                    }
                                }
                                .disabled(movie.movieId.id == nil)
                            }
                            .onAppear {
                                if store.paginationState == .idle, movies.suffix(12).contains(where: { $0.id == movie.id }) {
                                    store.send(.loadMore)
                                }
                            }
                    }
                } else if let error = store.movies.error {
                    KPErrorView(message: error.kpMessage) { store.send(.reloadMovies) }
                        .frame(height: 280)
                } else if store.bookmarks.data?.isEmpty == false, let movies = store.movies.data, movies.isEmpty {
                    KPEmptyView(message: store.selectedBookmark == nil ? "Выберите папку" : "В этой папке пока пусто", symbol: "bookmark")
                        .frame(height: 280)
                } else if store.movies.isLoading, store.selectedBookmark != nil {
                    KPLoadingView().frame(height: 200)
                }

                if store.paginationState == .loading {
                    KPLoadingView().frame(height: 80)
                }
            }
            .kpBelowTopBar()
            .padding(.bottom, metrics.screenBottom)
        }
        .scrollIndicators(.automatic)
        .overlay {
            if let error = store.bookmarks.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reloadBookmarks(reset: true))
                }
            } else if let bookmarks = store.bookmarks.data, bookmarks.isEmpty {
                VStack(spacing: 16) {
                    KPEmptyView(message: "Закладок пока нет", symbol: "bookmark").frame(height: 120)
                    Button("Создать папку") { store.send(.createTapped) }
                        .buttonStyle(KPPrimaryButtonStyle(size: 14))
                }
            } else if store.bookmarks.isLoading {
                KPLoadingView()
            }
        }
        .background {
            Button("") { store.send(.reloadBookmarks(reset: true)) }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .onChange(of: store.bookmarks.data?.first?.bookmarkId, initial: true) { _, first in
            // A folder open from the start: the first one, unless one is chosen already.
            if store.selectedBookmark == nil, let first {
                store.selectedBookmark = first
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .dialogSeverity(.critical)
        .sheet(item: $store.scope(state: \.destination?.renameBookmark, action: \.destination.renameBookmark)) { store in
            RenameBookmarkSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.createBookmark, action: \.destination.createBookmark)) { store in
            CreateBookmarkSheetView(store: store)
        }
        .kpScreenBackground()
    }

    private var subtitle: String? {
        guard let bookmarks = store.bookmarks.data, let selected = bookmarks.first(where: { $0.bookmarkId == store.selectedBookmark }) else { return nil }
        return "\(selected.name) · \(selected.count)"
    }

    private var filters: some View {
        Menu {
            Picker("Сортировка", selection: $store.filter) {
                ForEach(BookmarkFilters.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.inline)

            Picker("Жанр", selection: $store.genre) {
                ForEach(Genres.allCases) { genre in
                    Text(genre.rawValue).tag(genre)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Фильтры", systemImage: "line.3.horizontal.decrease")
        }
        .menuStyle(.button)
        .buttonStyle(KPSecondaryButtonStyle(size: 13))
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(store.movies.isLoading || store.selectedBookmark == nil)
    }
}

/// A folder: its name and how many titles; the chosen one white. A poster dropped on it moves there.
private struct FolderPill: View {
    let bookmark: Bookmark
    let selected: Bool

    @Environment(StoreOf<BookmarksFeature>.self) private var store
    @Environment(\.kpMetrics) private var metrics
    @State private var hover = false
    @State private var dropTarget = false

    var body: some View {
        Button {
            store.selectedBookmark = bookmark.bookmarkId
        } label: {
            HStack(spacing: 7) {
                Text(verbatim: bookmark.name)
                    .font(KP.font(metrics.pillFont, selected ? .semibold : .medium))
                    .lineLimit(1)
                Text(verbatim: "\(bookmark.count)")
                    .font(KP.font(metrics.pillFont - 1.5, .semibold).monospacedDigit())
                    .foregroundStyle(selected ? KP.ink.opacity(0.55) : KP.fg38)
                    .contentTransition(.numericText(value: Double(bookmark.count)))
            }
            .foregroundStyle(selected ? KP.ink : KP.fg)
            .padding(.horizontal, metrics.pillPaddingH)
            .padding(.vertical, metrics.pillPaddingV)
            .background(Capsule().fill(selected ? KP.fg : dropTarget ? KP.sun.opacity(0.5) : hover ? KP.chipStrong : KP.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Переименовать") { store.send(.renameTapped(bookmark)) }
            Button("Удалить папку", role: .destructive) { store.send(.deleteBookmark(bookmark)) }
        }
        .dropDestination(for: MovieSimple.self) { movies, _ in
            guard !selected, !movies.compactMap(\.movieId.id).isEmpty else { return false }
            store.send(.moveMovies(movies, to: bookmark))
            return true
        } isTargeted: { dropTarget = $0 && !selected }
    }
}
