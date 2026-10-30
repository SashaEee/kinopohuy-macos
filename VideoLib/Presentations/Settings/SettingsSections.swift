import AppKit
import Defaults
import Dependencies
import Kingfisher
import SQLiteData
import SwiftUI

// MARK: - Основное

/// The site's address, the account, and the app's look.
struct GeneralSettings: View {
    @Default(.mirror) private var mirror
    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.isUserPremium) private var isUserPremium
    @Default(.showLogo) private var showLogo
    @Default(.snow) private var snow
    @Default(.recentSearches) private var recentSearches

    @Dependency(\.appRouter) private var appRouter

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsGroup(title: "Сайт", footer: "Адрес не встроен в приложение: его указываете вы.") {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "Адрес сайта")
                    .font(KP.font(13.5, .medium))
                    .foregroundStyle(KP.fg)

                SiteAddressEditor()
            }
            .padding(16)
        }

        SettingsGroup(title: "Аккаунт") {
            SettingsRow(title: isLoggedIn ? "Вход выполнен" : "Вход не выполнен", subtitle: accountSubtitle) {
                if isLoggedIn {
                    Button {
                        showInMainWindow(.signOut)
                    } label: {
                        Text(verbatim: "Выйти")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                } else {
                    Button {
                        showInMainWindow(.signIn)
                    } label: {
                        Text(verbatim: "Войти")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .disabled(!SiteAddress.isConfigured(mirror))
                    .opacity(SiteAddress.isConfigured(mirror) ? 1 : 0.45)
                }
            }
        }

        SettingsGroup(title: "Вид") {
            SettingsToggle(title: "Логотип и название в верхней панели", subtitle: "Выключите, чтобы разделы начинались сразу после кнопок окна", isOn: $showLogo)
            SettingsToggle(title: "Снег на Новый год", subtitle: "Последние две недели декабря и первые две января", isOn: $snow)
        }

        SettingsGroup(title: "Поиск") {
            SettingsRow(title: "Недавние запросы", subtitle: recentSearches.isEmpty ? "Пока пусто" : "Сохранено запросов: \(recentSearches.count)") {
                Button {
                    withAnimation(.snappy) {
                        recentSearches = []
                    }
                } label: {
                    Text(verbatim: "Очистить")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
                .disabled(recentSearches.isEmpty)
                .opacity(recentSearches.isEmpty ? 0.45 : 1)
            }
        }
    }

    private var accountSubtitle: String {
        if isLoggedIn {
            if let isUserPremium {
                return "Премиум ещё \(isUserPremium) дн."
            }

            return "Закладки, история и новые серии берутся с сайта"
        }

        return SiteAddress.isConfigured(mirror) ? "Войдите, чтобы видеть закладки, историю и новые серии" : "Сначала укажите адрес сайта"
    }

    /// Sign-in and sign-out live on the main window (its sheet and confirmation): bring it forward (opened first if it
    /// was closed, as Help → «Отказ от ответственности» does) and ask it.
    private func showInMainWindow(_ route: AppRoute) {
        if Windows.videolib.window == nil {
            openWindow(id: Windows.videolib.id)
        }

        NSApp.activate()
        Windows.videolib.window?.makeKeyAndOrderFront(nil)

        appRouter.present(route)
    }
}

// MARK: - Плеер

/// Every preference of the player: quality, the window, the picture, the sound, the media keys.
struct PlayerSettings: View {
    @Default(.defaultQuality) private var defaultQuality
    @Default(.playerFullscreen) private var playerFullscreen
    @Default(.hideMainWindow) private var hideMainWindow
    @Default(.videoGravity) private var videoGravity
    @Default(.ambientLight) private var ambientLight
    @Default(.spatialAudio) private var spatialAudio
    @Default(.mediaControlButtonIsSeeking) private var mediaControlButtonIsSeeking

    var body: some View {
        SettingsGroup(title: "Воспроизведение") {
            SettingsRow(title: "Качество по умолчанию", subtitle: "С ним начинается видео; поменять можно в самом плеере") {
                Picker(selection: $defaultQuality) {
                    ForEach(DefaultQuality.allCases) { quality in
                        Text(quality.localizedKey)
                            .tag(quality)
                    }
                } label: {
                    Text(verbatim: "Качество по умолчанию")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsToggle(title: "Открывать плеер на весь экран", isOn: $playerFullscreen)
            SettingsToggle(title: "Прятать главное окно, пока открыт плеер", subtitle: "Оно вернётся, когда плеер закроется", isOn: $hideMainWindow)
        }

        SettingsGroup(title: "Картинка и звук") {
            SettingsRow(title: "Картинка", subtitle: "Как видео ложится в окно") {
                Picker(selection: $videoGravity) {
                    ForEach(VideoGravity.allCases) { gravity in
                        Text(gravity.localizedKey)
                            .tag(gravity)
                    }
                } label: {
                    Text(verbatim: "Картинка")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsToggle(title: "Подсветка вокруг видео", subtitle: "Поля вокруг кадра мягко светятся его цветами. Работает в режиме «Вместить»", isOn: $ambientLight)

            SettingsRow(title: "Пространственное аудио", subtitle: "Объёмный звук в наушниках, которые его поддерживают") {
                Picker(selection: $spatialAudio) {
                    ForEach(SpatialAudio.allCases) { format in
                        Text(format.localizedKey)
                            .tag(format)
                    }
                } label: {
                    Text(verbatim: "Пространственное аудио")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }

        SettingsGroup(title: "Управление") {
            SettingsToggle(title: "Медиаклавиши перематывают", subtitle: "⏮ и ⏭ на клавиатуре и в наушниках перематывают видео, а не переключают серии", isOn: $mediaControlButtonIsSeeking)
        }
    }
}

// MARK: - Загрузки

/// Where downloads go and how many run at once.
struct DownloadsSettings: View {
    @Default(.maxConcurrentDownloads) private var maxConcurrentDownloads

    @Environment(Downloader.self) private var downloader

    var body: some View {
        SettingsGroup(footer: "Ход загрузок виден в строке меню, пока они идут.") {
            SettingsRow(title: "Папка", subtitle: "Загрузки › \(Downloader.folderName)") {
                Button {
                    showFolder()
                } label: {
                    Text(verbatim: "Показать в Finder")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }

            SettingsRow(title: "Одновременно загружать", subtitle: downloader.downloads.isEmpty ? nil : "Сейчас в списке: \(downloader.downloads.count)") {
                HStack(spacing: 12) {
                    Slider(value: Binding { Double(maxConcurrentDownloads) } set: { maxConcurrentDownloads = Int($0) }, in: 1 ... 10, step: 1) {
                        Text(verbatim: "Одновременно загружать")
                    } onEditingChanged: { isEditing in
                        if !isEditing {
                            downloader.maxConcurrentDownloadsChange()
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 160)

                    Text(verbatim: "\(maxConcurrentDownloads)")
                        .font(KP.font(14, .semibold).monospacedDigit())
                        .foregroundStyle(KP.fg)
                        .contentTransition(.numericText(value: Double(maxConcurrentDownloads)))
                        .animation(.snappy, value: maxConcurrentDownloads)
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
    }

    /// The downloads folder in Finder; ~/Downloads while nothing has been downloaded yet.
    private func showFolder() {
        guard let folder = Downloader.folderURL else { return }

        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.open(folder.deletingLastPathComponent())
        }
    }
}

// MARK: - Данные

/// The image cache, and what the app remembers about watching (places, history, chosen voice-overs).
struct DataSettings: View {
    @Default(.cache) private var cache
    @Default(.isLoggedIn) private var isLoggedIn

    @Dependency(\.defaultDatabase) private var database
    @FetchOne(PlayerPosition.count(), animation: .easeInOut) private var playerPositionsCount: Int = 0
    @FetchOne(SelectPosition.count(), animation: .easeInOut) private var selectPositionsCount: Int = 0

    @Dependency(\.recommender) private var recommender

    @State private var diskCacheSize: UInt?
    @State private var confirmClearPositions = false
    @State private var confirmClearSelections = false
    @State private var confirmClearRecommendations = false

    var body: some View {
        SettingsGroup(title: "Картинки") {
            SettingsRow(title: "Кэш обложек", subtitle: "Где хранить обложки, чтобы не скачивать их снова") {
                Picker(selection: $cache) {
                    ForEach(Cache.allCases) { cache in
                        Text(cache.localizedKey)
                            .tag(cache)
                    }
                } label: {
                    Text(verbatim: "Кэш обложек")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(title: "Занято на диске", subtitle: diskCacheSize.map { Int64($0).formatted(.byteCount(style: .file).locale(Locale(identifier: "ru_RU"))) } ?? "Считаем…") {
                Button {
                    Task {
                        await ImageCache.default.clearCache()
                        await measureDiskCache()
                    }
                } label: {
                    Text(verbatim: "Очистить")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
                .disabled(diskCacheSize == 0)
                .opacity(diskCacheSize == 0 ? 0.45 : 1)
            }
        }
        .onChange(of: cache) {
            Task {
                await applyCacheMode()
                await measureDiskCache()
            }
        }
        .task {
            await measureDiskCache()
        }

        SettingsGroup(title: "Просмотр") {
            SettingsRow(title: "Места просмотра и история", subtitle: playerPositionsCount == 0 ? "Пока пусто" : "Сохранено мест: \(playerPositionsCount). По ним работают «Продолжить просмотр» и полоски прогресса") {
                Button {
                    confirmClearPositions = true
                } label: {
                    Text(verbatim: "Очистить")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
                .disabled(playerPositionsCount == 0)
                .opacity(playerPositionsCount == 0 ? 0.45 : 1)
            }

            // Beside the history, as the recommendations are built from it (the same button as in «Рекомендации»).
            SettingsRow(title: "Данные рекомендаций", subtitle: "Оценки, отметки «Скрыть» и «Уже смотрел», показы и вкус. Изученный каталог тайтлов останется") {
                Button {
                    confirmClearRecommendations = true
                } label: {
                    Text(verbatim: "Очистить")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }

            if !isLoggedIn {
                SettingsRow(title: "Выбранные озвучки и серии", subtitle: selectPositionsCount == 0 ? "Пока пусто" : "Запомнено для тайтлов: \(selectPositionsCount). Без входа это хранится только здесь") {
                    Button {
                        confirmClearSelections = true
                    } label: {
                        Text(verbatim: "Очистить")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .disabled(selectPositionsCount == 0)
                    .opacity(selectPositionsCount == 0 ? 0.45 : 1)
                }
            }
        }
        .confirmationDialog(Text(verbatim: "Очистить места просмотра и историю?"), isPresented: $confirmClearPositions) {
            Button(role: .destructive) {
                Task.detached(priority: .utility) {
                    try? await database.write { db in
                        try PlayerPosition.delete().execute(db)
                        try WatchHistory.delete().execute(db)
                    }
                }
            } label: {
                Text(verbatim: "Очистить")
            }
        } message: {
            Text(verbatim: "Пропадут «Продолжить просмотр» и полоски прогресса. Отменить это нельзя.")
        }
        .confirmationDialog(Text(verbatim: "Забыть выбранные озвучки и серии?"), isPresented: $confirmClearSelections) {
            Button(role: .destructive) {
                Task.detached(priority: .utility) {
                    try? await database.write { db in
                        try SelectPosition.delete().execute(db)
                    }
                }
            } label: {
                Text(verbatim: "Забыть")
            }
        } message: {
            Text(verbatim: "Тайтлы будут открываться с озвучкой и серией по умолчанию.")
        }
        .confirmationDialog(Text(verbatim: "Очистить все данные рекомендаций?"), isPresented: $confirmClearRecommendations) {
            Button(role: .destructive) {
                Task {
                    await recommender.clearAll()
                    RecCardMarks.shared.forgetAll()
                }
            } label: {
                Text(verbatim: "Очистить")
            }
        } message: {
            Text(verbatim: "Пропадут оценки, отметки «Скрыть» и «Уже смотрел», история показов и вкус. Отменить это нельзя — можно сначала сделать «Экспорт…» в разделе «Рекомендации».")
        }
    }

    private func measureDiskCache() async {
        let size = (try? await ImageCache.default.diskStorageSize) ?? 0

        withAnimation(.snappy) {
            diskCacheSize = size
        }
    }

    /// The new cache mode takes effect at once: what it no longer keeps is dropped.
    private func applyCacheMode() async {
        switch cache {
        case .off:
            await ImageCache.default.clearCache()

            ImageCache.default.memoryStorage.config.expiration = .expired
            ImageCache.default.diskStorage.config.expiration = .expired
        case .memory:
            await ImageCache.default.clearDiskCache()

            ImageCache.default.memoryStorage.config.expiration = .days(1)
            ImageCache.default.diskStorage.config.expiration = .expired
        case .disk:
            ImageCache.default.clearMemoryCache()

            ImageCache.default.memoryStorage.config.expiration = .expired
            ImageCache.default.diskStorage.config.expiration = .days(7)
        case .all:
            ImageCache.default.memoryStorage.config.expiration = .days(1)
            ImageCache.default.diskStorage.config.expiration = .days(7)
        }
    }
}
