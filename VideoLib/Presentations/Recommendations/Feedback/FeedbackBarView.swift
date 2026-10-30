import ComposableArchitecture
import RecommenderCore
import SwiftUI

/// Next to the site's stars: «Не моё · Нравится · Обожаю» as three small toggles (the chosen one white; pressing it
/// again takes it back) and «…» with the quieter marks. Marks that are on line up underneath, each with «×».
struct FeedbackBarView: View {
    let store: StoreOf<FeedbackBarFeature>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(TasteLevel.allCases, id: \.self) { level in
                    TasteToggleButton(level: level, selected: store.level == level, invites: store.asksAfterSeen) {
                        store.send(.levelTapped(level), animation: .snappy(duration: 0.22))
                    }
                }

                moreMenu

                if store.asksAfterSeen {
                    Text(verbatim: "Уже смотрели — как вам?")
                        .font(KP.font(12.5, .medium))
                        .foregroundStyle(KP.sun)
                        .padding(.leading, 4)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
                }
            }
            .opacity(store.isLoaded ? 1 : 0.5)

            if !store.activeActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(store.activeActions, id: \.self) { action in
                        MarkChip(action: action) {
                            if let kind = action.feedback {
                                store.send(.markRemoved(kind), animation: .snappy(duration: 0.22))
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: store.asksAfterSeen)
        .onAppear {
            store.send(.onAppear)
        }
    }

    /// «…»: the marks, ticked while they're on.
    private var moreMenu: some View {
        Menu {
            ForEach(FeedbackBarFeature.State.menuActions, id: \.self) { action in
                let isOn = action.feedback.map(store.marks.contains) ?? false
                Toggle(isOn: Binding(get: { isOn }, set: { _ in
                    store.send(.markToggled(action), animation: .snappy(duration: 0.22))
                })) {
                    Label {
                        Text(verbatim: action.title)
                    } icon: {
                        Image(systemName: action.symbol)
                    }
                }
                .help(action.help)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(KPIconButtonStyle(diameter: 28))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Ещё: скрыть, уже смотрел, не сегодня, смотрел не я")
    }
}

/// One of the three levels: a small capsule, white while chosen; it bounces as it's chosen, and glows softly while the
/// bar asks for a rating.
private struct TasteToggleButton: View {
    let level: TasteLevel
    let selected: Bool
    let invites: Bool
    let action: () -> Void

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: selected ? level.activeSymbol : level.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .symbolEffect(.bounce, options: .speed(1.4), value: selected && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: level.title)
                    .font(KP.font(12.5, .semibold))
            }
            .foregroundStyle(selected ? KP.ink : hover ? KP.fg : KP.fg80)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(selected ? KP.fg : hover ? KP.chipStrong : KP.chip))
            .overlay {
                Capsule()
                    .strokeBorder(KP.sun.opacity(invites && !selected ? 0.7 : 0), lineWidth: 1.5)
                    .phaseAnimator(invites && !reduceMotion ? [1.0, 0.35] : [1.0]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.8)
                    }
            }
            .contentShape(Capsule())
            .scaleEffect(hover && !selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
        .help(selected ? "Убрать оценку «\(level.title)»" : level.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A mark that's on («Скрыто», «Не сегодня»), with «×» to take it back.
private struct MarkChip: View {
    let action: TitleAction
    let remove: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Image(systemName: action.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(verbatim: action.activeLabel)
                    .font(KP.font(12, .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hover ? KP.fg : KP.fg38)
            }
            .foregroundStyle(KP.fg70)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(hover ? KP.chip : KP.chip.opacity(0.55)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Отменить «\(action.title)»")
    }
}
