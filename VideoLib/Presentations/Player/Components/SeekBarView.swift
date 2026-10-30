import AVKit
import ComposableArchitecture
import SwiftUI

struct SeekBarView: View {
    @Environment(StoreOf<PlayerFeature>.self) private var store

    var body: some View {
        SliderWithTextView(value: Binding {
            store.currentTime
        } set: { time in
            store.send(.seek(time))
        }, inRange: 0 ... store.duration, buffers: store.loadedTimeRanges, activeFillColor: KP.sun, fillColor: KP.sun.opacity(0.92), emptyColor: .white.opacity(0.28), height: 5, thumbnails: store.thumbnails) { _ in }
            .frame(height: 25)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }
}
