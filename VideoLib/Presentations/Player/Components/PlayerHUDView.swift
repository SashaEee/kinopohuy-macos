import ComposableArchitecture
import SwiftUI

/// For a moment after a key: how far it jumped («+30 с» when pressed three times) or the volume, in a glass capsule.
/// Also a short notice: «Продолжаем с 12:34», the voice-over it switched to, or why it couldn't.
struct PlayerHUDView: View {
    @Environment(StoreOf<PlayerFeature>.self) private var store
    @Environment(\.kpMetrics) private var metrics

    /// Sized for the transient feedback it is, a step under the centre controls.
    private var height: CGFloat { metrics.compact ? 40 : 44 }
    private var textSize: CGFloat { metrics.compact ? 15 : 16 }

    var body: some View {
        ZStack {
            if let hud = store.hud {
                content(hud)
                    .foregroundStyle(KP.fg)
                    .padding(.horizontal, 20)
                    .frame(height: height)
                    .kpGlass(in: Capsule())
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: store.hud == nil)
        .animation(.snappy(duration: 0.2), value: store.hud)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(_ hud: PlayerFeature.HUD) -> some View {
        switch hud {
        case let .skip(seconds):
            HStack(spacing: 9) {
                Image(systemName: seconds < 0 ? "gobackward" : "goforward")
                    .font(.system(size: 15, weight: .semibold))
                Text(verbatim: "\(seconds < 0 ? "−" : "+")\(Self.format(abs(seconds)))")
                    .font(KP.font(textSize, .bold).monospacedDigit())
                    .contentTransition(.numericText(value: seconds))
            }
        case let .volume(volume):
            HStack(spacing: 11) {
                Image(systemName: volume <= 0 ? "speaker.slash.fill" : volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 23, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))
                Capsule()
                    .fill(KP.fg.opacity(0.2))
                    .frame(width: 140, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(KP.fg).frame(width: 140 * CGFloat(volume))
                    }
            }
        case let .notice(icon, text):
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KP.fg80)
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: text)
                    .font(KP.font(textSize - 1, .semibold).monospacedDigit())
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
        }
    }

    /// 10 → «10 с», 90 → «1:30».
    private static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s) с" : String(format: "%d:%02d", s / 60, s % 60)
    }
}
