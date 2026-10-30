import Defaults
import SwiftUI

/// A person: their photo, name and facts, then their titles by role, each a row.
struct PersonDetailsView: View {
    private let details: PersonDetailed
    private let shareId: String

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.kpMetrics) private var metrics
    @Default(.mirror) private var mirror

    init(details: PersonDetailed, shareId: String) {
        self.details = details
        self.shareId = shareId
    }

    private var facts: [(String, String)] {
        [
            ("Карьера", details.career),
            ("Дата рождения", details.birthDate),
            ("Место рождения", details.birthPlace),
            ("Дата смерти", details.deathDate),
            ("Место смерти", details.deathPlace),
            ("Рост", details.height),
        ].compactMap { label, value in value.flatMap { $0.isEmpty ? nil : (label, $0) } }
    }

    private var rows: [(String, [MovieSimple])] {
        [
            ("Актёр", details.actorMovies),
            ("Актриса", details.actressMovies),
            ("Режиссёр", details.directorMovies),
            ("Сценарист", details.screenwriterMovies),
            ("Продюсер", details.producerMovies),
            ("Оператор", details.operatorMovies),
            ("Монтажёр", details.editorMovies),
            ("Художник", details.artistMovies),
            ("Композитор", details.composerMovies),
        ].compactMap { title, movies in movies.flatMap { $0.isEmpty ? nil : (title, $0) } }
    }

    var body: some View {
        // No picture-backed banner here: a smaller photo and name, so the first row of titles is in view.
        let photo = metrics.compact ? CGSize(width: 172, height: 258) : CGSize(width: 200, height: 300)
        VStack(alignment: .leading, spacing: metrics.sectionGap) {
            HStack(alignment: .bottom, spacing: 28) {
                Button {
                    if let url = URL(string: details.hphoto) ?? URL(string: details.photo) {
                        dismissWindow(id: Windows.imageViewer.id)
                        openWindow(id: Windows.imageViewer.id, value: url)
                    }
                } label: {
                    KPRemoteImage(url: details.hphoto, fallback: details.photo)
                        .frame(width: photo.width, height: photo.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: metrics.compact ? 14 : 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: details.nameRu)
                            .font(KP.font(metrics.displayLong, .heavy))
                            .tracking(metrics.compact ? -0.5 : -0.6)
                            .foregroundStyle(KP.fg)
                            .textSelection(.enabled)
                        if let original = details.nameOrig, !original.isEmpty {
                            Text(verbatim: original)
                                .font(KP.font(metrics.compact ? 15 : 16, .medium))
                                .foregroundStyle(KP.fg55)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: metrics.compact ? 7 : 9) {
                        ForEach(facts, id: \.0) { label, value in
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(verbatim: label)
                                    .font(KP.font(13, .medium))
                                    .foregroundStyle(KP.fg38)
                                    .frame(width: 120, alignment: .leading)
                                Text(verbatim: value)
                                    .font(KP.font(14, .medium))
                                    .foregroundStyle(KP.fg80)
                                    .lineLimit(2)
                            }
                        }
                    }

                    ShareLink(item: mirror.appending(path: shareId, directoryHint: .notDirectory)) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
            .padding(.horizontal, KP.gutter)

            ForEach(rows, id: \.0) { title, movies in
                PersonMoviesRowView(title, movies)
            }
        }
    }
}
