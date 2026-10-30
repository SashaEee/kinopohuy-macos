import ComposableArchitecture
import Defaults
import Dependencies
import RecommenderCore
import SwiftUI

extension Defaults.Keys {
    /// The titles «Как вам «…»?» was already shown for (each is asked once), newest last.
    static let recAskedAfterWatch = Key<[String]>("rec_asked_after_watch", default: [])
}

/// As a film reaches its credits, or a season's last episode does: «Как вам «Мост»? [Не моё] [Нравится] [Обожаю] ·
/// Позже» in a small glass pill under the player's top corner. It never stops the picture, answers to 1 · 2 · 3, goes
/// away by itself after 10 s (it waits while the pointer is on it), comes once per title, and only while «Спрашивать
/// оценку после просмотра» is on and the title has no rating yet. HBO Max asks the same way.
struct PostPlayRatingView: View {
    @Environment(StoreOf<PlayerFeature>.self) private var store
    @Environment(\.kpMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.recAskAfterWatch) private var enabled
    @Default(.recAskedAfterWatch) private var asked

    @Dependency(\.recommender) private var recommender

    private enum Phase: Equatable {
        case hidden
        case asking(titleId: String, name: String)
        case thanked(TasteLevel)
    }

    @State private var phase: Phase = .hidden
    @State private var hideTask: Task<Void, Never>?
    /// The countdown line along the pill's bottom (1 → 0 over the time left).
    @State private var remaining: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PostPlayTrigger(onReach: ask)

            switch phase {
            case .hidden:
                EmptyView()
            case let .asking(titleId, name):
                asking(titleId: titleId, name: name)
                    .transition(transition)
            case let .thanked(level):
                thanked(level)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: phase)
        .onDisappear {
            hideTask?.cancel()
        }
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    // MARK: - Pieces

    private func asking(titleId: String, name: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: PostPlayRules.question(name))
                    .font(KP.font(metrics.compact ? 14 : 15, .bold))
                    .foregroundStyle(KP.fg)
                Text(verbatim: "Подборка учтёт ваш ответ")
                    .font(KP.font(11.5, .medium))
                    .foregroundStyle(KP.fg55)
            }
            .lineLimit(1)
            .padding(.trailing, 4)

            ForEach(TasteLevel.allCases, id: \.self) { level in
                Button {
                    rate(level, titleId: titleId)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: level.symbol)
                        Text(verbatim: level.title)
                    }
                }
                .buttonStyle(KPGlassButtonStyle(size: metrics.compact ? 12.5 : 13, height: metrics.compact ? 30 : 32))
                .keyboardShortcut(KeyEquivalent(level.key), modifiers: [])
                .help("\(level.title) — клавиша \(String(level.key))")
            }

            Button {
                hide()
            } label: {
                Text(verbatim: "Позже")
                    .font(KP.font(12.5, .semibold))
                    .foregroundStyle(KP.fg55)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Не сейчас")
        }
        .padding(.vertical, 10)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .overlay(alignment: .bottom) {
            // The time left before it goes, as a fading line.
            GeometryReader { proxy in
                Capsule()
                    .fill(KP.sunGradient)
                    .frame(width: max(0, (proxy.size.width - 36) * remaining), height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .opacity(0.8)
            }
            .frame(height: 2)
            .padding(.bottom, 4)
        }
        .kpGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover { inside in
            if inside {
                // Reading or reaching for a button: it waits.
                hideTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) { remaining = 1 }
            } else {
                scheduleHide(after: 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: PostPlayRules.question(name)))
    }

    private func thanked(_ level: TasteLevel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: level.activeSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KP.sun)
            Text(verbatim: "Спасибо — учтём")
                .font(KP.font(metrics.compact ? 13.5 : 14, .semibold))
                .foregroundStyle(KP.fg)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .kpGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Flow

    private func ask() {
        let titleId = store.movieId
        let name = store.name
        guard case .hidden = phase, PostPlayRules.shouldAsk(enabled: enabled, titleId: titleId, asked: asked, hasRating: false) else { return }

        Task {
            // Rated already (on the page, from a card, a copy of the site's rating): nothing to ask.
            guard await recommender.rating(titleId) == nil else { return }
            asked = PostPlayRules.remembering(titleId, in: asked)
            remaining = 1
            phase = .asking(titleId: titleId, name: name)
            scheduleHide(after: PostPlayRules.visibleSeconds)
        }
    }

    private func rate(_ level: TasteLevel, titleId: String) {
        hideTask?.cancel()
        phase = .thanked(level)
        Task {
            await recommender.rate(titleId, level.level, .app)
        }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            phase = .hidden
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { remaining = 1 }
        withAnimation(.linear(duration: seconds)) { remaining = 0 }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        phase = .hidden
    }
}

/// Watches the playback time (it ticks ten times a second) in a view of its own, so only this empty view redraws
/// with it; tells once what's playing reaches the end worth asking about.
private struct PostPlayTrigger: View {
    let onReach: () -> Void

    @Environment(StoreOf<PlayerFeature>.self) private var store

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: reached) { _, reached in
                if reached { onReach() }
            }
    }

    private var reached: Bool {
        PostPlayRules.reachedEnd(
            isSeries: store.isSeries,
            isLastOfSeason: isLastOfSeason,
            currentTime: store.currentTime,
            duration: store.knownDuration,
            finished: finished
        )
    }

    /// The episode on is its season's last one.
    private var isLastOfSeason: Bool {
        guard let season = store.season, let episode = store.episode else { return false }
        return season.episodes.last?.episodeId == episode.episodeId
    }

    /// Played to its very end (a short film, or the credits skipped to the end).
    private var finished: Bool {
        if store.pauseReason == .finished { return true }
        guard let season = store.season, let episode = store.episode else { return false }
        return store.finishedEpisodes.contains(PlayerFeature.State.episodeKey(season, episode))
    }
}
