import Kingfisher
import SwiftUI

struct ImageView: View {
    private let url: URL

    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        KFImage
            .url(url)
            .placeholder {
                KPLoadingView()
            }
            .resizable()
            .loadTransition(.blurReplace(.downUp), animation: .bouncy)
            .cancelOnDisappear(true)
            .retry(NetworkRetryStrategy())
            .scaledToFit()
            .zoomable(
                maxZoomScale: 5,
                doubleTapZoomScale: 3
            )
            .navigationTitle("key.imageViewer")
            .toolbar(.hidden)
            .frame(minWidth: 300 * (16 / 9), maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
            .ignoresSafeArea()
            .focusable()
            .focusEffectDisabled()
            .contentShape(.rect)
            .background(Color.clear)
            .onAppear {
                guard let window = Windows.imageViewer.window,
                      !window.styleMask.contains(.fullScreen)
                else {
                    return
                }

                window.toggleFullScreen(nil)
            }
            .onExitCommand {
                dismiss()
            }
            .background {
                KFImage
                    .url(url)
                    .placeholder {
                        Color.gray
                    }
                    .resizable()
                    .loadTransition(.blurReplace(.downUp), animation: .bouncy)
                    .cancelOnDisappear(true)
                    .retry(NetworkRetryStrategy())
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle().fill(.ultraThickMaterial)
            }
            .gesture(
                WindowDragGesture()
                    .exclusively(before:
                        TapGesture(count: 2)
                            .onEnded {
                                guard let window = Windows.imageViewer.window else { return }

                                window.toggleFullScreen(nil)
                            }
                            .exclusively(before:
                                TapGesture(count: 1)
                                    .onEnded {
                                        dismiss()
                                    }))
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(KPIconButtonStyle(diameter: 38))
                    .help("Поделиться")

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(KPIconButtonStyle(diameter: 38))
                    .help("Закрыть (Esc)")
                }
                .padding(20)
            }
    }
}
