import Dependencies
import Observation
import RecommenderCore
import SwiftUI

// MARK: - Doing and undoing

/// What one action changed, so «Вернуть» puts back exactly that: the rating it replaced, or the mark it set.
struct TitleActionUndo: Sendable, Equatable {
    let titleId: String
    let action: TitleAction
    /// The rating before a level was set (nil: there was none).
    let previousRating: Double?

    func revert(_ recommender: RecommenderClient) async {
        if action.rating != nil {
            if let previousRating {
                await recommender.rate(titleId, previousRating, .app)
            } else {
                await recommender.clearRating(titleId)
            }
        } else if let feedback = action.feedback {
            await recommender.removeFeedback(titleId, feedback)
        }
    }
}

extension TitleAction {
    /// Records it for a title (a rating, or a service mark) and says how to undo it.
    func perform(_ titleId: String, _ recommender: RecommenderClient, source: ExplicitRating.Source = .app) async -> TitleActionUndo {
        if let rating {
            let previous = await recommender.rating(titleId)
            await recommender.rate(titleId, rating, source)
            return TitleActionUndo(titleId: titleId, action: self, previousRating: previous)
        }
        if let feedback {
            await recommender.feedback(titleId, feedback)
        }
        return TitleActionUndo(titleId: titleId, action: self, previousRating: nil)
    }
}

// MARK: - What the cards remember

/// The titles acted on from a card's menu in this session: the card dims and says what happened («Больше не покажем»)
/// with «Вернуть», wherever that title's card is drawn (Home, a list, search), until the app quits. The recommender
/// itself keeps the action for good; this is only the visible echo, so a press is felt without a dialog.
@MainActor
@Observable
final class RecCardMarks {
    static let shared = RecCardMarks()

    struct Mark: Equatable {
        let action: TitleAction
        /// After «Уже смотрел», the level given from the card's «Как вам?».
        var rated: TasteLevel?
    }

    private(set) var marks: [String: Mark] = [:]

    /// The latest «Вернуть» (with a serial, so the same title twice still counts as a change): a screen that sorts by
    /// these marks (e.g. «Досмотреть»'s segments) puts the title back.
    struct Undone: Equatable {
        let titleId: String
        let serial: Int
    }

    private(set) var lastUndone: Undone?

    /// Each title's actions in order: undoing waits for them and reverts them newest first.
    @ObservationIgnored private var done: [String: [Task<TitleActionUndo, Never>]] = [:]
    @ObservationIgnored @Dependency(\.recommender) private var recommender

    func mark(_ titleId: String?) -> Mark? {
        titleId.flatMap { marks[$0] }
    }

    /// Records `action` for the title and shows it on its cards.
    func apply(_ action: TitleAction, to titleId: String) {
        withAnimation(.smooth(duration: 0.3)) {
            marks[titleId] = Mark(action: action)
        }
        record(action, for: titleId)
    }

    /// «Как вам?» on a card marked «Уже смотрел»: the level goes in too, and the card says so.
    func rate(_ level: TasteLevel, _ titleId: String) {
        guard var mark = marks[titleId] else {
            apply(TitleAction(level), to: titleId)
            return
        }
        // A second press on the same level takes it back, as the title page's buttons do.
        let previous = mark.rated
        mark.rated = TasteLevel.toggled(current: previous, tapped: level)
        withAnimation(.smooth(duration: 0.25)) {
            marks[titleId] = mark
        }
        if let rated = mark.rated {
            record(TitleAction(rated), for: titleId)
        } else if previous != nil {
            let recommender = recommender
            let pending = done[titleId] ?? []
            done[titleId] = Array(pending.dropLast())
            Task {
                guard let last = pending.last else { return }
                await last.value.revert(recommender)
            }
        }
    }

    /// «Вернуть»: everything done to the title from cards in this session is undone, newest first.
    func undo(_ titleId: String) {
        withAnimation(.smooth(duration: 0.3)) {
            marks[titleId] = nil
        }
        lastUndone = Undone(titleId: titleId, serial: (lastUndone?.serial ?? 0) + 1)
        let recommender = recommender
        let tasks = done.removeValue(forKey: titleId) ?? []
        Task {
            for task in tasks.reversed() {
                await task.value.revert(recommender)
            }
        }
    }

    /// Shows a mark for an action recorded elsewhere (a feature that did the recording itself).
    func show(_ action: TitleAction, for titleId: String) {
        withAnimation(.smooth(duration: 0.3)) {
            marks[titleId] = Mark(action: action)
        }
    }

    func clear(_ titleId: String) {
        marks[titleId] = nil
        done[titleId] = nil
    }

    private func record(_ action: TitleAction, for titleId: String) {
        let recommender = recommender
        let previous = done[titleId]?.last
        let task = Task {
            // In order: an undo of the first must not land after the second.
            _ = await previous?.value
            return await action.perform(titleId, recommender)
        }
        done[titleId, default: []].append(task)
    }
}

// MARK: - On the poster

/// Over a poster acted on: the picture dims, a line says what happened, «Вернуть» takes it back; after «Уже смотрел»,
/// «Как вам?» with the three levels. Lies over the card's link, not inside it, so its buttons get the clicks.
struct RecCardMarkOverlay: View {
    let titleId: String?
    let width: CGFloat
    var aspect: CGFloat = 1.5

    private var marks: RecCardMarks { .shared }

    var body: some View {
        if let titleId, let mark = marks.mark(titleId) {
            ZStack {
                RoundedRectangle(cornerRadius: KP.posterRadius, style: .continuous)
                    .fill(.black.opacity(0.68))
                    .allowsHitTesting(false)

                VStack(spacing: 9) {
                    Image(systemName: mark.rated.map(\.activeSymbol) ?? mark.action.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KP.fg)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(KP.chipStrong))
                        .contentTransition(.symbolEffect(.replace))
                        .allowsHitTesting(false)

                    Text(verbatim: mark.rated.map { "Учтём: «\($0.title.lowercased())»" } ?? mark.action.confirmation)
                        .font(KP.font(12.5, .semibold))
                        .foregroundStyle(KP.fg)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .allowsHitTesting(false)

                    if mark.action == .seen {
                        VStack(spacing: 6) {
                            Text(verbatim: "Как вам?")
                                .font(KP.font(11.5, .medium))
                                .foregroundStyle(KP.fg55)
                                .allowsHitTesting(false)
                            HStack(spacing: 6) {
                                ForEach(TasteLevel.allCases, id: \.self) { level in
                                    Button {
                                        marks.rate(level, titleId)
                                    } label: {
                                        Image(systemName: mark.rated == level ? level.activeSymbol : level.symbol)
                                    }
                                    .buttonStyle(KPIconButtonStyle(diameter: 28))
                                    .help(level.title)
                                }
                            }
                        }
                    }

                    Button {
                        marks.undo(titleId)
                    } label: {
                        Text(verbatim: "Вернуть")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 12))
                    .help("Отменить: тайтл снова будет в рекомендациях")
                }
                .padding(10)
            }
            .frame(width: width, height: width * aspect)
            .transition(.opacity)
        }
    }
}

// MARK: - The poster's menu

extension View {
    /// A title card's right-click menu for recommendations: «Не моё», «Скрыть», «Уже смотрел», «Не сегодня», or
    /// «Вернуть» once one was chosen.
    func kpTitleFeedbackMenu(_ titleId: String?) -> some View {
        modifier(TitleFeedbackMenu(titleId: titleId))
    }
}

private struct TitleFeedbackMenu: ViewModifier {
    let titleId: String?

    func body(content: Content) -> some View {
        if let titleId {
            content.contextMenu {
                TitleFeedbackMenuItems(titleId: titleId, actions: [.notForMe, .hidden, .seen, .notToday])
            }
        } else {
            content
        }
    }
}

/// The recommendation items of a card's menu; with an action already on the card, «Вернуть» first.
struct TitleFeedbackMenuItems: View {
    let titleId: String
    let actions: [TitleAction]
    /// Instead of recording here (a screen that records and redraws itself, e.g. «Досмотреть»).
    var perform: ((TitleAction) -> Void)?

    private var marks: RecCardMarks { .shared }

    var body: some View {
        if let mark = marks.mark(titleId) {
            Button {
                marks.undo(titleId)
            } label: {
                Label {
                    Text(verbatim: "Вернуть («\(mark.action.title)»)")
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            Divider()
        }
        ForEach(actions, id: \.self) { action in
            Button {
                if let perform {
                    perform(action)
                } else {
                    marks.apply(action, to: titleId)
                }
            } label: {
                Label {
                    Text(verbatim: action.title)
                } icon: {
                    Image(systemName: action.symbol)
                }
            }
            .help(action.help)
        }
    }
}
