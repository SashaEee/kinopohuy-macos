import ComposableArchitecture
import Defaults
import SwiftUI

/// Under a title's banner: the voice-overs, and for a series its seasons and episodes, chosen right on the page.
/// An episode's tile starts it at once (its stream is fetched as soon as it's chosen).
struct WatchOptionsView: View {
    @Bindable var store: StoreOf<MovieSelectionFeature>
    /// The page's own list, shown (not yet choosable) until the selection has loaded where you left off, so the row
    /// is there from the start instead of pushing the page down a moment later.
    var pageActings: [MovieVoiceActing] = []
    /// Likewise: the episodes' place is kept from the start for a series.
    var pageIsSeries = false
    /// The site's «рейтинг озвучек»: each voice-over's share of the viewers, shown on its pill.
    var popularity: [MovieVoiceActingRating] = []
    /// Starts the episode (nil: whatever is chosen) as soon as its stream is in.
    let play: (MovieEpisode?) -> Void

    @Default(.isUserPremium) private var isUserPremium
    @Environment(\.kpMetrics) private var metrics

    private var ready: Bool { store.details != nil }
    /// Still loading (not failed): only then do the page's stand-ins show.
    private var loading: Bool { store.details == nil && store.error == nil }
    private var actings: [MovieVoiceActing] {
        (store.details?.voiceActing ?? (loading ? pageActings : [])).filter { !KPDemo.hides($0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.compact ? 12 : 14) {
            if actings.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Озвучка")
                        .font(KP.font(12, .semibold))
                        .foregroundStyle(KP.fg38)
                        .padding(.horizontal, KP.gutter)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(actings) { acting in
                                KPPill(
                                    title: acting.name,
                                    detail: detail(for: acting),
                                    selected: acting == store.selectedActing,
                                    dimmed: acting.isPremium && isUserPremium == nil
                                ) {
                                    if acting != store.selectedActing {
                                        store.selectedActing = acting
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, KP.gutter)
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.never)
                    .allowsHitTesting(ready)
                    .animation(.smooth(duration: 0.3), value: store.selectedActing)
                }
            }

            if store.details.map({ $0.series != nil }) ?? (loading && pageIsSeries) {
                let schedule = EpisodeSchedule(store.details?.schedule)

                if let seasons = store.seasons, seasons.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(seasons) { season in
                                KPPill(title: season.name.first?.isNumber == true ? "\(season.name) сезон" : season.name, selected: season == store.selectedSeason) {
                                    if season != store.selectedSeason {
                                        withAnimation(.snappy) { store.selectedSeason = season }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, KP.gutter)
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.never)
                }

                // «Новая серия 26 ноября · 1 сезон 8 серия»: what's coming next, from the site's schedule (with the
                // season's episodes, so one already out here isn't announced, and it comes in with the tiles).
                if let season = store.selectedSeason, let next = schedule.nextRelease(season: season) {
                    Label {
                        Text(verbatim: next)
                    } icon: {
                        Image(systemName: "calendar").foregroundStyle(KP.sun)
                    }
                    .font(KP.font(12.5, .semibold))
                    .foregroundStyle(KP.fg70)
                    .padding(.horizontal, KP.gutter)
                }

                if let season = store.selectedSeason, !season.episodes.isEmpty {
                    let slots = season.episodes.map(EpisodeSlot.released) + schedule.announced(after: season).map(EpisodeSlot.announced)
                    // Opens at the episode you're on (one before it shows too), not at the season's first.
                    let currentIndex = slots.firstIndex { if case let .released(episode) = $0 { episode == store.selectedEpisode } else { false } }
                    KPRow(title: "", items: slots, itemWidth: metrics.episodeTile.width, spacing: 12, captioned: false, startAt: currentIndex.map { slots[max(0, $0 - 1)].id }) { slot in
                        switch slot {
                        case let .released(episode):
                            EpisodeTile(
                                episode: episode,
                                entry: schedule.entry(season: season.seasonId, episode: episode.episodeId),
                                current: episode == store.selectedEpisode,
                                loading: episode == store.selectedEpisode && store.movie == nil,
                                watched: store.state.isWatched(season, episode),
                                progress: store.state.progress(season, episode)
                            ) {
                                play(episode)
                            }
                        case let .announced(entry):
                            AnnouncedEpisodeTile(entry: entry)
                        }
                    }
                    .id(season.id)
                    .transition(.opacity)
                } else {
                    HStack(spacing: 12) {
                        ForEach(0 ..< 6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(KP.surface)
                                .frame(width: metrics.episodeTile.width, height: metrics.episodeTile.height)
                        }
                    }
                    .padding(.horizontal, KP.gutter)
                }
            }
        }
    }
}

/// A place in the episodes' row: one that's out, or one the schedule announces.
private enum EpisodeSlot: Identifiable {
    case released(MovieEpisode)
    case announced(EpisodeSchedule.Entry)

    var id: String {
        switch self {
        case let .released(episode): "e-\(episode.id)"
        case let .announced(entry): "a-\(entry.season)-\(entry.episode)"
        }
    }
}

extension WatchOptionsView {
    /// «42%», and what the site marks on it: «с рекламой», «CAMRip», «реж. версия», «премиум» (without premium).
    func detail(for acting: MovieVoiceActing) -> String? {
        var parts: [String] = []
        if let percent = popularity.first(where: { $0.name == acting.name })?.percent {
            parts.append(percent < 1 ? "<1%" : "\(Int(percent.rounded()))%")
        }
        if acting.isAds == "1" { parts.append("с рекламой") }
        if acting.isCamrip == "1" { parts.append("CAMRip") }
        if acting.isDirector == "1" { parts.append("реж. версия") }
        if acting.isPremium, isUserPremium == nil { parts.append("премиум") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// An episode: its number large, its name from the schedule (or «серия») under it; the chosen one (where you are)
/// lit, the watched ones dimmed with a tick, a thin bar for how far you got, a play mark under the pointer.
private struct EpisodeTile: View {
    let episode: MovieEpisode
    let entry: EpisodeSchedule.Entry?
    let current: Bool
    let loading: Bool
    let watched: Bool
    let progress: Double?
    let action: () -> Void

    @State private var hover = false
    @Environment(\.kpMetrics) private var metrics

    private var isNumber: Bool { episode.name.first?.isNumber == true }

    /// «5 серия · «Пилот» · 12 октября», for the tooltip.
    private var fullTitle: String {
        var parts = [isNumber ? "\(episode.name) серия" : episode.name]
        if let name = entry?.name { parts.append("«\(name)»") }
        if let date = entry?.date, !date.isEmpty { parts.append(EpisodeSchedule.withoutYear(date)) }
        if watched { parts.append("просмотрена") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let size = metrics.episodeTile
        let inset: CGFloat = metrics.compact ? 10 : 12
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(current ? KP.surfaceHigh : KP.surface)
                    .overlay {
                        LinearGradient(colors: [Color.white.opacity(current ? 0.07 : 0.03), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .overlay(alignment: .bottom) {
                        if let progress {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.14))
                                    Rectangle().fill(KP.sunGradient)
                                        .frame(width: max(4, proxy.size.width * progress))
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: isNumber ? episode.name : "")
                        .font(KP.font(metrics.episodeNumber, .heavy))
                        .foregroundStyle(current ? KP.fg : watched ? KP.fg38 : KP.fg70)
                        .tracking(-1)
                    Text(verbatim: isNumber ? entry?.name ?? "серия" : episode.name)
                        .font(KP.font(metrics.compact ? 12 : 12.5, .semibold))
                        .foregroundStyle(watched && !current ? KP.fg38 : KP.fg55)
                        .lineLimit(isNumber ? 1 : 2)
                }
                .padding(inset)

                Group {
                    if current {
                        Capsule()
                            .fill(KP.sunGradient)
                            .frame(width: 32, height: 4)
                            .padding(.top, 2)
                    } else if watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KP.fg55)
                    }
                }
                .padding(inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                Group {
                    if loading, hover {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.compact ? 12 : 13, weight: .bold))
                            .foregroundStyle(KP.ink)
                            .offset(x: 1)
                    }
                }
                .frame(width: metrics.compact ? 28 : 30, height: metrics.compact ? 28 : 30)
                .background(Circle().fill(KP.fg))
                .padding(inset - 2)
                .padding(.bottom, progress == nil ? 0 : 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .opacity(hover ? 1 : 0)
                .scaleEffect(hover ? 1 : 0.7)
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(KP.fg, lineWidth: 3)
                    .padding(-5)
                    .opacity(hover ? 1 : 0)
            }
            .scaleEffect(hover ? 1.04 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hover)
        .help(fullTitle)
        .accessibilityLabel(fullTitle)
    }
}

/// An episode the schedule announces but that isn't out yet: dim and outlined, its number and date, not playable.
private struct AnnouncedEpisodeTile: View {
    let entry: EpisodeSchedule.Entry

    @Environment(\.kpMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "\(entry.episode)")
                .font(KP.font(metrics.episodeNumber, .heavy))
                .tracking(-1)
                .foregroundStyle(KP.fg.opacity(0.22))
            Text(verbatim: entry.date.isEmpty ? "скоро" : EpisodeSchedule.withoutYear(entry.date))
                .font(KP.font(metrics.compact ? 12 : 12.5, .semibold))
                .foregroundStyle(KP.fg38)
                .lineLimit(1)
        }
        .padding(metrics.compact ? 10 : 12)
        .frame(width: metrics.episodeTile.width, height: metrics.episodeTile.height, alignment: .bottomLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KP.fg.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .help(tooltip)
    }

    /// «8 серия · «Название» · выйдет 26 ноября 2025»; once its day has come, that this voice-over doesn't have it yet.
    private var tooltip: String {
        var parts = ["\(entry.episode) серия"]
        if let name = entry.name { parts.append("«\(name)»") }
        if !entry.date.isEmpty {
            parts.append(EpisodeSchedule.hasAired(entry) ? "вышла \(entry.date), в этой озвучке ещё нет" : "выйдет \(entry.date)")
        }
        return parts.joined(separator: " · ")
    }
}
