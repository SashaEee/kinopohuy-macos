import Defaults
import Dependencies
import Foundation
import RecommenderCore

/// The recommender's parts, made once on first use (after the app's database is set up): the catalogue and signal
/// stores, the cache of title pages, the background queue to the site, the engine and the background reader.
final class RecRuntime: Sendable {
    static let shared = RecRuntime()

    let titles: TitleStore
    let signals: SignalStore
    let detailsCache: DetailsCacheStore
    let queue: SiteQueue
    let broadcaster: RecBroadcaster
    let engine: RecommenderEngine
    let enricher: TitleEnricher

    private init() {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.movieDetailsRepository) var movieDetailsRepository

        let broadcaster = RecBroadcaster()
        let titles = TitleStore(database: database)
        let signals = SignalStore(database: database)
        let detailsCache = DetailsCacheStore(database: database)
        let queue = SiteQueue(store: signals)
        let engine = RecommenderEngine(titles: titles, signals: signals, broadcaster: broadcaster)

        // The background reader's pages: the cache first, else the site through the queue (never the app's own
        // session, so no sign-in sheet, header switch or premium change comes from here).
        let details = CachingMovieDetailsRepository(base: movieDetailsRepository, cache: detailsCache) { path in
            let parts = path.pathParts
            guard parts.count == 3 else { throw SiteFailure.unreadable }
            return try await queue.read(MovieDetailsService.getMovieDetails(type: parts[0], genre: parts[1], name: parts[2])) { html in
                try MovieDetailsParser.parseMovieDetails(from: html, movieId: path)
            }
        }

        self.broadcaster = broadcaster
        self.titles = titles
        self.signals = signals
        self.detailsCache = detailsCache
        self.queue = queue
        self.engine = engine
        enricher = TitleEnricher(
            titles: titles, signals: signals, queue: queue, details: details,
            hooks: TitleEnricher.Hooks(
                candidates: { limit in await engine.cardCandidates(limit: limit) },
                plan: { await engine.crawlPlan(anchors: signals.anchorIds()) },
                batchDone: { await engine.rebuildSoon() },
                suggestions: { limit in await engine.viewerSuggestions(limit: limit) },
            ),
        )

        #if DEBUG
            RecSelfCheck.report()
        #endif
    }

    // MARK: Requests in words

    /// The rules' reading of a request, with «как X» found in the catalogue and people found in the pool. What
    /// can't be found says so in a chip («Не нашёл «X» на сайте») instead of being dropped silently.
    func parse(_ text: String) async -> ParsedRequest {
        var parsed = RuleIntentParser.parse(text, context: EngineContext(date: .now))
        var chips = parsed.chips.filter { $0.field != .similarTo && $0.field != .people }

        var similar = parsed.intent.similarTo
        for query in parsed.similarQueries {
            if let match = await titles.search(query, limit: 3).first {
                if !similar.contains(match.id) { similar.append(match.id) }
                chips.append(IntentChip(id: "similarTo:\(match.id)", field: .similarTo, label: "Как «\(match.name)»"))
            } else {
                chips.append(IntentChip(id: "similarMissing:\(RecParsing.normalized(query))", field: .similarTo, label: "Не нашёл «\(query)» на сайте"))
            }
        }

        var people = parsed.intent.people
        for query in parsed.peopleQueries {
            if let person = await engine.people(matching: query).first {
                if !people.contains(person) { people.append(person) }
                chips.append(IntentChip(id: "people:\(person.id)", field: .people, label: person.name))
            } else {
                chips.append(IntentChip(id: "peopleMissing:\(RecParsing.normalized(query))", field: .people, label: "Не нашёл «\(query)» на сайте"))
            }
        }

        parsed.intent.similarTo = similar
        parsed.intent.people = people
        if !similar.isEmpty { parsed.intent.confidence[.similarTo] = max(parsed.intent.confidence[.similarTo] ?? 0, 0.9) }
        if !people.isEmpty { parsed.intent.confidence[.people] = max(parsed.intent.confidence[.people] ?? 0, 0.8) }
        parsed.chips = chips
        return parsed
    }

    // MARK: Background

    /// Housekeeping, the background reader (signed in, «Изучение каталога» on) and a warm Home.
    func startBackground() async {
        await signals.prune()
        await enricher.start()
        Task { _ = await engine.home(force: false) }
    }

    func status() async -> RecStatus {
        let counts = await titles.counts()
        return await RecStatus(
            known: counts.known,
            pages: counts.pages,
            fetchedToday: queue.fetchedToday(),
            dailyLimit: SiteQueue.dailyLimit,
            isEnriching: enricher.isReading,
        )
    }

    // MARK: Export

    private struct Export: Encodable {
        struct Title: Encodable {
            let id: String
            let name: String
            let originalName: String?
            let year: Int?
            let kind: TitleKind?
            let kpId: Int?
            let imdbId: String?
        }

        let format = "kinopohuy-recs/1"
        let exportedAt: Date
        let ratings: [ExplicitRating]
        let feedback: [Feedback]
        let overrides: [TasteOverride]
        let sessions: [WatchSession]
        let progress: [LocalProgress]
        let accountList: [AccountListItem]
        let bookmarks: [BookmarkItem]
        let followed: [String]
        let titles: [Title]
    }

    /// Everything about taste, with each title's name, year and Kinopoisk / IMDb ids (no site paths).
    func exportJSON() async -> Data? {
        let signals = await signals.signals(signedIn: Defaults[.isLoggedIn])
        var ids = Set(signals.ratings.map(\.titleId))
        ids.formUnion(signals.feedback.map(\.titleId))
        ids.formUnion(signals.sessions.map(\.titleId))
        ids.formUnion(signals.progress.map(\.titleId))
        ids.formUnion(signals.accountList.map(\.titleId))
        ids.formUnion(signals.bookmarks.map(\.titleId))
        ids.formUnion(signals.followed)
        let known = await titles.titles(Array(ids))

        let export = Export(
            exportedAt: .now,
            ratings: signals.ratings,
            feedback: signals.feedback,
            overrides: signals.overrides,
            sessions: signals.sessions,
            progress: signals.progress,
            accountList: signals.accountList,
            bookmarks: signals.bookmarks,
            followed: signals.followed,
            titles: known.values
                .sorted { $0.id < $1.id }
                .map { Export.Title(id: $0.id, name: $0.name, originalName: $0.originalName, year: $0.year, kind: $0.kind, kpId: $0.kpId, imdbId: $0.imdbId) },
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(export)
    }
}

extension RecommenderClient {
    /// The live recommender: signals in the local database, the catalogue growing in the background, RecommenderCore
    /// doing the picking. Every closure goes to `RecRuntime.shared`, made on the first call.
    static let live = RecommenderClient(
        home: { force in await RecRuntime.shared.engine.home(force: force) },
        pick: { request in await RecRuntime.shared.engine.pick(request) },
        parse: { text in await RecRuntime.shared.parse(text) },
        contextIntent: { ContextDefaults.intent(for: EngineContext(date: .now)) },
        critique: { critique, intent, currentTitleId in
            var current: TitleFeatures?
            if let currentTitleId { current = await RecRuntime.shared.engine.title(currentTitleId) }
            return CritiqueOps.apply(critique, to: intent, current: current, context: EngineContext(date: .now))
        },
        explain: { titleId in await RecRuntime.shared.engine.explain(titleId) },
        fit: { titleId in await RecRuntime.shared.engine.fit(titleId) },
        onboardingStack: { await RecRuntime.shared.engine.onboardingStack() },
        title: { titleId in await RecRuntime.shared.engine.title(titleId) },
        rate: { titleId, level, source in
            let runtime = RecRuntime.shared
            await runtime.signals.rate(titleId, level: min(2, max(-2, level)), source: source)
            await runtime.engine.rebuildNow()
        },
        clearRating: { titleId in
            let runtime = RecRuntime.shared
            await runtime.signals.clearRating(titleId)
            await runtime.engine.rebuildNow()
        },
        rating: { titleId in await RecRuntime.shared.signals.rating(titleId) },
        feedback: { titleId, kind in
            let runtime = RecRuntime.shared
            // «Не сегодня» hides for a week; the rest last until undone.
            let until: Double? = kind == .notToday ? Date.now.timeIntervalSince1970 + Weights.default.notTodayDays * 86400 : nil
            await runtime.signals.addFeedback(titleId, kind: kind, until: until)
            await runtime.engine.rebuildNow()
        },
        removeFeedback: { titleId, kind in
            let runtime = RecRuntime.shared
            await runtime.signals.removeFeedback(titleId, kind: kind)
            await runtime.engine.rebuildNow()
        },
        activeFeedback: { titleId in await RecRuntime.shared.signals.activeFeedback(titleId) },
        override: { override in
            let runtime = RecRuntime.shared
            await runtime.signals.setOverride(override)
            await runtime.engine.rebuildNow()
        },
        clearOverride: { feature in
            let runtime = RecRuntime.shared
            await runtime.signals.clearOverride(feature)
            await runtime.engine.rebuildNow()
        },
        overrides: { await RecRuntime.shared.signals.overrides() },
        tasteBubbles: { await RecRuntime.shared.engine.tasteBubbles() },
        interestGrid: { await RecRuntime.shared.engine.interestGrid() },
        tasteConfidence: { await RecRuntime.shared.engine.tasteConfidence() },
        critics: { imdbId, kpId in
            guard let facts = await RecRuntime.shared.engine.critics(imdbId: imdbId, kpId: kpId), facts.rt != nil || facts.mc != nil else { return nil }
            return CriticScores(rottenTomatoes: facts.rt, metacritic: facts.mc)
        },
        recordImpressions: { titleIds, surface in await RecRuntime.shared.signals.recordImpressions(titleIds, surface: surface) },
        markOpened: { titleId in await RecRuntime.shared.signals.markOpened(titleId) },
        logSession: { session in
            let runtime = RecRuntime.shared
            await runtime.signals.logSession(session)
            await runtime.engine.rebuildSoon()
        },
        captureDetails: { details in
            let runtime = RecRuntime.shared
            guard await runtime.titles.upsertPage(details) != nil else { return }
            await runtime.detailsCache.store(details)
            await runtime.engine.rebuildSoon()
        },
        captureCards: { cards, board in
            let runtime = RecRuntime.shared
            guard await runtime.titles.upsertCards(cards, board: board) > 0 || board != nil else { return }
            await runtime.engine.rebuildSoon()
        },
        captureAccountList: { items in
            let runtime = RecRuntime.shared
            await runtime.titles.upsertAccountTitles(items)
            await runtime.signals.replaceAccountList(items.compactMap { TitleMapper.accountItem(from: $0) })
            await runtime.engine.rebuildSoon()
            await runtime.enricher.poke()
        },
        status: { await RecRuntime.shared.status() },
        startBackground: { await RecRuntime.shared.startBackground() },
        updates: { RecRuntime.shared.broadcaster.stream() },
        resetTaste: {
            let runtime = RecRuntime.shared
            await runtime.signals.resetTaste()
            await runtime.engine.rebuildNow()
        },
        clearAll: {
            let runtime = RecRuntime.shared
            await runtime.signals.clearAll()
            await runtime.engine.reset()
            await runtime.engine.rebuildNow()
        },
        exportJSON: { await RecRuntime.shared.exportJSON() },
        captureBookmarks: { cards, folder in
            let runtime = RecRuntime.shared
            await runtime.titles.upsertCards(cards, board: nil)
            await runtime.signals.upsertBookmarks(cards.compactMap { RecParsing.titleId(fromPath: $0.movieId) }, folder: folder)
            await runtime.engine.rebuildSoon()
        },
        captureSeriesUpdates: { groups in
            let runtime = RecRuntime.shared
            let items = groups.flatMap(\.releasedEpisodes)
            // The feed names each series by path and title: enough for a card (kind and genre come from the path).
            await runtime.titles.upsertCards(items.map { MovieSimple(movieId: $0.seriesId, name: $0.seriesName) }, board: nil)
            let followed = items.filter(\.tracked).compactMap { RecParsing.titleId(fromPath: $0.seriesId) }
            guard !followed.isEmpty else { return }
            await runtime.signals.upsertFollowed(followed)
            await runtime.engine.rebuildSoon()
        },
        playerPresence: { windowId, isOpen in await RecRuntime.shared.queue.setPlayer(windowId, isOpen: isOpen) },
    )
}
