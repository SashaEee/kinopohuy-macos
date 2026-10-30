import Foundation

/// Why a title can't be recommended (§4.7 step 1). Kept per title for the debug view.
enum FilterReason: String, Sendable, Hashable, CaseIterable {
    /// Watched: history, the site's «watched», «Уже смотрел», a rating.
    case seen
    /// Started: it belongs in «Продолжить», not in recommendations.
    case started
    case notForMe
    case hidden
    case notToday
    case dropped
    case notSeed
    case excludedKind
    case excludedGenre
    case excludedFeature
    case age
    case comingSoon
    case unavailable
}

/// The hard filters: what's watched or started, what the user ruled out, what the settings exclude, what can't be
/// watched yet. A new season of a watched series is the one exception to «watched» (S2 brings it back).
struct CandidateFilters: Sendable {
    let settings: RecommenderSettings
    let excludedGenres: Set<Int>
    let excludedFeatures: Set<Int>

    init(settings: RecommenderSettings, table: FeatureTable, profile: TasteProfile) {
        self.settings = settings
        var genres = Set<Int>()
        for genre in settings.excludedGenres {
            if let id = table.id(of: FeatureKey(.genre, genre)) { genres.insert(id) }
        }
        excludedGenres = genres
        excludedFeatures = profile.excludedFeatures
    }

    /// Why the title is filtered out, nil when it may be recommended. `allowWatched` lets a new season through.
    func reason(
        title: TitleFeatures, features: [Int], signal: TitleSignal?, allowWatched: Bool = false,
    ) -> FilterReason? {
        if let reason = settingsReason(title: title, features: features, signal: signal) { return reason }
        if !allowWatched, let state = signal?.state {
            if state == .seen { return .seen }
            if state == .started { return .started }
        }
        return nil
    }

    /// Filters that hold even for the user's own titles (a next episode in «Своё» still respects the settings).
    func settingsReason(title: TitleFeatures, features: [Int], signal: TitleSignal?) -> FilterReason? {
        if title.comingSoon { return .comingSoon }
        if !title.available { return .unavailable }
        if let exclusion = signal?.exclusion { return exclusion }
        if let kind = FeatureTable.kind(of: title), settings.excludedKinds.contains(kind) { return .excludedKind }
        if !excludedGenres.isEmpty, features.contains(where: excludedGenres.contains) { return .excludedGenre }
        if !excludedFeatures.isEmpty, features.contains(where: excludedFeatures.contains) { return .excludedFeature }
        if let maxAge = settings.maxAge, let age = title.age, age > maxAge { return .age }
        return nil
    }
}
