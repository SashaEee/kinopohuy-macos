import ComposableArchitecture
import SwiftUI

/// Netflix-style: a few seconds into a pause with nothing touched, the picture dims from the left and says what's on:
/// «Вы смотрите» (or «Серия закончилась»), the title, the season and episode with its name and the voice-over, the
/// facts and a few lines of the description. Any movement or key brings the controls back. It lays out to the
/// window's width like a banner, puts no glass over the picture and never reads the playback time (that ticks ten
/// times a second).
struct PlayerPauseScreenView: View {
    @Environment(StoreOf<PlayerFeature>.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shown = store.isPauseScreenShown

        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let scale = min(max(width / 1440, 0.82), 1.3)

            ZStack(alignment: .leading) {
                dim
                    .opacity(shown ? 1 : 0)
                    .animation(shown ? dimIn : out, value: shown)

                info(scale: scale, height: height)
                    .frame(maxWidth: min(width * 0.46, 640 * scale), alignment: .leading)
                    .padding(.leading, KP.gutter * 2 * scale)
                    .padding(.bottom, height * 0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 12 * scale)
                    .animation(shown ? textIn : out, value: shown)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!shown)
    }

    // MARK: - Dim

    /// Darkest at the left, under the text; the paused frame stays readable on the right. Deeper after the sleep
    /// timer (the room is likely dark) and with Increase Contrast.
    private var dim: some View {
        let deep = store.pauseReason == .sleepTimer || contrast == .increased

        return ZStack {
            Color.black.opacity(deep ? 0.55 : 0.4)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.62), location: 0),
                    .init(color: .black.opacity(0.35), location: 0.38),
                    .init(color: .clear, location: 0.72),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    // MARK: - Text

    private func info(scale s: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: store.pauseKicker.uppercased())
                .font(KP.font(max(13 * s, 11), .bold))
                .tracking(1.6)
                .foregroundStyle(KP.fg70)

            Text(verbatim: store.name)
                .font(KP.font((store.name.count > 28 ? 44 : 56) * s, .heavy))
                .tracking(-0.9)
                .foregroundStyle(KP.fg)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.35), radius: 24)
                .padding(.top, 10 * s)

            if let episode = episodeLabel {
                HStack(spacing: 0) {
                    Text(verbatim: episode)
                        .font(KP.font(21 * s, .semibold))
                        .foregroundStyle(KP.fg)
                        .layoutPriority(1)
                    if let rest = episodeDetail {
                        Text(verbatim: "  ·  \(rest)")
                            .font(KP.font(21 * s, .medium))
                            .foregroundStyle(KP.fg80)
                    }
                }
                .lineLimit(1)
                .padding(.top, 14 * s)
            }

            if !facts.isEmpty {
                Text(verbatim: facts.joined(separator: "  ·  "))
                    .font(KP.font(max(15 * s, 13), .medium).monospacedDigit())
                    .foregroundStyle(KP.fg55)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, episodeLabel == nil ? 14 * s : 8 * s)
            }

            if let synopsis = store.synopsis {
                Text(verbatim: synopsis)
                    .font(KP.font(max(17 * s, 15)))
                    .lineSpacing(5 * s)
                    .foregroundStyle(KP.fg70)
                    .lineLimit(height < 600 ? 3 : height < 1000 ? 4 : 5)
                    .frame(maxWidth: 560 * s, alignment: .leading)
                    .padding(.top, 20 * s)
            }
        }
    }

    /// «1 сезон, 4 серия», for a series.
    private var episodeLabel: String? {
        guard store.isSeries, let season = store.season, let episode = store.episode else { return nil }
        let s = season.name.first?.isNumber == true ? "\(season.name) сезон" : season.name
        let e = episode.name.first?.isNumber == true ? "\(episode.name) серия" : episode.name
        return "\(s), \(e)"
    }

    /// «Пилот» · the voice-over, after the episode.
    private var episodeDetail: String? {
        var parts: [String] = []
        if let title = store.episodeTitle { parts.append("«\(title)»") }
        if !store.voiceActing.name.isEmpty { parts.append(store.voiceActing.name) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// The title's facts; for a film the voice-over goes last, so it's the first to be cut when the line runs long.
    private var facts: [String] {
        guard !store.isSeries, !store.voiceActing.name.isEmpty else { return store.facts }
        return store.facts + [store.voiceActing.name]
    }

    // MARK: - Motion

    /// In slowly, the text a moment after the controls have faded; out at once, before the controls are back.
    private var dimIn: Animation {
        reduceMotion ? .easeInOut(duration: 0.35) : .easeInOut(duration: 0.9)
    }

    private var textIn: Animation {
        reduceMotion ? .easeInOut(duration: 0.35) : .smooth(duration: 0.7).delay(0.3)
    }

    private var out: Animation {
        .easeOut(duration: 0.16)
    }
}
