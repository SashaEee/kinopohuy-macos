import ComposableArchitecture
import SwiftUI

/// «Досмотреть»: the site's continue list, what's started first, narrowed by the pills (not finished, series, films)
/// and by segments beside them («Продолжить», «Можно начать», «Похоже, бросили?», «Досмотрено»). A click goes on
/// watching; right-click a poster for its page, to take it off the row, mark it watched or take it off the list. In
/// «Похоже, бросили?» each poster has «Бросил» and «Убрать из ряда» under it.
struct WatchingLaterView: View {
    @Bindable var store: StoreOf<WatchingLaterFeature>

    @Environment(\.kpMetrics) private var metrics
    @Environment(\.kpWatchHistory) private var history

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap - 6) {
                VStack(alignment: .leading, spacing: metrics.stackGap + 6) {
                    KPScreenHeader(title: "Досмотреть", subtitle: subtitle)

                    if let movies = store.movies.data, !movies.isEmpty {
                        filters
                    }

                    if store.segment == .abandoned, store.state.count(.abandoned) > 0 {
                        abandonedNote
                            .transition(.opacity)
                    }
                }

                if store.movies.data?.isEmpty == false {
                    let movies = store.filtered
                    if movies.isEmpty {
                        KPEmptyView(message: emptyMessage, symbol: store.segment == nil ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                            .frame(height: 220)
                    } else {
                        KPGrid(items: movies) { movie in
                            VStack(alignment: .leading, spacing: 8) {
                                WatchingLaterCardView(movie: movie)
                                    .equatable()
                                    .kpWatchingMenu(movie) {
                                        store.send(.switchWatched(movie))
                                    } remove: {
                                        store.send(.remove(movie))
                                    } onAction: { action in
                                        perform(action, on: movie)
                                    }

                                if store.segment == .abandoned, store.segments[movie.watchLaterId] == .abandoned {
                                    AbandonedActions {
                                        perform(.dropped, on: movie)
                                    } setAside: {
                                        perform(.continueHidden, on: movie)
                                    }
                                }
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
        .onChange(of: history, initial: true) {
            store.send(.historyChanged(history))
        }
        .onChange(of: RecCardMarks.shared.lastUndone) { _, undone in
            if let undone {
                store.send(.titleRestored(undone.titleId), animation: .smooth(duration: 0.3))
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .dialogSeverity(.critical)
        .confirmationDialog($store.scope(state: \.dropDialog, action: \.dropDialog))
        .kpScreenBackground()
    }

    /// A card's menu or its buttons: recorded by the card's marks (so «Вернуть» on the poster undoes it), and the
    /// segments catch up; «Бросил» asks about the site's list first.
    private func perform(_ action: TitleAction, on movie: MovieWatchLater) {
        guard let titleId = movie.watchLaterId.id else { return }
        if action == .dropped {
            store.send(.dropTapped(movie), animation: .smooth(duration: 0.3))
            return
        }
        RecCardMarks.shared.apply(action, to: titleId)
        store.send(.titleAction(movie, action), animation: .smooth(duration: 0.3))
    }

    /// «Все · Не досмотрено · Сериалы · Фильмы», each with how many it holds; then the segments, a pressed one white
    /// (pressed again, off). They wrap onto a second line in a narrow window.
    private var filters: some View {
        let movies = store.movies.data ?? []
        return FlowLayout(spacing: 8) {
            ForEach(WatchingLaterFeature.Filter.allCases) { filter in
                KPPill(
                    title: filter.title,
                    detail: "\(movies.filter(filter.includes).count)",
                    selected: store.filter == filter
                ) {
                    store.send(.filterSelected(filter), animation: .smooth(duration: 0.3))
                }
            }

            Rectangle()
                .fill(KP.chipStrong)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)

            ForEach(WatchingSegment.allCases) { segment in
                let count = store.state.count(segment)
                KPPill(
                    title: segment.title,
                    detail: "\(count)",
                    selected: store.segment == segment,
                    dimmed: count == 0 && store.segment != segment
                ) {
                    store.send(.segmentSelected(segment), animation: .smooth(duration: 0.3))
                }
                .help(Self.segmentHelp(segment))
            }
        }
        .padding(.horizontal, KP.gutter)
    }

    private static func segmentHelp(_ segment: WatchingSegment) -> String {
        switch segment {
        case .continueWatching: "Смотрели за последний месяц или есть что досмотреть"
        case .canStart: "В списке, но ещё не начато"
        case .abandoned: "Больше двух месяцев без прогресса, досмотрено не больше половины фильма или двух серий"
        case .watched: "Отмечено как просмотренное"
        }
    }

    /// Under the pills in «Похоже, бросили?»: what it means and what to do.
    private var abandonedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KP.sun)
            Text(verbatim: "Больше двух месяцев без прогресса и почти не начато. Нажмите на постер, чтобы вернуться; «Бросил» учтётся во вкусе, «Убрать из ряда» просто спрячет.")
                .font(KP.font(13, .medium))
                .foregroundStyle(KP.fg55)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, KP.gutter)
    }

    private var emptyMessage: String {
        switch store.segment {
        case .continueWatching?: "Ничего начатого за последний месяц"
        case .canStart?: "Всё из списка уже начато"
        case .abandoned?: "Брошенного нет — всё под контролем"
        case .watched?: "Досмотренного пока нет"
        case nil: "Здесь пусто"
        }
    }

    /// «12 в процессе · 30 досмотрено»; under a pill, how many it shows of all.
    private var subtitle: String? {
        guard let movies = store.movies.data, !movies.isEmpty else { return nil }
        guard store.filter == .all, store.segment == nil else { return "\(store.filtered.count) из \(movies.count)" }
        let unwatched = movies.filter { !$0.watched }.count
        return "\(unwatched) в процессе · \(movies.count - unwatched) досмотрено"
    }
}

/// Under a poster in «Похоже, бросили?»: «Бросил» (a weak minus for the taste) and «Убрать из ряда» (just hidden).
private struct AbandonedActions: View {
    let drop: () -> Void
    let setAside: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            SmallAction(title: TitleAction.dropped.title, symbol: "xmark", help: TitleAction.dropped.help, action: drop)
            SmallAction(title: TitleAction.continueHidden.title, symbol: nil, help: TitleAction.continueHidden.help, action: setAside)
        }
    }
}

private struct SmallAction: View {
    let title: String
    let symbol: String?
    let help: String
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                }
                Text(verbatim: title)
            }
            .font(KP.font(11.5, .semibold))
            .foregroundStyle(hover ? KP.fg : KP.fg70)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(hover ? KP.chipStrong : KP.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
