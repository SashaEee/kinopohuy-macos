// Draws the README's pictures in the app's colours, with the sun from its icon, into docs/media/:
//   wordmark-dark.png   the sun and «КиноПохуй» in light letters, for GitHub's dark theme (transparent)
//   wordmark-light.png  the same in dark letters, for the light theme (transparent)
//   social-preview.png  1280×640, for the repository's Settings → Social preview (Telegram and VK show it on every link)
//   qr-usdt-ton.png     the donation wallet from VideoLib/Core/AppLinks.swift as a QR code
//   screen-*.jpg        window captures set on the app's black with the sun's glow (only when a captures folder is given)
// Nothing is downloaded: the sun and the Inter font come from VideoLib/Resources.
//
// Usage (from anywhere): DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/readme/make-media.swift [captures]
//
// The captures folder holds window shots without a shadow (`screencapture -o -l<window id>`) of a Debug build run with
// KP_DEMO=1 (screenshot mode, see KPDemo.swift): home.png, title.png, pause.png, player.png, and for the
// recommendations rows.png (KP_SCROLL), pick.png (KP_PICK), taste.png and deck.png (KP_TASTE, KP_TASTE=stack) and
// fit.png (KP_OPEN, KP_SCROLL). A sheet is a window of its own: those three are the main window's place on screen
// (`screencapture -R`) with the app in front. They stay out of the repository; only the framed JPEGs are committed.

import AppKit
import CoreImage.CIFilterBuiltins
import CoreText

let here = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
let root = here.deletingLastPathComponent().deletingLastPathComponent()
let sunURL = root.appending(path: "VideoLib/Resources/KinoPohuy.icon/Assets/sun.png")
let fontURL = root.appending(path: "VideoLib/Resources/Fonts/InterVariable.ttf")
let out = root.appending(path: "docs/media")

// KP palette (VideoLib/Presentations/Theme/KP.swift) and the icon's own background.
let bg = CGColor(srgbRed: 11 / 255, green: 11 / 255, blue: 13 / 255, alpha: 1)
let warmDark = CGColor(srgbRed: 0.102, green: 0.078, blue: 0.063, alpha: 1)
let fg = NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
let ink = NSColor(srgbRed: 17 / 255, green: 17 / 255, blue: 19 / 255, alpha: 1)
let sunOrange = CGColor(srgbRed: 1, green: 0.42, blue: 0, alpha: 1)

let sun = NSImage(contentsOf: sunURL)

/// The sun without its soft orange glow: on a white page the glow reads as a beige smudge. Pixels under 45 % opacity
/// go, the rest keep their edge.
let sunWithoutGlow: NSImage? = {
    guard let source = sun?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let width = source.width
    let height = source.height
    // Premultiplied RGBA: scaling a pixel's four bytes by the same factor changes only its opacity.
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self)
    else { return nil }
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    for i in stride(from: 0, to: width * height * 4, by: 4) {
        let alpha = Double(pixels[i + 3]) / 255
        guard alpha > 0 else { continue }
        let kept = max(0, min(1, (alpha - 0.45) / 0.55))
        let factor = kept / alpha
        for c in 0 ..< 4 {
            pixels[i + c] = UInt8(min(255, (Double(pixels[i + c]) * factor).rounded()))
        }
    }

    guard let cleaned = ctx.makeImage() else { return nil }
    return NSImage(cgImage: cleaned, size: NSSize(width: width, height: height))
}()

/// Inter at a given weight (the bundled file is variable: weight is its 'wght' axis).
func inter(_ size: CGFloat, weight: CGFloat) -> NSFont {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
          let base = descriptors.first
    else {
        return NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .bold : .medium)
    }

    let wght = 0x7767_6874 // 'wght'
    let descriptor = CTFontDescriptorCreateCopyWithVariation(base, wght as CFNumber, weight)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
}

/// A canvas in points, origin at the top left, drawn at `scale` pixels per point.
func canvas(width: CGFloat, height: CGFloat, scale: CGFloat, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: width, height: height)
    return rep
}

/// The sun and the name side by side, the pair's left edge at x, centred on y. Returns its width.
@discardableResult
func drawWordmark(x: CGFloat, centerY: CGFloat, sunSize: CGFloat, fontSize: CGFloat, color: NSColor, glow: Bool = true, measureOnly: Bool = false) -> CGFloat {
    let title = text("КиноПохуй", inter(fontSize, weight: 700), color, kern: -fontSize * 0.015)
    let gap = sunSize * 0.22
    let width = sunSize + gap + title.size().width
    guard !measureOnly else { return width }

    (glow ? sun : sunWithoutGlow)?.draw(in: CGRect(x: x, y: centerY - sunSize / 2, width: sunSize, height: sunSize), from: .zero,
              operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    let size = title.size()
    title.draw(at: CGPoint(x: (x + sunSize + gap).rounded(), y: (centerY - size.height / 2).rounded()))
    return width
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// The README's header: 560×128 pt at 2x, shown at 440 pt wide.
for (name, color, glow) in [("wordmark-dark.png", fg, true), ("wordmark-light.png", ink, false)] {
    let width: CGFloat = 560
    let height: CGFloat = 128
    let rep = canvas(width: width, height: height, scale: 2) { _ in
        let markWidth = drawWordmark(x: 0, centerY: 0, sunSize: 104, fontSize: 70, color: color, measureOnly: true)
        drawWordmark(x: ((width - markWidth) / 2).rounded(), centerY: height / 2, sunSize: 104, fontSize: 70, color: color, glow: glow)
    }
    write(rep, name)
}

// The social preview: 1280×640 px (GitHub's size), the app's black with the icon's warm glow.
let preview = canvas(width: 1280, height: 640, scale: 1) { ctx in
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let base = CGGradient(colorsSpace: space, colors: [warmDark, bg] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 1280, y: 640), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    let glowCenter = CGPoint(x: 330, y: 300)
    let glow = CGGradient(colorsSpace: space, colors: [sunOrange.copy(alpha: 0.22)!, sunOrange.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 520, options: [])

    let left: CGFloat = 120
    drawWordmark(x: left, centerY: 250, sunSize: 150, fontSize: 104, color: fg)

    let tagline = text("Кино на Mac. Без лишнего.", inter(46, weight: 600), fg.withAlphaComponent(0.92), kern: -0.5)
    tagline.draw(at: CGPoint(x: left, y: 362))

    let details = text("Нативный клиент для macOS · SwiftUI · открытый код", inter(28, weight: 500), fg.withAlphaComponent(0.55))
    details.draw(at: CGPoint(x: left, y: 430))

    // Two quiet chips at the bottom: what it runs on.
    var chipX = left
    for label in ["macOS 15+", "Apple Silicon и Intel"] {
        let chip = text(label, inter(22, weight: 600), fg.withAlphaComponent(0.8))
        let size = chip.size()
        let rect = CGRect(x: chipX, y: 512, width: size.width + 36, height: 46)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 23, cornerHeight: 23, transform: nil))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.1))
        ctx.fillPath()
        chip.draw(at: CGPoint(x: rect.minX + 18, y: (rect.midY - size.height / 2).rounded()))
        chipX = rect.maxX + 14
    }
}
write(preview, "social-preview.png")

// The wallet's QR code, black on white with a quiet margin, for a phone's camera. The address is read from AppLinks, so
// the picture can't drift from what the app shows.
let appLinks = try String(contentsOf: root.appending(path: "VideoLib/Core/AppLinks.swift"), encoding: .utf8)
if let match = appLinks.firstMatch(of: #/cryptoUSDT = "([^"]+)"/#) {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(String(match.1).utf8)
    filter.correctionLevel = "M"
    let code = filter.outputImage!
    let module: CGFloat = 12
    let margin = module * 3
    let side = code.extent.width * module + margin * 2
    let pixels = CIContext().createCGImage(code, from: code.extent)!
    let qr = canvas(width: side, height: side, scale: 1) { ctx in
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerWidth: 28, cornerHeight: 28, transform: nil))
        ctx.setFillColor(.white)
        ctx.fillPath()
        ctx.interpolationQuality = .none
        ctx.draw(pixels, in: CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2))
    }
    write(qr, "qr-usdt-ton.png")
}

// The screenshots: each capture centred on a 2400×1480 board in the app's black, a soft shadow under the window and
// the sun's warm glow from the top left, as on the social preview. JPEG, so they stay under a megabyte each.
if CommandLine.arguments.count > 1 {
    let captures = URL(fileURLWithPath: CommandLine.arguments[1])
    let shots = [
        "home": "screen-home.jpg", "title": "screen-title.jpg", "pause": "screen-pause.jpg", "player": "screen-player.jpg",
        "rows": "screen-rows.jpg", "pick": "screen-pick.jpg", "taste": "screen-taste.jpg", "deck": "screen-deck.jpg",
        "fit": "screen-fit.jpg",
    ]

    for (source, name) in shots.sorted(by: { $0.key < $1.key }) {
        guard let image = NSImage(contentsOf: captures.appending(path: "\(source).png")),
              let window = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            print("skipped \(source).png: not in \(captures.path)")
            continue
        }

        let width: CGFloat = 2400
        let height: CGFloat = 1480
        let board = canvas(width: width, height: height, scale: 1) { ctx in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let base = CGGradient(colorsSpace: space, colors: [warmDark, bg] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: width, y: height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

            let glowCenter = CGPoint(x: 360, y: 240)
            let glow = CGGradient(colorsSpace: space, colors: [sunOrange.copy(alpha: 0.26)!, sunOrange.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 1100, options: [])

            // Fit the window into 2160×1300, keeping its proportions.
            let fit = min(2160 / CGFloat(window.width), 1300 / CGFloat(window.height))
            let size = CGSize(width: CGFloat(window.width) * fit, height: CGFloat(window.height) * fit)
            let frame = CGRect(x: ((width - size.width) / 2).rounded(), y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)

            // Rounded like the window: a capture of its place on screen (a sheet over it) leaves no desktop in the corners.
            let corner = 32 * fit
            let rounded = CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 28), blur: 90, color: CGColor(gray: 0, alpha: 0.75))
            ctx.addPath(rounded)
            ctx.setFillColor(bg)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(rounded)
            ctx.clip()
            // The context is flipped for text; an image drawn as is would come out upside down.
            ctx.translateBy(x: frame.minX, y: frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(window, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
        try! board.representation(using: .jpeg, properties: [.compressionFactor: 0.86])!.write(to: out.appending(path: name))
    }
}

print("docs/media written")
