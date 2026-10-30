import Kingfisher
import SwiftUI

/// A picture from the site's CDN, filling its frame: the surface colour while it loads, a short fade in.
struct KPRemoteImage: View {
    let url: String?
    /// Shown while `url` loads (e.g. the small poster while the large one comes).
    var fallback: String? = nil
    /// Decode at this size (in pixels) instead of the file's: a 168-point card needs ~340 px, not the site's 2000.
    var downsample: CGSize? = nil
    /// The fallback's decode size. The cache keeps a picture per size, so the card's size finds the card's copy at once.
    var fallbackDownsample: CGSize? = nil
    /// Look in the caches while the view is being made, so a picture already there is in the very first frame.
    var immediate = false
    /// Nothing while it loads (a layer over another picture), instead of the surface colour.
    var clearPlaceholder = false

    var body: some View {
        KFImage
            .url(URL(string: url ?? ""))
            .setProcessor(downsample.map { DownsamplingImageProcessor(size: $0) } ?? DefaultImageProcessor.default)
            .startLoadingBeforeViewAppear(immediate)
            .loadDiskFileSynchronously(immediate)
            .placeholder {
                if clearPlaceholder {
                    Color.clear
                } else if let fallback, let fallbackURL = URL(string: fallback) {
                    KFImage.url(fallbackURL)
                        .setProcessor(fallbackDownsample.map { DownsamplingImageProcessor(size: $0) } ?? DefaultImageProcessor.default)
                        .placeholder { KP.surface }
                        .resizable()
                        .cancelOnDisappear(true)
                        .scaledToFill()
                } else {
                    KP.surface
                }
            }
            .resizable()
            .fade(duration: 0.25)
            .cancelOnDisappear(true)
            .retry(NetworkRetryStrategy())
            .scaledToFill()
    }
}
