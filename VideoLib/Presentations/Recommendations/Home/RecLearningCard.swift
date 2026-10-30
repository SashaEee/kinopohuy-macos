import SwiftUI

/// While the recommender is still getting to know the user (fewer titles than it needs to stand on): a slim card on
/// Home instead of the personal rows, «Изучаем ваш вкус · 120 из 315», with the quick way in, «Уточнить вкус» (a
/// dozen titles to rate in under a minute).
struct RecLearningCard: View {
    let status: RecStatus?
    let tune: () -> Void
    var dismiss: (() -> Void)?

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KP.sun)
                .frame(width: 40, height: 40)
                .background(Circle().fill(KP.sun.opacity(0.14)))
                .symbolEffect(.pulse, options: .repeating, isActive: status?.isEnriching == true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Изучаем ваш вкус")
                    .font(KP.font(metrics.body + 1, .bold))
                    .foregroundStyle(KP.fg)
                Text(verbatim: detail)
                    .font(KP.font(metrics.body - 1, .medium))
                    .foregroundStyle(KP.fg55)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(action: tune) {
                Label("Уточнить вкус", systemImage: "hand.thumbsup")
            }
            .buttonStyle(KPPrimaryButtonStyle(size: 13))

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(KPIconButtonStyle(diameter: 26, filled: false))
                .help("Скрыть до завтра")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KP.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(KP.line))
        .padding(.horizontal, KP.gutter)
    }

    private var detail: String {
        guard let status, status.known > 0 else {
            return "Смотрите и отмечайте «Нравится» — первые советы появятся здесь"
        }
        let pages = "знаем \(RecText.count(status.known, "тайтл", "тайтла", "тайтлов")), подробно — \(status.pages)"
        return status.isEnriching ? "\(pages) · читаем каталог сайта в фоне" : "\(pages) · оцените несколько просмотренных, и советы станут точнее"
    }
}
