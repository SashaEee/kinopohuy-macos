import Dependencies
import RecommenderCore
import SwiftUI

/// «Вам подойдёт?» on a title's page: «Скорее да / 50 на 50 / Скорее нет» with two pluses and a minus in the user's
/// terms («+ детектив — ваш жанр № 1 · − 2 ч 38 мин»). No percentages. Nothing shows until the recommender knows enough
/// about the user and the title.
struct FitVerdictView: View {
    let titleId: String

    @State private var verdict: FitVerdict?
    @Dependency(\.recommender) private var recommender

    var body: some View {
        Group {
            if let verdict, !(verdict.pros.isEmpty && verdict.cons.isEmpty) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: symbol(verdict.level))
                            .font(.system(size: 12, weight: .bold))
                        Text(verbatim: label(verdict.level))
                            .font(KP.font(13, .bold))
                    }
                    .foregroundStyle(color(verdict.level))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color(verdict.level).opacity(0.14)))

                    Text(verbatim: (verdict.pros.prefix(2).map { "+ \($0)" } + verdict.cons.prefix(1).map { "− \($0)" }).joined(separator: "  ·  "))
                        .font(KP.font(13, .medium))
                        .foregroundStyle(KP.fg70)
                        .lineLimit(2)
                }
                .help("Как это сходится с тем, что вы смотрели и оценивали")
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: verdict)
        .task(id: titleId) {
            verdict = await recommender.fit(titleId)
        }
    }

    private func label(_ level: FitVerdict.Level) -> String {
        switch level {
        case .likely: "Скорее зайдёт"
        case .maybe: "50 на 50"
        case .unlikely: "Скорее нет"
        }
    }

    private func symbol(_ level: FitVerdict.Level) -> String {
        switch level {
        case .likely: "hand.thumbsup.fill"
        case .maybe: "circle.lefthalf.filled"
        case .unlikely: "hand.thumbsdown.fill"
        }
    }

    private func color(_ level: FitVerdict.Level) -> Color {
        switch level {
        case .likely: KP.good
        case .maybe: KP.sun
        case .unlikely: KP.fg55
        }
    }
}
