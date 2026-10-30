import ComposableArchitecture
import SwiftUI

/// «Новые серии»: what came out, day by day; the series you follow first in each day, marked.
struct SeriesUpdatesSheetView: View {
    let store: StoreOf<SeriesUpdatesFeature>

    var body: some View {
        KPSheet(title: "Новые серии", subtitle: "Что вышло за последние дни", symbol: "bell.badge", width: 620, height: 640) {
            Group {
                if let error = store.seriesUpdates.error {
                    KPErrorView(message: error.kpMessage) { store.send(.reload) }
                } else if let groups = store.seriesUpdates.data {
                    if groups.isEmpty {
                        KPEmptyView(message: "Пока ничего нового", symbol: "bell.slash")
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                    DaySection(group: group, isExpanded: index < 2) { movie in
                                        store.send(.movieTapped(movie))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.automatic)
                    }
                } else {
                    KPLoadingView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            store.send(.reload)
        }
    }
}

private struct DaySection: View {
    let group: SeriesUpdateGroup
    @State var isExpanded: Bool
    let onSelect: (MovieSimple) -> Void

    private var items: [SeriesUpdateItem] {
        group.releasedEpisodes.filter(\.tracked) + group.releasedEpisodes.filter { !$0.tracked }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: group.date)
                        .font(KP.font(16, .bold))
                        .foregroundStyle(KP.fg)
                    Text(verbatim: "\(group.releasedEpisodes.count)")
                        .font(KP.font(13, .semibold))
                        .foregroundStyle(KP.fg38)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KP.fg55)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        UpdateRow(item: item) {
                            onSelect(.init(movieId: item.seriesId, name: item.seriesName))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct UpdateRow: View {
    let item: SeriesUpdateItem
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(item.tracked ? KP.sun : .clear)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.seriesName)
                        .font(KP.font(14.5, item.tracked ? .bold : .medium))
                        .foregroundStyle(item.tracked ? KP.fg : KP.fg80)
                        .lineLimit(1)
                    Text(verbatim: item.season.trimmingCharacters(in: CharacterSet(charactersIn: "() ")))
                        .font(KP.font(12.5))
                        .foregroundStyle(KP.fg38)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: item.releasedEpisode)
                        .font(KP.font(13, .semibold))
                        .foregroundStyle(KP.fg70)
                        .multilineTextAlignment(.trailing)
                    if !item.chosenVoiceActing.isEmpty {
                        Text(verbatim: item.chosenVoiceActing.trimmingCharacters(in: CharacterSet(charactersIn: "() ")))
                            .font(KP.font(11.5, .semibold))
                            .foregroundStyle(item.isChosenVoiceActingPremium ? KP.fg : KP.fg55)
                            .padding(.horizontal, item.isChosenVoiceActingPremium ? 7 : 0)
                            .padding(.vertical, item.isChosenVoiceActingPremium ? 2 : 0)
                            .background {
                                if item.isChosenVoiceActingPremium {
                                    Capsule().fill(Const.premiumGradient)
                                }
                            }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KP.fg38)
                    .opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? KP.surfaceHigh : KP.surface.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}
