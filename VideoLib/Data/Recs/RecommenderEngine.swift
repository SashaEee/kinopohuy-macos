import Defaults
import Foundation
import RecommenderCore
import Synchronization

/// Tells every listener (Home, the settings' status) that the recommendations changed. Each listener gets at most
/// one pending «changed», however many came while it was busy.
final class RecBroadcaster: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { $0[id] = nil }
        }
        return stream
    }

    func send() {
        continuations.withLock { all in
            for continuation in all.values { continuation.yield() }
        }
    }
}

/// The recommender's working copy: it gathers the pool and the signals from the stores, runs RecommenderCore once
/// (`Recommender.prepare`) and keeps the prepared engine for Home, «Выбери за меня», «Почему это?» and «Вам
/// подойдёт?». Home's page is cached in `rec_cache`, so the next launch draws it at once and refreshes it behind.
///
/// When it rebuilds: right away after an explicit signal (a rating, «Скрыть», an override), about 30 s after
/// implicit ones (a session, new pages from the background reader), when the day changes, and when the cached page
/// is older than 6 hours or no longer matches the profile. The randomness is seeded by the day and a per-Mac salt,
/// so Home doesn't jump around within a day.
actor RecommenderEngine {
    private struct CachedHome: Codable {
        var output: EngineOutput
        var titles: [String: TitleFeatures]
    }

    private let titles: TitleStore
    private let signals: SignalStore
    private let broadcaster: RecBroadcaster
    /// The open data pack: critics' scores, missing IMDb ids, viewer neighbours.
    private let pack = RecsPack()

    private var prepared: PreparedEngine?
    private var snapshot: RecSnapshot?
    private var pool: [String: TitleFeatures] = [:]
    private var cacheChecked = false

    private var requested = 0
    private var completed = 0
    private var running: Task<Void, Never>?
    private var debounce: Task<Void, Never>?

    static let surface = "home"
    static let debounceSeconds: Double = 30
    static let cacheMaxAge: TimeInterval = 6 * 3600
    /// The ranked candidates kept in the snapshot and the cache (Home never shows more; the picker uses the engine).
    static let snapshotRanked = 300

    init(titles: TitleStore, signals: SignalStore, broadcaster: RecBroadcaster) {
        self.titles = titles
        self.signals = signals
        self.broadcaster = broadcaster
    }

    // MARK: Home

    /// The latest snapshot: from memory, else the cached page (refreshed behind), else built now. `force` rebuilds.
    func home(force: Bool) async -> RecSnapshot? {
        if force {
            await refresh()
            return snapshot
        }

        if snapshot == nil, !cacheChecked {
            cacheChecked = true
            if let cached = await loadCache() {
                snapshot = cached.snapshot
                Task { await self.revalidate(profileHash: cached.profileHash, builtAt: cached.snapshot.builtAt) }
                return snapshot
            }
        }

        if let snapshot {
            if !Calendar.current.isDateInToday(snapshot.builtAt) { rebuildNow() }
            return snapshot
        }

        await refresh()
        return snapshot
    }

    /// The prepared engine, built now if there's none yet.
    func ensurePrepared() async -> PreparedEngine? {
        if prepared == nil { await refresh() }
        return prepared
    }

    func pick(_ request: PickRequest) async -> PickResult {
        guard let prepared = await ensurePrepared() else {
            return PickResult(main: nil, alternatives: [], showGrid: false, relaxed: [], question: nil, suggestRefine: false, effectiveIntent: request.intent)
        }
        return prepared.pick(request)
    }

    func explain(_ titleId: String) async -> Explanation? {
        await ensurePrepared()?.explain(titleId)
    }

    func fit(_ titleId: String) async -> FitVerdict? {
        await ensurePrepared()?.fit(titleId)
    }

    func onboardingStack(count: Int = 12) async -> [TitleFeatures] {
        guard let prepared = await ensurePrepared() else { return [] }
        let ids = prepared.onboardingStack(count: count)
        let missing = ids.filter { pool[$0] == nil }
        let stored = missing.isEmpty ? [:] : await titles.titles(missing)
        return ids.compactMap { pool[$0] ?? stored[$0] }
    }

    /// «Что вам близко»: the bubbles of «Уточнить вкус».
    func tasteBubbles() async -> [FeatureAffinity] {
        await ensurePrepared()?.tasteBubbles() ?? []
    }

    /// «Что хочется посмотреть?» in «Уточнить вкус».
    func interestGrid() async -> [TitleFeatures] {
        guard let prepared = await ensurePrepared() else { return [] }
        let ids = prepared.interestGrid()
        let missing = ids.filter { pool[$0] == nil }
        let stored = missing.isEmpty ? [:] : await titles.titles(missing)
        return ids.compactMap { pool[$0] ?? stored[$0] }
    }

    /// Films the viewers of the user's titles liked that the pool lacks: what the background reader looks for on the
    /// site next.
    func viewerSuggestions(limit: Int) async -> [RecsPack.Suggestion] {
        guard let prepared = await ensurePrepared(), await pack.isAvailable else { return [] }
        let looked = Set(await titles.packLookups().keys)
        return await pack.suggestions(seeds: prepared.tasteSeeds(), excluding: looked, limit: limit)
    }

    /// «Вкус изучен на N %».
    func tasteConfidence() async -> Double {
        await ensurePrepared()?.tasteConfidence() ?? 0
    }

    /// A title from the working pool, else from the catalogue.
    func title(_ titleId: String) async -> TitleFeatures? {
        if let title = pool[titleId] { return title }
        return await titles.title(titleId)
    }

    /// The best candidates known only as cards, for the background reader.
    func cardCandidates(limit: Int) -> [String] {
        let ranked = prepared?.output.ranked ?? snapshot?.output.ranked ?? []
        var ids: [String] = []
        for recommendation in ranked where pool[recommendation.titleId]?.level != .page {
            ids.append(recommendation.titleId)
            if ids.count == limit { break }
        }
        return ids
    }

    /// What the weekly pool crawl looks for: the profile's top genres and people (or, before there's a profile,
    /// the ones most common among the user's own titles).
    func crawlPlan(anchors: [String]) async -> PoolCrawler.Plan {
        let settings = RecommenderSettings.current
        let profile = prepared?.output.profile ?? snapshot?.output.profile ?? .empty
        var genres: [String] = []
        var people: [PersonRef] = []
        for feature in profile.top where feature.affinity > 0 {
            switch feature.feature.group {
            case .genre:
                for name in [feature.feature.value, feature.name] where !name.isEmpty && !genres.contains(name) { genres.append(name) }
            case .director, .actor:
                if !people.contains(where: { $0.id == feature.feature.value }) {
                    people.append(PersonRef(id: feature.feature.value, name: feature.name))
                }
            default:
                break
            }
        }

        if genres.isEmpty || people.isEmpty {
            let known = pool.isEmpty ? await titles.titles(Array(anchors.prefix(200))) : pool
            var genreCounts: [String: Double] = [:]
            var personCounts: [PersonRef: Double] = [:]
            for (index, id) in anchors.prefix(200).enumerated() {
                guard let title = known[id] else { continue }
                let weight = 1 / (1 + Double(index) / 50)
                for genre in title.genres { genreCounts[genre, default: 0] += weight }
                for person in title.directors { personCounts[person, default: 0] += weight }
            }
            if genres.isEmpty {
                genres = genreCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(PoolCrawler.topGenres).map(\.key)
            }
            if people.isEmpty {
                people = personCounts.filter { $0.value >= 1.5 }
                    .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.id < $1.key.id }
                    .prefix(PoolCrawler.people)
                    .map(\.key)
            }
        }
        return PoolCrawler.Plan(topGenres: genres, people: people, anchors: anchors, excludedKinds: settings.excludedKinds)
    }

    /// People in the pool whose name matches what the user typed («Нолан», «с Ди Каприо», «Нолана»): the one with
    /// the most titles first, directors ahead of actors.
    func people(matching query: String, limit: Int = 1) async -> [PersonRef] {
        if pool.isEmpty { _ = await ensurePrepared() }
        let words = RecParsing.normalized(query)
            .split(separator: " ")
            .map(String.init)
            .filter { !Self.personStopWords.contains($0) }
            .map(RecParsing.stem)
        guard !words.isEmpty, words.contains(where: { $0.count >= 3 }) else { return [] }

        var scores: [String: (person: PersonRef, score: Double)] = [:]
        var verdicts: [String: Bool] = [:]
        for title in pool.values {
            let credited = title.directors.map { ($0, 2.0) } + title.actors.prefix(5).map { ($0, 1.0) }
            for (person, weight) in credited {
                let matches: Bool
                if let known = verdicts[person.name] {
                    matches = known
                } else {
                    matches = Self.nameMatches(person.name, words: words)
                    verdicts[person.name] = matches
                }
                guard matches else { continue }
                scores[person.id] = (person, (scores[person.id]?.score ?? 0) + weight)
            }
        }
        return scores.values
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.person.id < $1.person.id }
            .prefix(limit)
            .map(\.person)
    }

    private static let personStopWords: Set<String> = ["с", "со", "от", "и", "режиссер", "режиссера", "актер", "актера", "актриса", "актрисой", "фильм", "фильмы", "кино"]

    /// Every typed word starts a word of the name (or, long enough, sits inside the name written together).
    static func nameMatches(_ name: String, words: [String]) -> Bool {
        let nameWords = RecParsing.normalized(name).split(separator: " ").map(String.init)
        guard !nameWords.isEmpty else { return false }
        let joined = nameWords.joined()
        return words.allSatisfy { word in
            nameWords.contains { $0.hasPrefix(word) || ($0.count >= 4 && word.hasPrefix(RecParsing.stem($0))) }
                || (word.count >= 5 && joined.contains(word))
        }
    }

    // MARK: Rebuilding

    /// Rebuilds in the background now (an explicit signal).
    func rebuildNow() {
        Task { await self.refresh() }
    }

    /// Rebuilds in about 30 s (implicit signals, new pages); more of them meanwhile don't push it further away.
    func rebuildSoon() {
        guard debounce == nil else { return }
        debounce = Task {
            try? await Task.sleep(for: .seconds(Self.debounceSeconds))
            await self.firePending()
        }
    }

    private func firePending() async {
        debounce = nil
        await refresh()
    }

    /// Brings the snapshot up to date with everything asked so far; concurrent calls share one build (and one more
    /// if something came in while it ran).
    func refresh() async {
        requested += 1
        let wanted = requested
        while completed < wanted {
            if let running {
                await running.value
                continue
            }
            let target = requested
            let task = Task {
                await self.build()
                self.completed = max(self.completed, target)
                self.running = nil
            }
            running = task
            await task.value
        }
    }

    private func build() async {
        let now = Date()
        let settings = RecommenderSettings.current
        async let poolTitles = titles.pool(now: now)
        async let userSignals = signals.signals(signedIn: Defaults[.isLoggedIn], now: now)
        let salt = await profileSalt()
        let (stored, signalsNow) = await (poolTitles, userSignals)
        await pack.remember(titles.packLookups().compactMapValues { $0 }.reduce(into: [:]) { $0[$1.value] = $1.key })
        let (titlesList, viewerNeighbours) = await pack.enrich(stored)

        let input = EngineInput(
            context: EngineContext(date: now),
            titles: titlesList,
            signals: signalsNow,
            settings: settings,
            weights: .default,
            seed: Self.seed(day: now, salt: salt),
            viewerNeighbours: viewerNeighbours,
        )
        #if DEBUG
            // KP_REC_DUMP=1: the engine's whole input as JSON (rec-input.json in the app's temporary folder, the one place
            // the sandbox lets it write), for RecEval's offline check on real history.
            if ProcessInfo.processInfo.environment["KP_REC_DUMP"] != nil, let data = try? JSONEncoder().encode(input) {
                try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "rec-input.json"))
            }
        #endif
        let start = Date()
        let prepared = await Task.detached(priority: .utility) { Recommender.prepare(input) }.value
        #if DEBUG
            print("Recommender: \(titlesList.count) titles, \(prepared.output.ranked.count) ranked, \(prepared.output.page.rows.count) rows in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        #endif

        self.prepared = prepared
        pool = Dictionary(titlesList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshot = RecSnapshot(output: prepared.output, titles: referencedTitles(prepared.output), builtAt: now)
        self.snapshot = snapshot
        await writeCache(snapshot, profileHash: Self.profileHash(signalsNow, settings))
        broadcaster.send()
    }

    /// The titles a page refers to (hero, rows, the first ranked ones), so views never look anything up.
    private func referencedTitles(_ output: EngineOutput) -> [String: TitleFeatures] {
        var ids: [String] = []
        if let hero = output.page.hero { ids += [hero.main.titleId] + hero.alternatives.map(\.titleId) }
        for row in output.page.rows { ids += row.items.map(\.titleId) }
        ids += output.ranked.prefix(Self.snapshotRanked).map(\.titleId)
        var result: [String: TitleFeatures] = [:]
        for id in ids where result[id] == nil {
            if let title = pool[id] { result[id] = title }
        }
        return result
    }

    // MARK: Cache

    private func loadCache() async -> (snapshot: RecSnapshot, profileHash: String)? {
        guard let cached = await signals.readCache(Self.surface),
              let home = try? JSONDecoder().decode(CachedHome.self, from: cached.payload)
        else { return nil }
        let snapshot = RecSnapshot(output: home.output, titles: home.titles, builtAt: Date(timeIntervalSince1970: cached.builtAt))
        return (snapshot, cached.profileHash)
    }

    /// After drawing the cached page: rebuild when it's from another day, older than 6 hours, or the profile moved.
    private func revalidate(profileHash: String, builtAt: Date) async {
        let now = Date()
        if !Calendar.current.isDate(builtAt, inSameDayAs: now) || now.timeIntervalSince(builtAt) > Self.cacheMaxAge {
            await refresh()
            return
        }
        let current = await Self.profileHash(signals.signals(signedIn: Defaults[.isLoggedIn], now: now), RecommenderSettings.current)
        if current != profileHash { await refresh() }
    }

    private func writeCache(_ snapshot: RecSnapshot, profileHash: String) async {
        var output = snapshot.output
        output.ranked = Array(output.ranked.prefix(Self.snapshotRanked))
        guard let data = try? JSONEncoder().encode(CachedHome(output: output, titles: snapshot.titles)) else { return }
        await signals.writeCache(Self.surface, .init(payload: data, profileHash: profileHash, builtAt: snapshot.builtAt.timeIntervalSince1970))
    }

    /// The signals and settings in one hash (impressions left out: they change with every redraw).
    static func profileHash(_ signals: UserSignals, _ settings: RecommenderSettings) -> String {
        var signals = signals
        signals.impressions = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(signals)) ?? Data()
        data.append((try? encoder.encode(settings)) ?? Data())
        data.append(Data("engine \(Recommender.version)".utf8))
        return String(RecParsing.fnv1a(data), radix: 16)
    }

    /// The day (local) and the Mac's salt.
    static func seed(day: Date, salt: String) -> UInt64 {
        RecParsing.fnv1a("\(SiteQueue.dayKey(day))|\(salt)")
    }

    private func profileSalt() async -> String {
        if let salt = await signals.state(StateKey.profileSalt), !salt.isEmpty { return salt }
        let salt = UUID().uuidString
        await signals.setState(StateKey.profileSalt, salt)
        return salt
    }

    /// Forgets the working copy (after «Очистить все данные»): the next call builds afresh.
    func reset() {
        prepared = nil
        snapshot = nil
        cacheChecked = true
    }
}
