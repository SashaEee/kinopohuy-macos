import Alamofire
import Defaults
import Foundation
import RecommenderCore

/// Why a background read didn't work out; the queue decides from it how long to wait.
enum SiteFailure: Error, Equatable, Sendable {
    /// 403: the site refused (two in a row pause the reader for half an hour).
    case forbidden
    /// 429: too many requests.
    case tooManyRequests
    /// The address is blocked (the app shows its own notice for that).
    case banned
    /// The site asks to sign in: background reading stops until the next start.
    case signedOut
    /// No site address entered yet.
    case notConfigured
    /// Offline, a timeout, a server error.
    case network
    /// The page came but didn't read (a different layout): that title is skipped for a week.
    case unreadable
    /// Today's limit of pages is used up.
    case dailyLimit
    case cancelled
}

/// The background reader's own connection to the site: a separate session (the cookies are the shared ones, so it
/// reads as the signed-in user), and an interceptor that never retries. On a 403 it doesn't switch the app's headers
/// like the main session does (`CustomInterceptor`), and no sign-in sheet or error ever shows from here; the
/// premium badge the site's pages carry is left for the pages the user opens.
final class BackgroundSite: Sendable {
    private let session: Session

    init() {
        let configuration = URLSessionConfiguration.af.default
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = 30
        session = Session(
            configuration: configuration,
            rootQueue: DispatchQueue(label: "com.kinopohuy.recs.rootQueue", qos: .utility),
            interceptor: BackgroundInterceptor(),
            redirectHandler: .modify { task, request, _ in
                var newRequest = task.originalRequest ?? task.currentRequest ?? request
                newRequest.url = request.url
                return newRequest
            },
        )
    }

    /// One page, parsed.
    func page<T: Sendable>(_ request: any URLRequestConvertible, parse: @escaping @Sendable (String) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let response = await session.request(request)
            .validate(statusCode: 200 ..< 400)
            .serializingString()
            .response

        switch response.response?.statusCode {
        case 403: throw SiteFailure.forbidden
        case 429: throw SiteFailure.tooManyRequests
        default: break
        }

        switch response.result {
        case let .success(html):
            do {
                return try Self.preservingPremium { try parse(html) }
            } catch let error as VideoLibError {
                switch error {
                case .mirrorBanned: throw SiteFailure.banned
                case .loginRequired: throw SiteFailure.signedOut
                case .siteNotConfigured: throw SiteFailure.notConfigured
                default: throw SiteFailure.unreadable
                }
            } catch {
                throw SiteFailure.unreadable
            }
        case let .failure(error):
            if error.isExplicitlyCancelledError || Task.isCancelled { throw SiteFailure.cancelled }
            if let underlying = error.underlyingError as? VideoLibError, case .siteNotConfigured = underlying { throw SiteFailure.notConfigured }
            throw SiteFailure.network
        }
    }

    /// The site's parsers note the premium days from every page they read; a background read puts back what the
    /// app showed, so only the pages the user opens change it.
    private static func preservingPremium<T>(_ parse: () throws -> T) rethrows -> T {
        let premium = Defaults[.isUserPremium]
        defer {
            if Defaults[.isUserPremium] != premium { Defaults[.isUserPremium] = premium }
        }
        return try parse()
    }
}

/// Lets nothing go to the placeholder address and never retries (the queue waits instead).
private final class BackgroundInterceptor: RequestInterceptor, Sendable {
    func adapt(_ urlRequest: URLRequest, for _: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        if SiteAddress.isPlaceholder(host: urlRequest.url?.host()) {
            completion(.failure(VideoLibError.siteNotConfigured))
        } else {
            completion(.success(urlRequest))
        }
    }

    func retry(_: Request, for _: Session, dueTo _: any Error, completion: @escaping @Sendable (RetryResult) -> Void) {
        completion(.doNotRetry)
    }
}

/// The one line to the site for everything in the background: one request at a time, at least 3 s apart (a little
/// more, at random, like a person), nothing while a player window is open, a daily limit
/// (`Defaults[.recCrawlDailyLimit]`, counted per local day and kept across launches), and waits that grow after
/// refusals: 403, 429 or a blocked address double the wait each time; two 403 in a row pause it for 30 minutes.
actor SiteQueue {
    private let site = BackgroundSite()
    private let store: SignalStore

    static let spacing: TimeInterval = 3
    static let jitter: ClosedRange<Double> = 0 ... 1.2
    static let longPause: TimeInterval = 30 * 60
    static let networkPause: TimeInterval = 2 * 60

    private var lastRequestAt: Date?
    private var playerWindows: [UUID: Date] = [:]
    private var busy = false
    private var consecutiveForbidden = 0
    private var refusals = 0
    private var pausedUntil: Date?
    private var loadedPause = false

    init(store: SignalStore) {
        self.store = store
    }

    // MARK: Player

    /// A player window opened or closed: reading waits while any is open. A window that never said it closed stops
    /// counting after 6 hours, so a lost message can't stop the reader for good.
    func setPlayer(_ windowId: UUID, isOpen: Bool, now: Date = .now) {
        if isOpen {
            playerWindows[windowId] = now
        } else {
            playerWindows[windowId] = nil
        }
    }

    func isPlayerActive(now: Date = .now) -> Bool {
        playerWindows = playerWindows.filter { now.timeIntervalSince($0.value) < Self.playerMemory }
        return !playerWindows.isEmpty
    }

    static let playerMemory: TimeInterval = 6 * 3600

    // MARK: Budget

    /// Pages read in the background today (local day).
    func fetchedToday(now: Date = .now) async -> Int {
        let day = Self.dayKey(now)
        guard await store.state(StateKey.crawlDay) == day else { return 0 }
        return await store.state(StateKey.crawlCount).flatMap(Int.init) ?? 0
    }

    static var dailyLimit: Int { max(0, Defaults[.recCrawlDailyLimit]) }

    func hasBudget(now: Date = .now) async -> Bool {
        await fetchedToday(now: now) < Self.dailyLimit
    }

    private func spendBudget(now: Date) async throws {
        let used = await fetchedToday(now: now)
        guard used < Self.dailyLimit else { throw SiteFailure.dailyLimit }
        await store.setState(StateKey.crawlDay, Self.dayKey(now), now: now)
        await store.setState(StateKey.crawlCount, String(used + 1), now: now)
    }

    /// The pause still running (also one left from before a relaunch).
    func pause(now: Date = .now) async -> Date? {
        if !loadedPause {
            loadedPause = true
            if let saved = await store.state(StateKey.pausedUntil).flatMap(Double.init) {
                let until = Date(timeIntervalSince1970: saved)
                if until > now { pausedUntil = until }
            }
        }
        guard let pausedUntil, pausedUntil > now else { return nil }
        return pausedUntil
    }

    // MARK: Reading

    /// Reads one page when its turn comes. Throws `SiteFailure`.
    func read<T: Sendable>(_ request: any URLRequestConvertible, parse: @escaping @Sendable (String) throws -> T) async throws -> T {
        // A wait cut short is a stop, never a failed page.
        do {
            while busy {
                try await Task.sleep(for: .milliseconds(200))
            }
        } catch {
            throw SiteFailure.cancelled
        }
        busy = true
        defer { busy = false }

        do {
            try await waitForTurn()
        } catch {
            throw SiteFailure.cancelled
        }
        let now = Date()
        try await spendBudget(now: now)
        lastRequestAt = now

        do {
            let result = try await site.page(request, parse: parse)
            consecutiveForbidden = 0
            refusals = 0
            return result
        } catch let failure as SiteFailure {
            await note(failure)
            throw failure
        } catch is CancellationError {
            throw SiteFailure.cancelled
        } catch {
            await note(.network)
            throw SiteFailure.network
        }
    }

    /// Waits for the spacing, a player window to close and any pause to end.
    private func waitForTurn() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            if isPlayerActive(now: now) {
                try await Task.sleep(for: .seconds(5))
                continue
            }
            if let until = await pause(now: now) {
                try await Task.sleep(for: .seconds(min(60, max(1, until.timeIntervalSince(now)))))
                continue
            }
            if let last = lastRequestAt {
                let wait = Self.spacing + Double.random(in: Self.jitter) - now.timeIntervalSince(last)
                if wait > 0 {
                    try await Task.sleep(for: .seconds(wait))
                }
            }
            // The player may have opened during the wait.
            if !isPlayerActive() { return }
        }
    }

    private func note(_ failure: SiteFailure) async {
        let now = Date()
        switch failure {
        case .forbidden:
            consecutiveForbidden += 1
            refusals += 1
            await pause(for: consecutiveForbidden >= 2 ? Self.longPause : backoff, now: now)
        case .tooManyRequests, .banned:
            consecutiveForbidden = 0
            refusals += 1
            await pause(for: backoff, now: now)
        case .network:
            await pause(for: Self.networkPause, now: now)
        case .unreadable:
            consecutiveForbidden = 0
        case .signedOut, .notConfigured, .dailyLimit, .cancelled:
            break
        }
    }

    /// 1, 2, 4, 8… minutes, at most 30.
    private var backoff: TimeInterval {
        min(Self.longPause, 60 * pow(2, Double(max(0, refusals - 1))))
    }

    private func pause(for interval: TimeInterval, now: Date) async {
        let until = now.addingTimeInterval(interval)
        guard until > (pausedUntil ?? .distantPast) else { return }
        pausedUntil = until
        await store.setState(StateKey.pausedUntil, String(until.timeIntervalSince1970), now: now)
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
