import SwiftUI

extension NSImage {
    func resized(to size: CGSize) -> NSImage {
        let image = self
        image.size = size
        return image
    }
}
