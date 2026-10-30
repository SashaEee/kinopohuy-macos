import AVKit
import ComposableArchitecture
import Defaults
import SwiftUI

struct DetailsView: View {
    @Bindable var store: StoreOf<DetailsFeature>

    @State private var isSchedulePresented = false

    var body: some View {
        ScrollView(.vertical) {
            // Laid out from the first frame: the card's name and picture, stand-ins for the rest (see
            // DetailsComponentView), so opening a title never shows a blank or a half-built page.
            if store.details.error == nil {
                DetailsComponentView(details: store.details.data, previewTitle: store.title ?? "", previewPoster: store.poster, isSchedulePresented: $isSchedulePresented)
                    .environment(store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.automatic)
        .ignoresSafeArea(edges: .top)
        .overlay {
            if let error = store.details.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
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
        .sheet(item: $store.scope(state: \.destination?.bookmarks, action: \.destination.bookmarks)) { store in
            BookmarksSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.createBookmark, action: \.destination.createBookmark)) { store in
            CreateBookmarkSheetView(store: store)
        }
        .sheet(isPresented: $isSchedulePresented) {
            if let details = store.details.data, let schedule = details.schedule, !schedule.isEmpty {
                ScheduleSheetView(schedule: schedule)
            }
        }
        .sheet(isPresented: Binding(get: { store.trailerStream != nil }, set: { if !$0 { store.trailerStream = nil } })) {
            if let url = store.trailerStream {
                TrailerPlayerView(url: url, title: store.details.data?.nameRussian ?? store.title ?? "")
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .dialogSeverity(.critical)
        .kpScreenBackground()
    }
}

/// The trailer in the system player (Rutube's HLS: the picture size adapts to the network by itself).
private struct TrailerPlayerView: View {
    let url: URL
    let title: String

    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: title)
                    .font(KP.font(16, .bold))
                    .foregroundStyle(KP.fg)
                Text(verbatim: "Трейлер")
                    .font(KP.font(14, .medium))
                    .foregroundStyle(KP.fg55)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(KPIconButtonStyle(diameter: 30))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
        }
        .frame(width: 1040)
        .background(KP.bg)
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
        .preferredColorScheme(.dark)
    }
}
