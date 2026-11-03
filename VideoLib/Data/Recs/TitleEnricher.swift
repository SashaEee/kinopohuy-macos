import Defaults
import Foundation
import RecommenderCore

/// Reads title pages in the background so the recommender knows more than list cards say: genres, people, ratings,
/// «Смотрите также», lists and collections. Only for a signed-in user (the site doesn't show title pages to
/// guests) with «Изучение каталога» on, within the daily limit, one page at a time through `SiteQueue`.
///
/// What comes first: the titles that make the user's taste (this Mac's history, «Досмотреть», ratings, bookmarks)
/// without a page or with an aged one; then, once a week, the pool crawl; then the engine's best candidates still
/// known only as cards; then the cards that share lists, collections, franchises and people with the user's titles.
/// Every few pages the engine is told, and it redraws Home (debounced).
actor TitleEnricher {
    struct Hooks: Sendable {
        /// The engine's best candidates (ids), whose pages are worth reading next.
        var candidates: @Sendable (_ limit: Int) async -> [String]
        /// What the weekly pool crawl looks for.
        var plan: @Sendable () async -> PoolCrawler.Plan
        /// A batch of pages came in.
        var batchDone: @Sendable () async -> Void
    }

    private struct Target: Sendable {
        var id: String
        var path: String
    }

    private enum Step {
        case page(Target)
        case crawl
    }

    private let titles: TitleStore
    private let signals: SignalStore
    private let queue: SiteQueue
    private let details: CachingMovieDetailsRepository
    private let crawler: PoolCrawler
    private let hooks: Hooks

    /// Pages read before the engine hears about them.
    static let batchSize = 10
    /// How long a page that didn't read is left alone.
    static let failureMemory: TimeInterval = 7 * TitleFreshness.day
    /// With nothing to read, how long until it looks again.
    static let idleInterval: TimeInterval = 30 * 60

    private var loop: Task<Void, Never>?
    /// Bumped by every start and stop, so an old loop still winding down never takes over a new one's state.
    private var generation = 0
    private var pending: [Target] = []
    private var pendingBuiltAt = Date.distantPast
    private var failed: [String: Double] = [:]
    private var failedLoaded = false
    private var poked = false
    /// Pages read since the engine last heard.
    private var sinceBatch = 0
    /// Reading pages right now (not idle, not waiting for tomorrow).
    private(set) var isReading = false

    init(titles: TitleStore, signals: SignalStore, queue: SiteQueue, details: CachingMovieDetailsRepository, hooks: Hooks) {
        self.titles = titles
        self.signals = signals
        self.queue = queue
        self.details = details
        self.hooks = hooks
        crawler = PoolCrawler(titles: titles, signals: signals, queue: queue)
    }

    /// Whether background reading may run now.
    static var isAllowed: Bool {
        Defaults[.isLoggedIn] && Defaults[.recCrawlEnabled] && Defaults[.recCrawlDailyLimit] > 0 && SiteAddress.isConfigured
    }

    /// Starts the loop (no-op when it runs or isn't allowed).
    func start() {
        guard loop == nil, Self.isAllowed else { return }
        generation += 1
        let generation = generation
        loop = Task { [weak self] in
            await self?.run(generation: generation)
        }
    }

    func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        isReading = false
    }

    /// Something new to read (the account's list came in): the next pick looks again, and an idle wait ends.
    func poke() {
        poked = true
        pending = []
    }

    // MARK: Loop

    /// The engine hears about the pages read since it last did.
    private func flush() async {
        guard sinceBatch > 0 else { return }
        sinceBatch = 0
        await hooks.batchDone()
    }

    /// The loop of one start; a newer start (or a stop) makes it end at its next step.
    private func run(generation: Int) async {
        await loadFailed()
        sinceBatch = 0

        reading: while !Task.isCancelled, generation == self.generation, Self.isAllowed {
            guard await queue.hasBudget() else {
                isReading = false
                await flush()
                await idle(seconds: Self.untilTomorrow(), step: 600)
                continue
            }

            guard let step = await nextStep() else {
                isReading = false
                await flush()
                await idle(seconds: Self.idleInterval, step: 5)
                continue
            }

            isReading = true
            switch step {
            case .crawl:
                pending = []
                sinceBatch += Self.batchSize
                do {
                    try await crawler.run(hooks.plan())
                } catch let failure as SiteFailure where failure == .signedOut || failure == .notConfigured || failure == .cancelled {
                    break reading
                } catch {
                    // Anything else (the day's limit, refusals) just ends this run; the loop goes on.
                }
                await flush()

            case let .page(target):
                do {
                    let page = try await details.getMovieDetails(movieId: target.path)
                    await titles.upsertPage(page)
                    sinceBatch += 1
                    if sinceBatch >= Self.batchSize { await flush() }
                } catch let failure as SiteFailure {
                    switch failure {
                    case .signedOut, .notConfigured, .cancelled:
                        break reading
                    case .unreadable:
                        await markFailed(target.id)
                    case .forbidden, .tooManyRequests, .banned, .network, .dailyLimit:
                        // The queue waits before the next read; this title stays first in line.
                        pending.insert(target, at: 0)
                    }
                } catch {
                    // Only the queue reads pages here, and it throws `SiteFailure`; anything else is a stop.
                    if Task.isCancelled { break reading }
                    await markFailed(target.id)
                }
            }
        }

        await flush()
        // A newer start owns the state from here.
        guard generation == self.generation else { return }
        isReading = false
        loop = nil
    }

    /// The next thing to read, refilling the line (at most every few minutes) in priority order.
    private func nextStep() async -> Step? {
        if !pending.isEmpty, Date().timeIntervalSince(pendingBuiltAt) < 5 * 60 {
            return .page(pending.removeFirst())
        }

        let anchors = await signals.anchorIds()
        let needAnchors = await targets(among: anchors, important: true, limit: 30)
        if !needAnchors.isEmpty { return refill(needAnchors) }

        if await crawler.isDue() { return .crawl }

        let candidates = await targets(among: hooks.candidates(60), important: true, limit: 30)
        if !candidates.isEmpty { return refill(candidates) }

        let mates = await targets(among: titles.boardMates(of: anchors, limit: 90), important: false, limit: 30)
        if !mates.isEmpty { return refill(mates) }

        pending = []
        return nil
    }

    private func refill(_ targets: [Target]) -> Step? {
        pending = targets
        pendingBuiltAt = Date()
        guard !pending.isEmpty else { return nil }
        return .page(pending.removeFirst())
    }

    /// Of these titles (in order), the ones without a page or with one aged past its lifetime, that have a path and
    /// didn't fail lately.
    private func targets(among ids: [String], important: Bool, limit: Int) async -> [Target] {
        guard !ids.isEmpty else { return [] }
        let known = await titles.titles(Array(ids.prefix(600)))
        let now = Date()
        var result: [Target] = []
        for id in ids.prefix(600) {
            guard let title = known[id], !title.path.isEmpty, !isFailed(id, now: now) else { continue }
            guard TitleFreshness.isStale(title, important: important, now: now) else { continue }
            result.append(Target(id: id, path: title.path))
            if result.count == limit { break }
        }
        return result
    }

    // MARK: Waiting

    /// Waits in short steps, ending early when poked, stopped, or no longer allowed.
    private func idle(seconds: TimeInterval, step: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        poked = false
        while Date() < deadline, !Task.isCancelled, !poked, Self.isAllowed {
            try? await Task.sleep(for: .seconds(min(step, max(1, deadline.timeIntervalSinceNow))))
            // The limit was raised in Settings: back to work.
            if await queue.hasBudget(), seconds > Self.idleInterval { break }
        }
        poked = false
    }

    /// Until a few minutes past local midnight, when the day's count starts over.
    private static func untilTomorrow(now: Date = .now, calendar: Calendar = .current) -> TimeInterval {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(TitleFreshness.day)
        return max(60, tomorrow.timeIntervalSince(now) + 5 * 60)
    }

    // MARK: Failures

    private func isFailed(_ id: String, now: Date) -> Bool {
        guard let at = failed[id] else { return false }
        return now.timeIntervalSince1970 - at < Self.failureMemory
    }

    private func markFailed(_ id: String) async {
        let now = Date().timeIntervalSince1970
        failed[id] = now
        failed = failed.filter { now - $0.value < Self.failureMemory }
        if let data = try? JSONEncoder().encode(failed) {
            await signals.setState(StateKey.failedPages, String(decoding: data, as: UTF8.self))
        }
    }

    private func loadFailed() async {
        guard !failedLoaded else { return }
        failedLoaded = true
        guard let json = await signals.state(StateKey.failedPages),
              let saved = try? JSONDecoder().decode([String: Double].self, from: Data(json.utf8))
        else { return }
        failed = saved
    }
}
