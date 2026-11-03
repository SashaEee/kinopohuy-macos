import ComposableArchitecture
import Defaults
import Dependencies
import GRDB
import Kingfisher
import Sparkle
import SQLiteData
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private nonisolated let updateNotificationIdentifier = "kinopohuy.update-available"
    var updaterController: SPUStandardUpdaterController!

    /// Sparkle's relaunch into the new version, held while downloads are running (it would cut them short).
    private var postponedRelaunch: (() -> Void)?
    private var postponedRelaunchWatch: Task<Void, Never>?

    override init() {
        super.init()

        // Release builds with the real feed and key only (AppUpdates): a Debug build, or one made before the feed
        // and key were decided, never asks for updates.
        updaterController = SPUStandardUpdaterController(startingUpdater: AppUpdates.startsUpdater, updaterDelegate: self, userDriverDelegate: self)
    }

    func applicationDidFinishLaunching(_: Notification) {
        UNUserNotificationCenter.current().delegate = self

        NSWindow.allowsAutomaticWindowTabbing = false

        // Quit requests from outside (Sparkle's installer before it swaps the app, the Dock's «Завершить») go through
        // the same door as ⌘Q, so an open sheet doesn't make the app refuse.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuit(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
    }

    @objc private func handleQuit(_: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        NSApp.terminateClosingSheets()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        Downloader.shared.downloads.isEmpty
    }

    func applicationWillTerminate(_: Notification) {
        if !Downloader.shared.downloads.isEmpty {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests.filter { $0.content.categoryIdentifier == "cancel" }.map(\.identifier))
            }

            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notifications.filter { $0.request.content.categoryIdentifier == "cancel" }.map(\.request.identifier))
            }
        }

        Downloader.shared.terminate()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list, .banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == updateNotificationIdentifier, response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                updaterController.checkForUpdates(nil)
            }
        } else {
            let userInfo = response.notification.request.content.userInfo

            switch response.actionIdentifier {
            case "cancel":
                if let gid = userInfo["gid"] as? String {
                    Task { @MainActor in
                        Downloader.shared.remove(gid)
                    }
                }
            case "open":
                if let url = userInfo["url"] as? String, let fileUrl = URL(string: url), fileUrl.isFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([fileUrl])
                }
            case "retry":
                if let retryData = userInfo["data"] as? Data, let data = try? JSONDecoder().decode(DownloadData.self, from: retryData) {
                    Task { @MainActor in
                        Downloader.shared.download(data)
                    }
                }
            case "need_premium":
                NSWorkspace.shared.open(Defaults[.mirror].appending(path: "payments", directoryHint: .notDirectory))
            default:
                break
            }
        }

        completionHandler()
    }
}

extension AppDelegate: SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    nonisolated func updater(_: SPUUpdater, willScheduleUpdateCheckAfterDelay _: TimeInterval) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { _, _ in }
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated {
            Task { @MainActor in
                NSApp.dockTile.badgeLabel = "1"
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "key.update")
            content.body = String(localized: "key.update.description-\(update.displayVersionString)")

            let request = UNNotificationRequest(identifier: updateNotificationIdentifier, content: content, trigger: nil)

            UNUserNotificationCenter.current().add(request)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        Task { @MainActor in
            NSApp.dockTile.badgeLabel = ""
        }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [updateNotificationIdentifier])
    }

    /// «Установить и перезапустить» while something is downloading: relaunching stops aria2 and cuts the files short.
    /// The app asks first; by default it waits and relaunches into the new version by itself once the last download
    /// has finished and no film is playing.
    func updater(_: SPUUpdater, shouldPostponeRelaunchForUpdate _: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !Downloader.shared.downloads.isEmpty else { return false }

        postponedRelaunch = installHandler

        // Asked on the next turn of the run loop, after Sparkle has taken the answer.
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Обновление установится после загрузок"
            alert.informativeText = "Перезапуск прервёт то, что сейчас скачивается. \(AppInfo.name) перезапустится и обновится сам, когда загрузки закончатся."
            alert.addButton(withTitle: "Подождать")
            alert.addButton(withTitle: "Перезапустить сейчас")

            if alert.runModal() == .alertSecondButtonReturn {
                relaunchIntoUpdate()
            } else {
                waitForDownloadsThenRelaunch()
            }
        }

        return true
    }

    /// Polls every couple of seconds: no downloads left and no player window open → relaunch.
    private func waitForDownloadsThenRelaunch() {
        postponedRelaunchWatch?.cancel()
        postponedRelaunchWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled, !Downloader.shared.downloads.isEmpty || Windows.player.window?.isVisible == true {
                try? await Task.sleep(for: .seconds(2))
            }

            guard !Task.isCancelled else { return }

            self?.relaunchIntoUpdate()
        }
    }

    private func relaunchIntoUpdate() {
        let relaunch = postponedRelaunch
        postponedRelaunch = nil
        postponedRelaunchWatch = nil

        relaunch?()
    }
}

extension NSApplication {
    /// AppKit won't quit while a window has a sheet attached: ⌘Q and «Не сейчас — выйти» on the first-run sheet
    /// would do nothing. Ends them, innermost first (a sheet can carry its own).
    func closeSheets() {
        for _ in 0 ... windows.count {
            guard let window = windows.first(where: { $0.attachedSheet != nil && $0.attachedSheet?.attachedSheet == nil }),
                  let sheet = window.attachedSheet
            else { return }
            window.endSheet(sheet)
        }
    }

    /// Quits even with a sheet open: the sheets go first, the app on the next turn of the run loop.
    func terminateClosingSheets() {
        closeSheets()
        DispatchQueue.main.async {
            self.terminate(nil)
        }
    }
}

@main
struct VideoLibApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: StoreOf<AppFeature>
    @State private var downloader: Downloader = .shared
    @State private var cookiesManager: CookiesManager = .shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @Default(.mirror) private var mirror

    init() {
        KP.registerFonts()

        prepareDependencies {
            $0.defaultDatabase = try! Self.appDatabase()
        }

        let store = Store(initialState: AppFeature.State()) { AppFeature() }
        store.send(.appLaunched)
        _store = State(initialValue: store)

        KingfisherManager.shared.defaultOptions += [.backgroundDecode]

        // Posters stay in memory for a day (within ~400 MB), not the default 5 minutes: back on Home after an episode,
        // nothing is decoded again while scrolling.
        ImageCache.default.memoryStorage.config.totalCostLimit = 400 * 1024 * 1024
        ImageCache.default.memoryStorage.config.countLimit = 600
        ImageCache.default.memoryStorage.config.expiration = .days(1)

        switch Defaults[.cache] {
        case .off:
            ImageCache.default.memoryStorage.config.expiration = .expired
            ImageCache.default.diskStorage.config.expiration = .expired
        case .memory:
            ImageCache.default.diskStorage.config.expiration = .expired
        case .disk:
            ImageCache.default.memoryStorage.config.expiration = .expired
        case .all:
            break
        }
    }

    var body: some Scene {
        WindowGroup(id: Windows.videolib.id) {
            ContentView(store: store)
                .environment(downloader)
                .environment(cookiesManager)
                .preferredColorScheme(.dark) // КиноПохуй is dark, like the TV
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commands(content: customCommands)
        .commands(content: removed)

        WindowGroup("key.player", id: Windows.player.id, for: PlayerData.self) { $data in
            if let data {
                PlayerView(data: data)
            }
        }
        .defaultSize(width: 1280, height: 720)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands(content: customCommands)
        .commands(content: removed)

        WindowGroup("key.imageViewer", id: Windows.imageViewer.id, for: URL.self) { $url in
            if let url {
                ImageView(url: url)
                    .preferredColorScheme(.dark)
            }
        }
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands(content: customCommands)
        .commands(content: removed)

        WindowGroup("key.licenses", id: Windows.licenses.id) {
            LicensesView()
                .preferredColorScheme(.dark)
        }
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands(content: customCommands)
        .commands(content: removed)

        Window(Text("key.about-\(AppInfo.name)"), id: Windows.about.id) {
            AboutView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commands(content: customCommands)
        .commands(content: removed)

        Settings {
            SettingsView(updater: delegate.updaterController.updater)
                .environment(downloader)
                .environment(cookiesManager)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commands(content: customCommands)
        .commands(content: removed)

        MenuBarExtra(isInserted: Binding {
            downloader.hasDownloads
        } set: { _ in }) {
            DownloadsView()
                .environment(downloader)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .commands(content: customCommands)
        .commands(content: removed)
    }

    @CommandsBuilder
    func customCommands() -> some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Text("key.settings")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                openWindow(id: Windows.licenses.id)
            } label: {
                Text("key.licenses")
            }
        }

        // «О программе» is a window of its own (AboutView); the update check sits under it, where Mac apps keep it.
        CommandGroup(replacing: .appInfo) {
            Button {
                openWindow(id: Windows.about.id)
            } label: {
                Text("key.about-\(AppInfo.name)")
            }

            UpdateButton(updater: delegate.updaterController.updater)
        }

        // «Выбери за меня» from anywhere (the main window comes forward if another one was in front).
        CommandGroup(before: .sidebar) {
            Button {
                showPickForMe(focusText: false)
            } label: {
                Text(verbatim: "Выбери за меня")
            }
            .keyboardShortcut("j", modifiers: .command)

            Button {
                showPickForMe(focusText: true)
            } label: {
                Text(verbatim: "Что хочется посмотреть…")
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()
        }

        CommandGroup(replacing: .appTermination) {
            Button {
                NSApp.terminateClosingSheets()
            } label: {
                Text("key.close-\(AppInfo.name)")
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button {
                showDisclaimer()
            } label: {
                Text("key.disclaimer")
            }

            // The site's rules only once its address is set (the placeholder has no pages).
            if SiteAddress.isConfigured(mirror) {
                Link(destination: mirror.appending(path: "rules/", directoryHint: .notDirectory)) {
                    Text("key.site.rules")
                }
            }

            // The project's own links, each once it's filled in (AppLinks).
            if AppLinks.isSet(AppLinks.repository) || AppLinks.isSet(AppLinks.issues) || AppLinks.isSet(AppLinks.telegram) || Donations.isAvailable {
                Divider()
            }

            if AppLinks.isSet(AppLinks.repository) {
                Link(destination: AppLinks.repository) {
                    Text(verbatim: "\(AppInfo.name) на GitHub")
                }
            }

            if AppLinks.isSet(AppLinks.issues) {
                Link(destination: AppLinks.issues) {
                    Text(verbatim: "Сообщить о проблеме…")
                }
            }

            if AppLinks.isSet(AppLinks.telegram) {
                Link(destination: AppLinks.telegram) {
                    Text(verbatim: "Канал в Telegram")
                }
            }

            if Donations.isAvailable {
                Button {
                    AppUI.shared.settingsSection = .about
                    openSettings()
                } label: {
                    Text(verbatim: "Поддержать проект…")
                }
            }
        }
    }

    private func showPickForMe(focusText: Bool) {
        if Windows.videolib.window == nil {
            openWindow(id: Windows.videolib.id)
        }

        NSApp.activate()
        Windows.videolib.window?.makeKeyAndOrderFront(nil)

        store.send(.pickForMeTapped(focusText: focusText))
    }

    /// Help → «Отказ от ответственности»: the text over the main window (opened first if it was closed).
    private func showDisclaimer() {
        if Windows.videolib.window == nil {
            openWindow(id: Windows.videolib.id)
        }

        NSApp.activate()
        Windows.videolib.window?.makeKeyAndOrderFront(nil)

        AppUI.shared.isDisclaimerPresented = true
    }

    @CommandsBuilder
    func removed() -> some Commands {
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .singleWindowList) {}
        CommandGroup(replacing: .systemServices) {}
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .windowList) {}
    }

    private struct MenuBarIcon: View {
        var body: some View {
            Image(nsImage: NSImage(resource: .barIcon).resized(to: CGSize(width: 18, height: 18)))
        }
    }

    private static func appDatabase() throws -> any DatabaseWriter {
        let configuration = Configuration()

        #if DEBUG
            // A file of its own: eraseDatabaseOnSchemaChange below must never touch the installed app's places (it
            // lives in the same container).
            let path = try Const.dbPath.replacingOccurrences(of: ".db", with: "-debug.db")
        #else
            let path = try Const.dbPath
        #endif

        let database = try defaultDatabase(path: path, configuration: configuration)

        var migrator = DatabaseMigrator()

        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "player_positions", options: [.ifNotExists, .strict]) { t in
                t.column("id", .text).notNull()
                t.column("acting", .text).notNull()
                t.column("season", .text).notNull()
                t.column("episode", .text).notNull()
                t.column("position", .real).notNull()
                t.primaryKey(["id", "acting", "season", "episode"])
            }

            try db.create(table: "select_positions", options: [.ifNotExists, .strict]) { t in
                t.column("id", .text).notNull()
                t.column("acting", .text).notNull()
                t.column("season", .text)
                t.column("episode", .text)
                t.column("subtitles", .text)
                t.primaryKey(["id"])
            }
        }

        // Each title's and episode's real length (for progress bars and «Осталось N мин»), and what was last played.
        migrator.registerMigration("v2") { db in
            try db.alter(table: "player_positions") { t in
                t.add(column: "duration", .real)
            }

            try db.create(table: "watch_history", options: [.ifNotExists, .strict]) { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("acting", .text).notNull()
                t.column("season", .text).notNull()
                t.column("episode", .text).notNull()
                t.column("position", .real).notNull()
                t.column("duration", .real).notNull()
                t.column("updatedAt", .real).notNull()
            }
        }

        // Recommendations: the local catalogue of titles seen on the site, the session log, ratings and feedback,
        // impressions and the cached Home. All of it stays on this Mac.
        migrator.registerMigration("v3") { db in
            try db.create(table: "title_meta", options: [.ifNotExists, .strict]) { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("path", .text).notNull()
                t.column("level", .text).notNull()
                t.column("kind", .text)
                t.column("primaryGenre", .text)
                t.column("name", .text).notNull()
                t.column("originalName", .text)
                t.column("year", .integer)
                t.column("kpId", .integer)
                t.column("imdbId", .text)
                // The whole RecommenderCore.TitleFeatures as JSON (the columns above are for lookups and indexes).
                t.column("features", .text).notNull()
                t.column("fetchedAt", .real).notNull()
            }
            try db.create(index: "title_meta_kp", on: "title_meta", columns: ["kpId"], ifNotExists: true)
            try db.create(index: "title_meta_imdb", on: "title_meta", columns: ["imdbId"], ifNotExists: true)
            try db.create(index: "title_meta_kind_genre", on: "title_meta", columns: ["kind", "primaryGenre"], ifNotExists: true)

            try db.create(virtualTable: "title_fts", ifNotExists: true, using: GRDB.FTS5()) { t in
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("id").notIndexed()
                t.column("name")
                t.column("originalName")
            }

            try db.create(table: "board_member", options: [.ifNotExists, .strict]) { t in
                t.column("boardKey", .text).notNull()
                t.column("titleId", .text).notNull()
                t.column("rank", .integer)
                t.column("name", .text).notNull()
                t.column("updatedAt", .real).notNull()
                t.primaryKey(["boardKey", "titleId"])
            }
            try db.create(index: "board_member_title", on: "board_member", columns: ["titleId"], ifNotExists: true)

            try db.create(table: "watch_event", options: [.ifNotExists, .strict]) { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("titleId", .text).notNull()
                t.column("acting", .text)
                t.column("season", .text)
                t.column("episode", .text)
                t.column("startedAt", .real).notNull()
                t.column("endedAt", .real).notNull()
                t.column("fromPos", .real).notNull()
                t.column("toPos", .real).notNull()
                t.column("duration", .real).notNull()
                t.column("completed", .integer).notNull()
            }
            try db.create(index: "watch_event_title", on: "watch_event", columns: ["titleId"], ifNotExists: true)

            try db.create(table: "user_rating", options: [.ifNotExists, .strict]) { t in
                t.column("titleId", .text).notNull().primaryKey()
                t.column("level", .real).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .real).notNull()
                t.column("sentToSite", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "title_feedback", options: [.ifNotExists, .strict]) { t in
                t.column("titleId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("createdAt", .real).notNull()
                t.column("until", .real)
                t.primaryKey(["titleId", "kind"])
            }

            try db.create(table: "taste_override", options: [.ifNotExists, .strict]) { t in
                t.column("feature", .text).notNull().primaryKey()
                t.column("mode", .text).notNull()
                t.column("until", .real)
            }

            try db.create(table: "rec_impression", options: [.ifNotExists, .strict]) { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("titleId", .text).notNull()
                t.column("surface", .text).notNull()
                t.column("shownAt", .real).notNull()
                t.column("opened", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "rec_impression_title", on: "rec_impression", columns: ["titleId"], ifNotExists: true)

            try db.create(table: "rec_cache", options: [.ifNotExists, .strict]) { t in
                t.column("surface", .text).notNull().primaryKey()
                t.column("payload", .text).notNull()
                t.column("profileHash", .text).notNull()
                t.column("builtAt", .real).notNull()
            }
        }

        // Recommendations, continued: the account's lists as last seen, board sizes, genre slugs, the background
        // reader's counters and its cache of title pages (RecSchema).
        migrator.registerMigration("v4") { db in
            try RecSchema.migrateV4(db)
        }

        try migrator.migrate(database)

        return database
    }
}
