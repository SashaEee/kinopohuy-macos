import SwiftUI

/// The release schedule, season by season (the first open).
struct ScheduleSheetView: View {
    private let schedule: [SeriesScheduleGroup]

    init(schedule: [SeriesScheduleGroup]) {
        self.schedule = schedule
    }

    var body: some View {
        KPSheet(title: "Выход серий", subtitle: "Даты выхода по сезонам", symbol: "calendar", width: 620, height: 620) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(schedule.enumerated()), id: \.element.id) { index, group in
                        ScheduleSection(group: group, isExpanded: index == 0)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
        }
    }
}

private struct ScheduleSection: View {
    let group: SeriesScheduleGroup
    @State var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: group.name)
                        .font(KP.font(16, .bold))
                        .foregroundStyle(KP.fg)
                    Text(verbatim: "\(group.items.count)")
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
                    ForEach(group.items) { item in
                        HStack(spacing: 14) {
                            Text(verbatim: item.title)
                                .font(KP.font(12.5, .semibold))
                                .foregroundStyle(KP.fg55)
                                .frame(width: 120, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.russianEpisodeName)
                                    .font(KP.font(14.5, .medium))
                                    .foregroundStyle(KP.fg)
                                    .lineLimit(1)
                                if let original = item.originalEpisodeName {
                                    Text(verbatim: original)
                                        .font(KP.font(12.5))
                                        .foregroundStyle(KP.fg38)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(verbatim: item.releaseDate)
                                .font(KP.font(13, .semibold))
                                .foregroundStyle(KP.fg70)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KP.surface.opacity(0.7)))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
