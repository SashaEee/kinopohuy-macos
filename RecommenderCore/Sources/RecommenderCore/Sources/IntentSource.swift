import Foundation

/// S3: what the user meant to watch — bookmarks without progress (with the folder's name), «Досмотреть» items not
/// started yet, followed series not begun, «Хочу посмотреть» from «Уточнить вкус» (§4.5). Taste orders them within the source.
enum IntentSource {
    static func ranking(_ core: EngineCore) -> SourceRanking {
        SourceRanking(kind: .intent, hits: hits(core))
    }

    static func hits(_ core: EngineCore) -> [SourceHit] {
        var hits: [SourceHit] = []
        for signal in core.orderedSignals where signal.intent > 0 {
            guard let title = core.titleIndex[signal.titleId], core.isEligible(title), signal.state == .none else { continue }
            let evidence: Evidence
            if let folder = preferredFolder(signal.bookmarkFolders) {
                evidence = Evidence(folder: folder, origin: .bookmark)
            } else if signal.accountListNoProgress {
                evidence = Evidence(origin: .accountList)
            } else if signal.followed {
                evidence = Evidence(origin: .followed)
            } else if signal.interested {
                evidence = Evidence(origin: .interest)
            } else {
                continue
            }
            let score = signal.intent + 0.5 * max(0, core.profile.titleAffinity[title]) + 0.1 * core.quality[title]
            hits.append(SourceHit(title: title, score: score, evidence: evidence))
        }
        return hits
    }

    /// A named folder says more than a generic one: «На выходные» beats «Посмотреть позже».
    static func preferredFolder(_ folders: [String]) -> String? {
        let named = folders.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return named.first { !SignalWeighter.isLaterFolder($0) } ?? named.first
    }
}
