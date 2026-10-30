import ComposableArchitecture
import SwiftUI

/// Near the end of an episode: the next one (with its name from the schedule), with a ring running out until it
/// starts by itself; a press starts it now, «Смотреть титры» puts the card away for the rest of this one. It steps
/// aside while the pause screen is up.
struct NextTimerView: View {
    @Environment(StoreOf<PlayerFeature>.self) private var store
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        Group {
            if let nextTimer = store.nextTimer, store.isSeries, let (season, episode) = store.nextEpisode {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        store.send(.creditsTapped, animation: .spring(response: 0.45, dampingFraction: 0.85))
                    } label: {
                        Text(verbatim: "Смотреть титры")
                    }
                    .buttonStyle(KPGlassButtonStyle(size: metrics.compact ? 12.5 : 13))

                    card(nextTimer, label(season, episode))
                }
                .padding(.top, top)
                .padding(.trailing, KP.gutter)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.nextTimer != nil)
        .opacity(store.isPauseScreenShown ? 0 : 1)
        .allowsHitTesting(!store.isPauseScreenShown)
        .animation(.easeOut(duration: 0.2), value: store.isPauseScreenShown)
    }

    /// Under the top capsule: its top padding, its height and a gap.
    private var top: CGFloat {
        20 + metrics.playerTransport + 20
    }

    private func card(_ nextTimer: CGFloat, _ title: String) -> some View {
        let ring: CGFloat = metrics.compact ? 34 : 36
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return Button {
            store.send(.nextTrackTapped, animation: .easeInOut(duration: 0.15))
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Следующая серия")
                        .font(KP.font(11.5, .bold))
                        .tracking(0.5)
                        .foregroundStyle(KP.sun)
                    Text(verbatim: title)
                        .font(KP.font(metrics.compact ? 14 : 15, .bold))
                        .foregroundStyle(KP.fg)
                    if let name = store.nextEpisodeTitle {
                        // Cut short so a long name doesn't stretch the card across the picture.
                        Text(verbatim: "«\(name.count > 34 ? String(name.prefix(33)) + "…" : name)»")
                            .font(KP.font(metrics.compact ? 12.5 : 13, .medium))
                            .foregroundStyle(KP.fg70)
                    }
                }
                .lineLimit(1)

                ZStack {
                    Circle().stroke(KP.fg.opacity(0.18), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: nextTimer)
                        .stroke(KP.sunGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KP.fg)
                        .offset(x: 1.5)
                }
                .frame(width: ring, height: ring)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .contentShape(shape)
            .kpGlass(in: shape, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Смотреть следующую серию сейчас")
    }

    private func label(_ season: MovieSeason, _ episode: MovieEpisode) -> String {
        let s = season.name.first?.isNumber == true ? "\(season.name) сезон" : season.name
        let e = episode.name.first?.isNumber == true ? "\(episode.name) серия" : episode.name
        return "\(s), \(e)"
    }
}
