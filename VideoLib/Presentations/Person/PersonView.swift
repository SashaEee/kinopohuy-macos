import ComposableArchitecture
import Defaults
import SwiftUI

struct PersonView: View {
    let store: StoreOf<PersonFeature>

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        ScrollView(.vertical) {
            if let details = store.details.data {
                PersonDetailsView(details: details, shareId: store.id)
                    .kpBelowTopBar(extra: metrics.compact ? 20 : 28)
                    .padding(.bottom, metrics.screenBottom)
            }
        }
        .scrollIndicators(.automatic)
        .overlay {
            if let error = store.details.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
            } else if store.details.isLoading {
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
