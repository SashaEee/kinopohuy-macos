import ComposableArchitecture
import Defaults
import SwiftUI

/// «Подборки»: the site's collections as wide covers, more as the end comes into view.
struct CollectionsView: View {
    @Bindable var store: StoreOf<CollectionsFeature>

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap - 6) {
                KPScreenHeader(title: "Подборки")

                if let collections = store.collections.data, !collections.isEmpty {
                    KPGrid(items: collections, itemWidth: CollectionCardView.width(for: metrics)) { collection in
                        CollectionCardView(collection: collection)
                            .equatable()
                            .onAppear {
                                if store.paginationState == .idle, collections.suffix(8).contains(where: { $0.id == collection.id }) {
                                    store.send(.loadMore)
                                }
                            }
                    }
                }

                if store.paginationState == .loading {
                    KPLoadingView().frame(height: 80)
                }
            }
            .kpBelowTopBar()
            .padding(.bottom, metrics.screenBottom)
        }
        .scrollIndicators(.automatic)
        .overlay {
            if let error = store.collections.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
            } else if let collections = store.collections.data, collections.isEmpty {
                KPEmptyView(message: "Подборок пока нет")
            } else if store.collections.isLoading {
                KPLoadingView()
            }
        }
        .background {
            Button("") { store.send(.reload) }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .kpScreenBackground()
    }
}
