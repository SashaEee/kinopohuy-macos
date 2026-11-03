import Dependencies
import RecommenderCore
import SwiftUI

extension View {
    /// The verdict as a row under this one (the page's «Ваша оценка»), `spacing` apart. It loads with this row: a view
    /// with nothing in it yet never appears, so it could never start loading itself.
    func kpFitVerdictRow(titleId: String, label: String, spacing: CGFloat) -> some View {
        modifier(FitVerdictRow(titleId: titleId, label: label, spacing: spacing))
    }
}

private struct FitVerdictRow: ViewModifier {
    let titleId: String
    let label: String
    let spacing: CGFloat

    @State private var verdict: FitVerdict?
    @Dependency(\.recommender) private var recommender

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
            if let verdict, !(verdict.pros.isEmpty && verdict.cons.isEmpty) {
                FitVerdictView(verdict: verdict, label: label)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: verdict)
        .task(id: titleId) {
            guard await !isRatedOrSeen() else {
                verdict = nil
                return
            }
            let fit = await recommender.fit(titleId)
            // Rated or marked seen while it was being worked out (the first one after launch takes a few seconds).
            guard await !isRatedOrSeen() else { return }
            verdict = fit
        }
        .onReceive(NotificationCenter.default.publisher(for: .recRatingChanged)) { note in
            guard note.object as? String == titleId else { return }
            verdict = nil
        }
    }

    /// Seen it (rated or «Уже смотрел»): «Вам подойдёт?» has nothing to say any more.
    private func isRatedOrSeen() async -> Bool {
        if await recommender.rating(titleId) != nil { return true }
        return await recommender.activeFeedback(titleId).contains(.seen)
    }
}

/// «Вам подойдёт?» on a title's page: «Скорее да / 50 на 50 / Скорее нет» with two pluses and a minus in the user's
/// terms («+ детектив — ваш жанр № 1 · − 2 ч 38 мин»). No percentages. Nothing shows until the recommender knows enough
/// about the user and the title, and nothing once it's rated or marked seen.
struct FitVerdictView: View {
    let verdict: FitVerdict
    /// A title page's fact row: its label in the page's left column («Вам подойдёт?»).
    var label: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let label {
                Text(verbatim: label)
                    .font(KP.font(13, .medium))
                    .foregroundStyle(KP.fg38)
                    .frame(width: 108, alignment: .leading)
            }
            content(verdict)
        }
        .help("Как это сходится с тем, что вы смотрели и оценивали")
    }

    private func content(_ verdict: FitVerdict) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol(verdict.level))
                    .font(.system(size: 12, weight: .bold))
                Text(verbatim: levelText(verdict.level))
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
                // Wraps onto its second line rather than being cut on the first.
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func levelText(_ level: FitVerdict.Level) -> String {
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

extension Notification.Name {
    /// A title was rated or marked seen on its page (the object is its id): what asks «подойдёт?» steps aside.
    static let recRatingChanged = Notification.Name("recRatingChanged")
}
