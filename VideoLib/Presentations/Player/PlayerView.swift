import AVKit
import ComposableArchitecture
import SwiftUI

struct PlayerView: View {
    @State private var engine: PlayerEngine
    @State private var store: StoreOf<PlayerFeature>

    init(data: PlayerData) {
        let engine = PlayerEngine()

        _engine = State(initialValue: engine)
        _store = State(initialValue: Store(initialState: PlayerFeature.State(data: data)) { PlayerFeature(engine: engine) })
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isFocused: Bool

    /// Where the pointer was last seen: under the pause screen a twitch of under 3 pt doesn't wake the player.
    @State private var lastHover: CGPoint?
    /// A menu opened while this window was in front (its end is then passed on too).
    @State private var isTrackingMenu = false

    var body: some View {
        Group {
            if let error = store.error {
                KPErrorView(message: error.base.kpMessage) {
                    store.send(.retryTapped)
                }
            } else if let player = engine.player {
                CustomAVPlayerView(playerLayer: engine.playerLayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                guard store.isReady,
                                      let window = Windows.player.window,
                                      !store.isPictureInPictureActive || (store.isPictureInPictureActive && window.styleMask.contains(.fullScreen))
                                else {
                                    return
                                }

                                store.send(.userActivity)
                                window.toggleFullScreen(nil)
                            }
                            .exclusively(before:
                                TapGesture(count: 1)
                                    .onEnded {
                                        store.send(.videoTapped)
                                    })
                    )
                    .overlay {
                        PlayerPauseScreenView()
                    }
                    .overlay {
                        PlayerOverlayView(player: player)
                    }
                    .overlay(alignment: .topTrailing) {
                        NextTimerView()
                    }
                    .overlay(alignment: .top) {
                        PlayerHUDView()
                            .padding(.top, 22)
                    }
                    .background(alignment: .center) {
                        GlowImageView()
                    }
            } else if store.isLoading {
                KPLoadingView()
            }
        }
        .environment(store)
        .environment(engine)
        .kpMetricsFromWindow()
        .navigationTitle(Text(verbatim: "Player - \(store.name)"))
        .toolbar(.hidden)
        .frame(minWidth: 900, minHeight: 900 / 16 * 9)
        .ignoresSafeArea()
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(.primary)
        .contentShape(.rect)
        .task {
            store.send(.task)

            if let window = Windows.player.window,
               store.playerFullscreen,
               !window.styleMask.contains(.fullScreen)
            {
                window.toggleFullScreen(nil)
            }

            if store.hideMainWindow,
               let window = Windows.videolib.window
            {
                let animation = window.animationBehavior
                window.animationBehavior = .none
                window.orderOut(nil)
                window.animationBehavior = animation
            }
        }
        .onDisappear {
            store.send(.disappeared)

            guard store.hideMainWindow,
                  let window = Windows.videolib.window
            else {
                return
            }

            let animation = window.animationBehavior
            window.animationBehavior = .none
            window.orderFront(nil)
            window.animationBehavior = animation
        }
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                if store.isPauseScreenShown, let lastHover, hypot(location.x - lastHover.x, location.y - lastHover.y) < 3 {
                    return
                }

                lastHover = location
                store.send(.hoverChanged(isActive: true), animation: .easeInOut)
            case .ended:
                store.send(.hoverChanged(isActive: false), animation: .easeInOut)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            guard Windows.player.window?.isKeyWindow == true else { return }

            isTrackingMenu = true
            store.send(.menuTracking(true), animation: .easeInOut)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            guard isTrackingMenu else { return }

            isTrackingMenu = false
            store.send(.menuTracking(false), animation: .easeInOut)
        }
        .onChange(of: scenePhase) {
            store.send(.scenePhaseChanged(isActive: scenePhase == .active))
        }
        .onChange(of: store.isFocused) {
            isFocused = store.isFocused
        }
        .onChange(of: isFocused) {
            store.isFocused = isFocused
        }
        .onChange(of: store.isDismissed) {
            if store.isDismissed {
                dismiss()
            }
        }
        .onExitCommand {
            // Under the pause screen Esc only wakes the player (like Back on the TV); the next one leaves full screen.
            if store.isPauseScreenShown {
                store.send(.userActivity, animation: .easeInOut)

                return
            }

            store.send(.userActivity)

            guard store.isReady,
                  let window = Windows.player.window,
                  window.styleMask.contains(.fullScreen)
            else {
                return
            }

            window.toggleFullScreen(nil)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                store.send(.moveCommand(.up))
            case .down:
                store.send(.moveCommand(.down))
            case .left:
                store.send(.moveCommand(.left))
            case .right:
                store.send(.moveCommand(.right))
            default:
                store.send(.userActivity)
            }
        }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }
}
