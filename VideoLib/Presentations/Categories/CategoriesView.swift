import ComposableArchitecture
import SwiftUI

/// «Каталог»: films, series, cartoons, anime — each with its genres and the site's «лучшие» by genre and year.
struct CategoriesView: View {
    @Bindable var store: StoreOf<CategoriesFeature>

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.sectionGap) {
                KPScreenHeader(title: "Каталог")

                if let types = store.types.data, !types.isEmpty {
                    ForEach(types) { type in
                        if let typeView = CategoriesTypeView(type: type) {
                            typeView.equatable()
                        }
                    }
                }
            }
            .kpBelowTopBar()
            .padding(.bottom, metrics.screenBottom)
        }
        .scrollIndicators(.automatic)
        .overlay {
            if let error = store.types.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
            } else if let types = store.types.data, types.isEmpty {
                KPEmptyView(message: "Каталог пуст")
            } else if store.types.isLoading {
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
