// Draws the DMG window's background in the app's colours, with the sun from its icon:
//   scripts/dmg/background.png (660×420), background@2x.png (1320×840) and background.tiff (both, for create-dmg).
// The layout matches scripts/release.sh: a 660×420 window, the app at (170, 200), «Программы» at (490, 200),
// 128 pt icons. Nothing is downloaded: the sun and the Inter font come from VideoLib/Resources.
//
// Usage (from anywhere): DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/dmg/make-background.swift

import AppKit
import CoreText

let here = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
let root = here.deletingLastPathComponent().deletingLastPathComponent()
let sunURL = root.appending(path: "VideoLib/Resources/KinoPohuy.icon/Assets/sun.png")
let fontURL = root.appending(path: "VideoLib/Resources/Fonts/InterVariable.ttf")

let width: CGFloat = 660
let height: CGFloat = 420
let appCenter = CGPoint(x: 170, y: 200)
let applicationsCenter = CGPoint(x: 490, y: 200)

// KP palette (VideoLib/Presentations/Theme/KP.swift) and the icon's own background.
let warmDark = CGColor(srgbRed: 0.102, green: 0.078, blue: 0.063, alpha: 1)
let bg = CGColor(srgbRed: 11 / 255, green: 11 / 255, blue: 13 / 255, alpha: 1)
let fg = NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
let sunOrange = CGColor(srgbRed: 1, green: 0.42, blue: 0, alpha: 1)
let sunYellow = CGColor(srgbRed: 1, green: 0.8, blue: 0.12, alpha: 1)

/// Inter at a given weight (the bundled file is variable: weight is its 'wght' axis).
func inter(_ size: CGFloat, weight: CGFloat) -> NSFont {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
          let base = descriptors.first
    else {
        return NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .semibold : .medium)
    }

    let wght = 0x7767_6874 // 'wght'
    let descriptor = CTFontDescriptorCreateCopyWithVariation(base, wght as CFNumber, weight)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
}

/// Draws a line of text centred on x at the given vertical centre.
func drawCentered(_ string: NSAttributedString, centerX: CGFloat, centerY: CGFloat) {
    let size = string.size()
    string.draw(at: CGPoint(x: (centerX - size.width / 2).rounded(), y: (centerY - size.height / 2).rounded()))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // Points, origin at the top left (as Finder places the icons).
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high

    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Background: the icon's warm black, fading to the app's black.
    let base = CGGradient(colorsSpace: space, colors: [warmDark, bg] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: width, y: height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // A warm glow behind the app, a faint cool one behind «Программы».
    let glow = CGGradient(colorsSpace: space, colors: [sunOrange.copy(alpha: 0.2)!, sunOrange.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: appCenter, startRadius: 0, endCenter: appCenter, endRadius: 200, options: [])
    let cool = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.05), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(cool, startCenter: applicationsCenter, startRadius: 0, endCenter: applicationsCenter, endRadius: 150, options: [])

    // Header: the sun and the name.
    let title = text("КиноПохуй", inter(21, weight: 700), fg, kern: -0.3)
    let sunSize: CGFloat = 30
    let gap: CGFloat = 9
    let headerWidth = sunSize + gap + title.size().width
    let headerX = ((width - headerWidth) / 2).rounded()
    let headerY: CGFloat = 46
    if let sun = NSImage(contentsOf: sunURL) {
        sun.draw(in: CGRect(x: headerX, y: headerY - sunSize / 2, width: sunSize, height: sunSize), from: .zero,
                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
    let titleSize = title.size()
    title.draw(at: CGPoint(x: headerX + sunSize + gap, y: (headerY - titleSize.height / 2).rounded()))

    // The arrow from the app to «Программы», in the sun's gradient.
    let arrowStart = CGPoint(x: appCenter.x + 92, y: appCenter.y)
    let arrowEnd = CGPoint(x: applicationsCenter.x - 92, y: applicationsCenter.y)
    let head: CGFloat = 11
    let arrow = CGMutablePath()
    arrow.move(to: arrowStart)
    arrow.addLine(to: arrowEnd)
    arrow.move(to: CGPoint(x: arrowEnd.x - head, y: arrowEnd.y - head))
    arrow.addLine(to: arrowEnd)
    arrow.addLine(to: CGPoint(x: arrowEnd.x - head, y: arrowEnd.y + head))
    ctx.saveGState()
    ctx.addPath(arrow.copy(strokingWithWidth: 3.5, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    let stroke = CGGradient(colorsSpace: space, colors: [sunOrange.copy(alpha: 0.35)!, sunOrange, sunYellow] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(stroke, start: arrowStart, end: CGPoint(x: arrowEnd.x, y: arrowEnd.y), options: [])
    ctx.restoreGState()

    // What to do, and the one-time Gatekeeper step (the app isn't signed by Apple).
    drawCentered(text("Перетащите в Программы", inter(16, weight: 600), fg.withAlphaComponent(0.88)), centerX: width / 2, centerY: 326)

    var hintSize: CGFloat = 11.5
    var hint = text("Первый запуск: Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»", inter(hintSize, weight: 500), fg.withAlphaComponent(0.5))
    while hint.size().width > width - 48, hintSize > 9 {
        hintSize -= 0.5
        hint = text(hint.string, inter(hintSize, weight: 500), fg.withAlphaComponent(0.5))
    }
    drawCentered(hint, centerX: width / 2, centerY: 352)

    NSGraphicsContext.current = nil

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: width, height: height) // 72 or 144 dpi, which tiffutil pairs up
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) -> URL {
    let url = here.appending(path: name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    return url
}

let png1x = write(render(scale: 1), "background.png")
let png2x = write(render(scale: 2), "background@2x.png")

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", png1x.path, png2x.path, "-out", here.appending(path: "background.tiff").path]
try tiffutil.run()
tiffutil.waitUntilExit()

print(tiffutil.terminationStatus == 0 ? "scripts/dmg/background{.png,@2x.png,.tiff} written" : "tiffutil failed")
exit(tiffutil.terminationStatus)
