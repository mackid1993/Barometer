import AppKit
import MenuBarStatsCore

/// Concatenates several renderers with compact separators.
public struct CombinedRenderer: MenuBarRenderer {
    private let renderers: [any MenuBarRenderer]

    /// Creates a combined renderer.
    public init(renderers: [any MenuBarRenderer]) {
        self.renderers = renderers
    }

    /// Renders all child images into one image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let images = renderers.map { $0.render(in: context) }
        let gap: CGFloat = 6 * context.scale
        let width = combinedWidth(of: images, gap: gap)
        return makeImage(width: width, context: context) { rect in
            var x: CGFloat = 0
            for (index, image) in images.enumerated() {
                image.draw(in: NSRect(x: x, y: 0, width: image.size.width, height: rect.height))
                x += image.size.width
                guard index < images.count - 1 else {
                    continue
                }
                context.foregroundColor.withAlphaComponent(0.35).setStroke()
                let separator = NSBezierPath()
                separator.move(to: NSPoint(x: x + gap / 2, y: 5))
                separator.line(to: NSPoint(x: x + gap / 2, y: rect.height - 5))
                separator.lineWidth = 1
                separator.stroke()
                x += gap
            }
        }
    }
}

/// Concatenates already-rendered member images into one independently movable item.
public struct CombinedImageRenderer: MenuBarRenderer {
    private let images: [NSImage]
    private let showsSeparators: Bool

    /// Creates a rendered-image sequence.
    public init(images: [NSImage], showsSeparators: Bool) {
        self.images = images
        self.showsSeparators = showsSeparators
    }

    /// Draws members without reintroducing per-item padding.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let gap: CGFloat = showsSeparators ? 4 : 2
        let width = combinedWidth(of: images, gap: gap)
        return makeImage(width: max(1, width), context: context) { rect in
            var x: CGFloat = 0
            for (index, image) in images.enumerated() {
                image.draw(in: NSRect(x: x, y: 0, width: image.size.width, height: rect.height))
                x += image.size.width
                guard index < images.count - 1 else { continue }
                if showsSeparators {
                    context.foregroundColor.withAlphaComponent(0.3).setStroke()
                    let separator = NSBezierPath()
                    separator.move(to: NSPoint(x: x + gap / 2, y: 5))
                    separator.line(to: NSPoint(x: x + gap / 2, y: rect.height - 5))
                    separator.lineWidth = 1
                    separator.stroke()
                }
                x += gap
            }
        }
    }
}

// MARK: - Shared layout

/// Total width of `images` laid out side by side with `gap` between neighbors.
func combinedWidth(of images: [NSImage], gap: CGFloat) -> CGFloat {
    images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(max(0, images.count - 1))
}
