import SwiftUI

/// A collection: its wide cover with the number of titles, the name under it.
struct CollectionCardView: View {
    private let collection: MoviesCollection
    private let fixedWidth: CGFloat?

    @Environment(\.kpMetrics) private var metrics

    /// width: nil is the size tier's (`width(for:)`).
    init(collection: MoviesCollection, width: CGFloat? = nil) {
        self.collection = collection
        fixedWidth = width
    }

    /// The cover's width in a tier: about 1.8 poster cards.
    static func width(for metrics: KPMetrics) -> CGFloat {
        metrics.compact ? 264 : 300
    }

    /// Decoded at one size whatever the tier, so a tier change doesn't fetch the covers again.
    private static let coverPixels = CGSize(width: 600, height: 360)

    var body: some View {
        KPRouteLink(route: .collection(collection)) {
            KPPosterCard(
                title: collection.name,
                kind: collection.count.map { "\($0)" },
                width: fixedWidth ?? Self.width(for: metrics),
                aspect: 0.6
            ) {
                KPRemoteImage(url: collection.poster, downsample: Self.coverPixels)
            }
        }
        .buttonStyle(.plain)
    }
}

extension CollectionCardView: Equatable {
    nonisolated static func == (lhs: CollectionCardView, rhs: CollectionCardView) -> Bool {
        lhs.collection.id == rhs.collection.id
    }
}
