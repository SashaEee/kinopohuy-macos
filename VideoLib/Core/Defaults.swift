import AVFoundation
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let mirror = Key<URL>("mirror", default: Const.mirror)
    static let defaultQuality = Key<DefaultQuality>("default_quality", default: .highest) // ready to play in one press

    static let playerFullscreen = Key<Bool>("player_fullscreen", default: false)
    static let hideMainWindow = Key<Bool>("hide_main_window", default: false)
    static let spatialAudio = Key<SpatialAudio>("spatial_audio", default: .off)
    static let videoGravity = Key<VideoGravity>("video_gravity", default: .fit)
    static let ambientLight = Key<Bool>("ambient_light", default: false)
    static let maxConcurrentDownloads = Key<Int>("max_concurrent_downloads", default: 5)
    static let mediaControlButtonIsSeeking = Key<Bool>("media_control_button_is_seeking", default: false)
    static let rate = Key<Float>("rate", default: 1.0)
    static let volume = Key<Float>("volume", default: 1.0)
    static let isMuted = Key<Bool>("is_muted", default: false)

    static let cache = Key<Cache>("cache", default: .all)

    static let useHeaders = Key<Bool>("use_headers", default: true)
    /// The site's Android app version for its headers, refreshed from the site at launch once its address is set.
    static let siteAppVersion = Key<String>("site_app_version", default: Const.siteAppVersion)
    static let isUserPremium = Key<Int?>("is_user_premium", default: nil)
    static let isLoggedIn = Key<Bool>("is_logged_in", default: false)
    static let allowedComments = Key<Bool>("allowed_comments", default: false)

    /// Snow over the window in the last two weeks of December and the first two of January.
    static let snow = Key<Bool>("snow", default: true)
    /// The logo and name in the top bar (off: the sections start right after the traffic lights).
    static let showLogo = Key<Bool>("show_logo", default: false)
}
