import AVKit
import ComposableArchitecture
import Defaults
import SwiftUI

/// The player's controls over the picture, in Liquid Glass: the clock and the sound at the top; −10 s, play/pause and
/// +10 s in the middle; the title, the episode buttons, subtitles, settings and full screen over the scrubber at the
/// bottom; «Серии» opens a panel with the seasons and episodes. All of it fades away a few seconds into playback.
/// Sizes follow the player window's tier (`kpMetrics`): a MacBook's full screen gets the compact set.
struct PlayerOverlayView: View {
    let player: AVPlayer

    @Environment(StoreOf<PlayerFeature>.self) private var store
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.kpMetrics) private var metrics

    @Default(.videoGravity) private var videoGravity
    @Default(.ambientLight) private var ambientLight
    @Default(.rate) private var rate
    @Default(.isUserPremium) private var isUserPremium

    @State private var episodesShown = false
    @State private var panelSeason: MovieSeason?
    /// The bottom bar's height, so the «Серии» panel sits just above it whatever the tier.
    @State private var bottomBarHeight: CGFloat = 150

    var body: some View {
        ZStack {
            scrims

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }

            centerControls
                .opacity(episodesShown ? 0 : 1)
                .scaleEffect(episodesShown ? 0.9 : 1)

            if episodesShown, let seasons = store.seasons {
                episodesPanel(seasons)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .opacity(store.isMaskShow ? 1 : 0)
        .allowsHitTesting(store.isMaskShow)
        .animation(.easeInOut(duration: 0.28), value: store.isMaskShow)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: episodesShown)
        .onChange(of: store.isMaskShow) {
            if !store.isMaskShow { closeEpisodes() }
        }
        #if DEBUG
        .task {
            // Test hooks: KP_CONTROLS keeps the controls up, KP_EPISODES opens the «Серии» panel.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(4))
            if env["KP_CONTROLS"] != nil { store.send(.lockMask(true)) }
            if env["KP_EPISODES"] != nil, store.isSeries { toggleEpisodes() }
            // KP_PAUSE: pauses, for the pause screen (with KP_PAUSE_DELAY=1 it comes a second later).
            if env["KP_PAUSE"] != nil, store.isPlaying { store.send(.playPauseTapped) }
            // KP_HUD: three jumps forward, as from the arrow key.
            if env["KP_HUD"] != nil {
                for _ in 0 ..< 3 {
                    store.send(.moveCommand(.right))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        #endif
    }

    // MARK: - Scrims

    /// The picture darkens at the top and the bottom, so the controls read over a bright frame; smaller controls need
    /// less of it.
    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: metrics.compact ? 130 : 150)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .frame(height: metrics.compact ? 240 : 280)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            PlayerClock(left: max(0, store.duration - store.currentTime), rate: rate, height: metrics.playerTransport, size: metrics.compact ? 13 : 13.5)

            Spacer()

            HStack(spacing: 2) {
                if engine.pipController != nil, AVPictureInPictureController.isPictureInPictureSupported() {
                    Button {
                        store.send(.pictureInPictureTapped)
                    } label: {
                        Image(systemName: "pip.enter")
                    }
                    .buttonStyle(PlainIconStyle())
                    .disabled(store.isPictureInPictureActive || !store.isPictureInPicturePossible)
                    .help("Картинка в картинке")
                }

                if store.routesDetected {
                    AirPlayButtonView(player: player) { isPressed in
                        store.send(isPressed ? .lockMask(true) : .unlockMask(true), animation: .easeInOut)
                    }
                    .frame(width: 28, height: 28)
                }

                Button {
                    store.send(.toggleMuteTapped)
                } label: {
                    Image(systemName: store.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: Double(store.volume))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PlainIconStyle())
                .keyboardShortcut(.init("m"), modifiers: [])
                .help("Звук (M)")

                SliderWithoutTextView(value: Binding {
                    store.volume
                } set: { volume in
                    store.send(.volumeChanged(volume))
                }, inRange: 0 ... 1, activeFillColor: KP.fg, fillColor: KP.fg.opacity(0.85), emptyColor: KP.fg.opacity(0.22), height: 5)
                    .frame(width: metrics.compact ? 84 : 96, height: 12)
                    .padding(.trailing, 10)
            }
            .padding(.horizontal, 5)
            .frame(height: metrics.playerTransport)
            .kpGlass()
        }
        .padding(.top, 20)
        .padding(.leading, 92) // the traffic lights (in a window)
        .padding(.trailing, KP.gutter)
    }

    // MARK: - Middle

    private var centerControls: some View {
        HStack(spacing: metrics.compact ? 28 : 36) {
            Button {
                store.send(.skip(-10), animation: .easeInOut(duration: 0.15))
            } label: {
                Image(systemName: "gobackward.10")
            }
            .buttonStyle(KPGlassIconButtonStyle(diameter: metrics.playerSkip, symbolScale: 0.42))
            .help("Назад на 10 секунд (←)")

            ZStack {
                if store.isLoading {
                    KPLoadingView()
                        .frame(width: metrics.playerMain, height: metrics.playerMain)
                        .kpGlass(in: Circle())
                } else {
                    Button {
                        store.send(.playPauseTapped)
                    } label: {
                        // The triangle's weight sits left of its box: nudged right by ~7% of the glyph so it looks
                        // centred in the circle (a fixed 3 pt was too much at the smaller sizes).
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace.downUp))
                            .offset(x: store.isPlaying ? 0 : metrics.playerMain * 0.38 * 0.07)
                    }
                    .buttonStyle(KPGlassIconButtonStyle(diameter: metrics.playerMain, symbolScale: 0.38))
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Пауза (пробел)")
                }
            }
            .frame(width: metrics.playerMain, height: metrics.playerMain)

            Button {
                store.send(.skip(10), animation: .easeInOut(duration: 0.15))
            } label: {
                Image(systemName: "goforward.10")
            }
            .buttonStyle(KPGlassIconButtonStyle(diameter: metrics.playerSkip, symbolScale: 0.42))
            .help("Вперёд на 10 секунд (→)")
        }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    if let line = subtitleLine {
                        Text(verbatim: line)
                            .font(KP.font(metrics.playerSubtitle, .semibold))
                            .foregroundStyle(KP.fg70)
                            .lineLimit(1)
                    }
                    Text(verbatim: store.name)
                        .font(KP.font(metrics.playerTitle, .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(KP.fg)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 14)
                        .help(store.name)
                }

                Spacer(minLength: 20)

                KPGlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        if store.isSeries {
                            Button {
                                store.send(.previousTrackTapped, animation: .easeInOut(duration: 0.15))
                            } label: {
                                Image(systemName: "backward.end.fill")
                            }
                            .buttonStyle(KPGlassIconButtonStyle(onPress: lockWhilePressed))
                            .disabled(!store.hasPreviousEpisode)
                            .opacity(store.hasPreviousEpisode ? 1 : 0.4)
                            .help("Предыдущая серия")

                            Button {
                                toggleEpisodes()
                            } label: {
                                Label("Серии", systemImage: "rectangle.stack.fill")
                            }
                            .buttonStyle(KPGlassButtonStyle())

                            Button {
                                store.send(.nextTrackTapped, animation: .easeInOut(duration: 0.15))
                            } label: {
                                Image(systemName: "forward.end.fill")
                            }
                            .buttonStyle(KPGlassIconButtonStyle(onPress: lockWhilePressed))
                            .disabled(!store.hasNextEpisode)
                            .opacity(store.hasNextEpisode ? 1 : 0.4)
                            .help("Следующая серия")
                        }

                        if !store.subtitlesOptions.isEmpty {
                            subtitlesMenu
                        }

                        settingsMenu

                        Button {
                            store.send(.userActivity)
                            Windows.player.window?.toggleFullScreen(nil)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(KPGlassIconButtonStyle())
                        .keyboardShortcut("f", modifiers: [])
                        .help("Во весь экран (F)")
                    }
                }
            }

            SeekBarView()
        }
        .padding(.horizontal, KP.gutter)
        .padding(.bottom, metrics.compact ? 22 : 28)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
    }

    /// «1 сезон · 4 серия · «Пилот» · Дубляж», or just the voice-over for a film.
    private var subtitleLine: String? {
        var parts: [String] = []
        if let season = store.season, let episode = store.episode {
            parts.append(season.name.first?.isNumber == true ? "\(season.name) сезон" : season.name)
            parts.append(episode.name.first?.isNumber == true ? "\(episode.name) серия" : episode.name)
            if let title = store.episodeTitle { parts.append("«\(title)»") }
        }
        if !store.voiceActing.name.isEmpty { parts.append(store.voiceActing.name) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func lockWhilePressed(_ isPressed: Bool) {
        store.send(isPressed ? .lockMask(true) : .unlockMask(true), animation: .easeInOut)
    }

    private var subtitlesMenu: some View {
        Menu {
            Picker("Субтитры", selection: Binding {
                store.subtitles
            } set: { subtitles in
                store.send(.subtitlesSelected(subtitles))
            }) {
                Text(verbatim: "Без субтитров").tag(nil as String?)

                ForEach(store.subtitlesOptions) { subtitles in
                    Text(subtitles.displayName).tag(subtitles.tag as String?)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: store.subtitles == nil ? "captions.bubble" : "captions.bubble.fill")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(KPGlassIconButtonStyle(onPress: lockWhilePressed))
        .fixedSize()
        .help("Субтитры")
    }

    private var settingsMenu: some View {
        Menu {
            if store.actings.count > 1 {
                Picker("Озвучка", systemImage: "waveform", selection: Binding {
                    store.voiceActing.translatorId
                } set: { id in
                    guard let acting = store.actings.first(where: { $0.translatorId == id }) else { return }
                    store.send(.voiceSelected(acting))
                }) {
                    ForEach(store.actings) { acting in
                        Text(verbatim: voiceLabel(acting)).tag(acting.translatorId)
                    }
                }
                .pickerStyle(.menu)
            }

            if !store.movie.getAvailableQualities().isEmpty {
                Picker("Качество", systemImage: "4k.tv", selection: Binding {
                    store.quality
                } set: {
                    store.send(.qualitySelected($0))
                }) {
                    ForEach(store.movie.getAvailableQualities(), id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("Скорость", systemImage: "gauge.with.needle", selection: $rate) {
                ForEach(PlayerEngine.rates, id: \.self) { value in
                    Text(verbatim: value == 1 ? "Обычная" : "\(value)×").tag(value)
                }
            }
            .pickerStyle(.menu)

            Picker("Таймер сна", systemImage: "moon.zzz", selection: Binding {
                store.timer
            } set: {
                store.send(.timerSelected($0))
            }) {
                Text(verbatim: "Выключен").tag(nil as Int?)

                ForEach(store.times, id: \.self) { time in
                    Text(verbatim: time == -1 ? "До конца серии" : time >= 3600 ? "1 час" : "\(time / 60) минут").tag(time as Int?)
                }
            }
            .pickerStyle(.menu)

            Picker("Картинка", systemImage: "arrow.up.left.and.arrow.down.right.rectangle", selection: $videoGravity) {
                ForEach(VideoGravity.allCases) { videoGravity in
                    Text(videoGravity.localizedKey).tag(videoGravity)
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $ambientLight) {
                Label("Подсветка вокруг видео", systemImage: "light.panel")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(KPGlassIconButtonStyle(onPress: lockWhilePressed))
        .fixedSize()
        .help("Озвучка, качество, скорость, таймер сна")
    }

    /// «Дубляж  ·  42% · с рекламой»: the share of the viewers and the site's marks, as on the title's page.
    private func voiceLabel(_ acting: MovieVoiceActing) -> String {
        var parts: [String] = []
        if let percent = store.popularity.first(where: { $0.name == acting.name })?.percent {
            parts.append(percent < 1 ? "<1%" : "\(Int(percent.rounded()))%")
        }
        if acting.isAds == "1" { parts.append("с рекламой") }
        if acting.isCamrip == "1" { parts.append("CAMRip") }
        if acting.isDirector == "1" { parts.append("реж. версия") }
        if acting.isPremium, isUserPremium == nil { parts.append("премиум") }
        return parts.isEmpty ? acting.name : "\(acting.name)  ·  \(parts.joined(separator: " · "))"
    }

    // MARK: - Episodes

    private func toggleEpisodes() {
        if episodesShown {
            closeEpisodes()
        } else {
            panelSeason = store.season
            episodesShown = true
            store.send(.lockMask(true))
        }
    }

    private func closeEpisodes() {
        guard episodesShown else { return }
        episodesShown = false
        store.send(.unlockMask(true))
    }

    private func episodesPanel(_ seasons: [MovieSeason]) -> some View {
        let season = panelSeason ?? store.season ?? seasons.first
        let watchedEpisodes = store.watchedEpisodes

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(verbatim: "Серии")
                    .font(KP.font(17, .bold))
                    .foregroundStyle(KP.fg)
                Spacer()
                Button {
                    closeEpisodes()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(KPGlassIconButtonStyle(diameter: 28))
                .keyboardShortcut(.cancelAction)
            }

            if seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { item in
                            KPPill(title: item.name.first?.isNumber == true ? "\(item.name) сезон" : item.name, selected: item == season) {
                                withAnimation(.snappy) { panelSeason = item }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            if let season {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(season.episodes) { episode in
                                let current = season == store.season && episode == store.episode
                                // Watched ones are greyed with a tick, as on the TV.
                                let watched = !current && watchedEpisodes.contains(PlayerFeature.State.episodeKey(season, episode))
                                KPPill(
                                    title: episode.name.first?.isNumber == true ? "\(episode.name) серия" : episode.name,
                                    detail: watched ? "✓" : nil,
                                    selected: current,
                                    dimmed: watched
                                ) {
                                    store.send(.episodeSelected(season, episode))
                                    closeEpisodes()
                                }
                                .id(episode.id)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        if let episode = store.episode { proxy.scrollTo(episode.id, anchor: .center) }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 980)
        .kpGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, KP.gutter)
        .padding(.bottom, bottomBarHeight + 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// A bare icon in the top capsule.
private struct PlainIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KPHoverable { hover in
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hover ? KP.fg : KP.fg80)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
        }
    }
}

/// «12:16 · закончится в 13:04», 24-hour like the rest of the app (not the system's 12-hour English format).
private struct PlayerClock: View {
    /// Seconds still to go.
    let left: Double
    let rate: Float
    /// As tall as the sound capsule beside it; a status line's type.
    let height: CGFloat
    let size: CGFloat

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(verbatim: Self.formatter.string(from: context.date))
                    .foregroundStyle(KP.fg)
                if left > 0, left < 60 * 60 * 24 {
                    let end = context.date.addingTimeInterval(left / Double(max(rate, 0.25)))
                    Text(verbatim: "·  закончится в \(Self.formatter.string(from: end))")
                        .foregroundStyle(KP.fg70)
                }
            }
            .font(KP.font(size, .semibold).monospacedDigit())
            .padding(.horizontal, 14)
            .frame(height: height)
            .kpGlass()
        }
    }
}
