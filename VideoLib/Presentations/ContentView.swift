import ComposableArchitecture
import Defaults
import SQLiteData
import SwiftUI

struct ContentView: View {
    @Bindable var store: StoreOf<AppFeature>

    @State private var pageFade = KPPageFade()
    @State private var scrollState = KPScrollState()
    @FetchAll(WatchHistory.all) private var watchHistory: [WatchHistory]

    @Default(.isLoggedIn) private var isLoggedIn
    @Default(.mirror) private var mirror
    @Default(.isUserPremium) private var isUserPremium
    @Default(.snow) private var snow
    @Default(.showLogo) private var showLogo

    @Bindable private var ui = AppUI.shared
    @State private var isOnboardingPresented = false

    private var visibleTabs: [Tabs] { Tabs.barOrder.filter { isLoggedIn || !$0.needAccount } }

    /// The sections switch in place under the top bar; a title, list or person opened from one is pushed on the
    /// shared stack (the system toolbar is hidden: back, sections and the account are all in the top bar).
    private var shell: some View {
        ZStack(alignment: .top) {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                root(for: store.selectedTab)
                    .id(store.selectedTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .kpScreenChrome()
            } destination: { store in
                PathView(store: store)
                    .kpScreenChrome()
            }
            .environment(\.kpNavigate, KPNavigateAction(id: ObjectIdentifier(pageFade)) { [store, pageFade] route in
                pageFade.run(key: route) { store.send(.pushRoute(route)) }
            })
            .onChange(of: store.pendingRoute) { _, pending in
                // A push decided by a feature (a banner's «Подробнее», a link on a title's page) goes the same way.
                guard let pending else { return }
                store.send(.pendingRouteTaken)
                pageFade.run(key: pending.route) { store.send(.pushRoute(pending.route)) }
            }

            // Pages change under this cover (see KPPageFade); the top bar stays above it.
            KP.bg
                .opacity(pageFade.cover)
                .ignoresSafeArea()
                .allowsHitTesting(pageFade.blocking)

            KPTopBar(
                tabs: visibleTabs,
                selected: store.selectedTab,
                title: \.title,
                select: select,
                canGoBack: !store.path.isEmpty,
                back: {
                    pageFade.run {
                        if let last = store.path.ids.last { store.send(.path(.popFrom(id: last))) }
                    }
                },
                logo: Image(.kinoPohuySun),
                showsLogo: showLogo
            ) {
                topBarTrailing
            }
        }
        .ignoresSafeArea()
        .background(KP.bg)
        .frame(minWidth: 1100, minHeight: 680)
        .kpMetricsFromWindow()
        .environment(\.kpScrollState, scrollState)
        .environment(\.kpWatchHistory, KPWatchHistory(byId: Dictionary(watchHistory.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })))
    }

    /// A section: switch to it, or back to its start if it's the one open.
    private func select(_ tab: Tabs) {
        if tab != store.selectedTab {
            if store.path.isEmpty {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    store.selectedTab = tab
                }
            } else {
                // Leaving an open page for another section: the same dip as going back.
                pageFade.run(key: "tab-\(tab)") { store.selectedTab = tab }
            }
        } else if !store.path.isEmpty {
            pageFade.run(key: "root") {
                if let first = store.path.ids.first { store.send(.path(.popFrom(id: first))) }
            }
        }
    }

    @ViewBuilder
    private var topBarTrailing: some View {
        if let isUserPremium, !KPDemo.isOn {
            Link(destination: mirror.appending(path: "payments", directoryHint: .notDirectory)) {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                    Text(verbatim: "Премиум · \(isUserPremium) дн.")
                        .font(KP.font(12.5, .semibold))
                }
                .foregroundStyle(Const.premiumGradient)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(KP.chip))
            }
            .buttonStyle(.plain)
            .help("Дней премиума осталось")
        }

        Button {
            store.send(.pickForMeTapped(focusText: false))
        } label: {
            Image(systemName: "dice")
        }
        .buttonStyle(KPIconButtonStyle(diameter: 28, filled: false))
        .help("Выбери за меня (⌘J)")

        Button {
            store.send(.home(.seriesUpdatesTapped))
        } label: {
            Image(systemName: "bell")
        }
        .buttonStyle(KPIconButtonStyle(diameter: 28, filled: false))
        .help("Новые серии")

        SettingsLink {
            Image(systemName: "gearshape")
        }
        .buttonStyle(KPIconButtonStyle(diameter: 28, filled: false))
        .help("Настройки")

        if isLoggedIn {
            Menu {
                Button("Выйти из аккаунта") {
                    store.isSignOutPresented = true
                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(KP.fg80)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Аккаунт")
        } else {
            Button("Войти") {
                store.send(.signInTapped)
            }
            .buttonStyle(KPSecondaryButtonStyle(size: 13))
        }
    }

    var body: some View {
        shell
        .onChange(of: isLoggedIn) {
            store.send(.loggedInChanged(isLoggedIn))
        }
        .sheet(item: $store.scope(state: \.destination?.signIn, action: \.destination.signIn)) { store in
            SignInSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.signUp, action: \.destination.signUp)) { store in
            SignUpSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.destination?.restore, action: \.destination.restore)) { store in
            RestoreSheetView(store: store)
        }
        .confirmationDialog("key.sign_out.label", isPresented: $store.isSignOutPresented) {
            Button(role: .destructive) {
                store.send(.signOutConfirmed)
            } label: {
                Text("key.yes")
            }
        } message: {
            Text("key.sign_out.q")
        }
        .dialogSeverity(.critical)
        .alert($store.scope(state: \.alert, action: \.alert))
        .confirmationDialog("key.premium_content", isPresented: $store.isPremiumPresented) {
            Link("key.buy", destination: mirror.appending(path: "payments", directoryHint: .notDirectory))
        } message: {
            Text("key.premium.description")
        }
        .sheet(item: $store.scope(state: \.home.seriesUpdates, action: \.home.seriesUpdates)) { store in
            SeriesUpdatesSheetView(store: store)
        }
        .sheet(item: $store.scope(state: \.pickForMe, action: \.pickForMe)) { store in
            PickForMeView(store: store)
        }
        .sheet(isPresented: $store.isCommentsRulesPresented) {
            CommentsRulesSheetView()
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView { signIn in
                isOnboardingPresented = false

                if signIn {
                    Task {
                        // After the first-run sheet has gone: one sheet at a time.
                        try? await Task.sleep(for: .milliseconds(450))
                        store.send(.signInTapped)
                    }
                }
            }
        }
        .sheet(isPresented: $ui.isDisclaimerPresented) {
            DisclaimerSheetView()
        }
        .task {
            // A fresh install, or one still without the site's address: the first-run screen, once the window is up.
            guard !SiteAddress.isConfigured(mirror) else { return }

            try? await Task.sleep(for: .milliseconds(350))
            isOnboardingPresented = true
        }
        .onChange(of: mirror) { _, newMirror in
            store.send(.siteAddressChanged)

            if !SiteAddress.isConfigured(newMirror) {
                isOnboardingPresented = true
            }
        }
        .overlay {
            let weekOfYear = Calendar.current.component(.weekOfYear, from: .now)

            if snow, weekOfYear <= 2 || weekOfYear >= 51 {
                SnowflakesView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func root(for tab: Tabs) -> some View {
        switch tab {
        case .home:
            HomeView(store: store.scope(state: \.home, action: \.home))
        case .search:
            SearchView(store: store.scope(state: \.search, action: \.search))
        case .categories:
            CategoriesView(store: store.scope(state: \.categories, action: \.categories))
        case .collections:
            CollectionsView(store: store.scope(state: \.collections, action: \.collections))
        case .watchingLater:
            WatchingLaterView(store: store.scope(state: \.watchingLater, action: \.watchingLater))
        case .bookmarks:
            BookmarksView(store: store.scope(state: \.bookmarks, action: \.bookmarks))
        }
    }
}

private struct PathView: View {
    let store: StoreOf<AppFeature.Path>

    var body: some View {
        Group {
            switch store.case {
            case let .details(store):
                DetailsView(store: store)
            case let .list(store):
                ListView(store: store)
            case let .person(store):
                PersonView(store: store)
            case let .comments(store):
                CommentsView(store: store)
            }
        }
    }
}
