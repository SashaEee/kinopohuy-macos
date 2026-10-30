import SwiftUI

struct SpoilerAttribute: TextAttribute {
    let id: UUID
    let revealDate: Date?
}

/// Hidden text is covered by a grey block, as on the TV (it used a Metal "dust" shader, which needs Xcode's
/// separate Metal toolchain to build); the block fades out when revealed.
struct SpoilerTextRenderer: TextRenderer {
    static let revealDuration: TimeInterval = 0.3

    let date: Date

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let lines = Array(layout)
        var dust: [(spoiler: SpoilerAttribute, path: Path)] = []

        for (index, line) in lines.enumerated() {
            let bounds = line.typographicBounds.rect
            let top = index > 0 ? (lines[index - 1].typographicBounds.rect.maxY + bounds.minY) / 2 : bounds.minY
            let bottom = index < lines.count - 1 ? (bounds.maxY + lines[index + 1].typographicBounds.rect.minY) / 2 : bounds.maxY

            var lineRect: CGRect?

            func flush() {
                guard let rect = lineRect else { return }

                dust[dust.count - 1].path.addRect(CGRect(x: rect.minX, y: top - 0.5, width: rect.width, height: bottom - top + 1))
                lineRect = nil
            }

            for run in line {
                guard let spoiler = run[SpoilerAttribute.self] else {
                    flush()
                    context.draw(run)
                    continue
                }

                if spoiler.revealDate != nil {
                    var context = context
                    context.opacity = revealProgress(spoiler)
                    context.draw(run)
                }

                let rect = run.typographicBounds.rect

                guard rect.width > 0 else { continue }

                if dust.last?.spoiler.id != spoiler.id {
                    flush()
                    dust.append((spoiler, Path()))
                }

                lineRect = lineRect?.union(rect) ?? rect
            }

            flush()
        }

        for (spoiler, path) in dust {
            let opacity = 1 - revealProgress(spoiler)

            guard opacity > 0 else { continue }

            var context = context
            context.opacity = opacity
            context.fill(path, with: .color(Color(white: 0.3)))
        }
    }

    private func revealProgress(_ spoiler: SpoilerAttribute) -> CGFloat {
        spoiler.revealDate.map { min(1, max(0, date.timeIntervalSince($0) / Self.revealDuration)) } ?? 0
    }
}
