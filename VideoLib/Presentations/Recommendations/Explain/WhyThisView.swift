import Dependencies
import RecommenderCore
import SwiftUI

/// «Почему это?»: what led to a recommendation, in the user's terms («Похоже на «Мост» и «Убийство» — вы их
/// досмотрели»), the path through the site's links, and the levers: less of the main feature for 60 days, stop using
/// the title it came from, or «Не моё». `changed` runs after a lever was pulled (the caller closes the popover).
struct WhyThisView: View {
    let titleId: String
    let name: String
    var changed: () -> Void = {}

    @State private var explanation: Explanation?
    @State private var loaded = false
    @State private var anchorName: String?
    @Dependency(\.recommender) private var recommender

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(KP.sun)
                Text(verbatim: "Почему «\(name)»")
                    .font(KP.font(15, .bold))
                    .foregroundStyle(KP.fg)
                    .lineLimit(1)
            }

            if let explanation {
                Text(verbatim: explanation.reason.long)
                    .font(KP.font(13.5, .semibold))
                    .foregroundStyle(KP.fg)
                    .fixedSize(horizontal: false, vertical: true)

                if !explanation.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(explanation.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Circle().fill(KP.fg38).frame(width: 4, height: 4).offset(y: -2)
                                Text(verbatim: line)
                                    .font(KP.font(12.5, .medium))
                                    .foregroundStyle(KP.fg70)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if explanation.path.count > 1 {
                    Text(verbatim: explanation.path.map { "«\($0)»" }.joined(separator: " → "))
                        .font(KP.font(12, .medium))
                        .foregroundStyle(KP.fg55)
                        .lineLimit(2)
                }

                Divider().overlay(KP.line)

                HStack(spacing: 8) {
                    if let feature = explanation.mainFeature {
                        Button("Меньше такого") {
                            let until = Date.now.addingTimeInterval(60 * 24 * 3600).timeIntervalSince1970
                            act { await recommender.override(TasteOverride(feature: feature, mode: .mute, until: until)) }
                        }
                        .help("Реже советовать «\(feature.value)» ближайшие два месяца")
                    }
                    if let anchor = explanation.mainAnchorId {
                        Button(anchorName.map { "Не учитывать «\(RecText.short($0, 24))»" } ?? "Не учитывать источник") {
                            act { await recommender.feedback(anchor, .notSeed) }
                        }
                        .help("Этот тайтл перестанет влиять на советы")
                    }
                    Button("Не моё") {
                        act { await recommender.rate(titleId, -2, .app) }
                    }
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            } else if loaded {
                Text(verbatim: "Это из общих подборок: о вашем вкусе здесь пока мало данных.")
                    .font(KP.font(13, .medium))
                    .foregroundStyle(KP.fg55)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    KPSkeleton(width: 260, height: 13)
                    KPSkeleton(width: 220, height: 11)
                    KPSkeleton(width: 240, height: 11)
                }
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(KP.surface)
        .environment(\.colorScheme, .dark)
        .task(id: titleId) {
            explanation = await recommender.explain(titleId)
            if let anchor = explanation?.mainAnchorId {
                anchorName = await recommender.title(anchor)?.name
            }
            loaded = true
        }
    }

    private func act(_ work: @escaping @Sendable () async -> Void) {
        Task {
            await work()
            changed()
        }
    }
}

extension RecText {
    /// A long name cut to fit a button or a heading.
    static func short(_ name: String, _ limit: Int) -> String {
        name.count > limit ? name.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}
