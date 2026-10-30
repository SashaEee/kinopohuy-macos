import Foundation

struct PlayerData: Identifiable, Codable, Hashable {
    let details: MovieDetailed
    let selectedActing: MovieVoiceActing
    let seasons: [MovieSeason]?
    let selectedSeason: MovieSeason?
    let selectedEpisode: MovieEpisode?
    let selectedQuality: String
    let movie: MovieVideo
    /// «С начала»: plays from 0 instead of where this episode or film was left.
    let startOver: Bool
    let id: UUID

    init(details: MovieDetailed, selectedActing: MovieVoiceActing, seasons: [MovieSeason]?, selectedSeason: MovieSeason?, selectedEpisode: MovieEpisode?, selectedQuality: String, movie: MovieVideo, startOver: Bool = false, id: UUID = .init()) {
        self.details = details
        self.selectedActing = selectedActing
        self.seasons = seasons
        self.selectedSeason = selectedSeason
        self.selectedEpisode = selectedEpisode
        self.selectedQuality = selectedQuality
        self.movie = movie
        self.startOver = startOver
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case details, selectedActing, seasons, selectedSeason, selectedEpisode, selectedQuality, movie, startOver, id
    }

    /// A player window restored from before `startOver` existed still opens (it resumes, as it did then).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        details = try container.decode(MovieDetailed.self, forKey: .details)
        selectedActing = try container.decode(MovieVoiceActing.self, forKey: .selectedActing)
        seasons = try container.decodeIfPresent([MovieSeason].self, forKey: .seasons)
        selectedSeason = try container.decodeIfPresent(MovieSeason.self, forKey: .selectedSeason)
        selectedEpisode = try container.decodeIfPresent(MovieEpisode.self, forKey: .selectedEpisode)
        selectedQuality = try container.decode(String.self, forKey: .selectedQuality)
        movie = try container.decode(MovieVideo.self, forKey: .movie)
        startOver = try container.decodeIfPresent(Bool.self, forKey: .startOver) ?? false
        id = try container.decode(UUID.self, forKey: .id)
    }
}
