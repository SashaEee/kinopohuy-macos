import SwiftUI

/// One kind of title in «Каталог»: its genres as capsules, and «Лучшие» for a genre and a year.
struct CategoriesTypeView: View {
    private let type: MovieType

    init?(type: MovieType) {
        self.type = type

        guard let genre = type.best.genres.first, let year = type.best.years.first else { return nil }

        bestGenre = genre
        bestYear = year
    }

    @State private var bestGenre: MovieGenre
    @State private var bestYear: MovieYear
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.stackGap + 4) {
            HStack(alignment: .firstTextBaseline) {
                KPSectionTitle(title: type.name, count: type.genres.count)
                Spacer()
                KPRouteLink(route: .genre(.init(name: type.name, genreId: type.typeId))) {
                    HStack(spacing: 4) {
                        Text(verbatim: "Все")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(KP.font(13, .semibold))
                    .foregroundStyle(KP.fg55)
                }
                .buttonStyle(.plain)
            }

            FlowLayout(spacing: 8) {
                ForEach(type.genres) { genre in
                    GenreChip(genre: genre)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(KP.sun)
                Text(verbatim: type.best.name)
                    .font(KP.font(14, .semibold))
                    .foregroundStyle(KP.fg80)

                Picker(selection: $bestGenre) {
                    ForEach(type.best.genres) { genre in
                        Text(genre.name).tag(genre)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                Picker(selection: $bestYear) {
                    ForEach(type.best.years) { year in
                        Text(year.name).tag(year)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                KPRouteLink(route: .list(.init(name: type.name, listId: bestGenre.genreId + (bestYear.year != 0 ? "\(bestYear.year)/" : "")))) {
                    Text(verbatim: "Показать")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KP.surface))
            .fixedSize()
        }
        .padding(.horizontal, KP.gutter)
    }
}

/// A genre as a pill (KPPill's size), white under the pointer.
private struct GenreChip: View {
    let genre: MovieGenre
    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        KPRouteLink(route: .genre(genre)) {
            Text(verbatim: genre.name)
                .font(KP.font(metrics.pillFont, .medium))
                .foregroundStyle(hover ? KP.ink : KP.fg80)
                .padding(.horizontal, metrics.pillPaddingH)
                .padding(.vertical, metrics.pillPaddingV)
                .background(Capsule().fill(hover ? KP.fg : KP.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}

extension CategoriesTypeView: Equatable {
    nonisolated static func == (lhs: CategoriesTypeView, rhs: CategoriesTypeView) -> Bool {
        lhs.type.id == rhs.type.id
    }
}
