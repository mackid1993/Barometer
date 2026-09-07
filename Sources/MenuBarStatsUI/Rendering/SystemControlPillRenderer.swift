import AppKit
import MenuBarStatsCore

/// Fixed-width capsule used by Focus and Now Playing, independent of their changing content.
@MainActor
enum SystemControlPillRenderer {
    static func render(_ sample: SystemControlSample, in context: RenderContext) -> StatusItemContent {
        let width = round(30 * context.scale)
        let height = min(context.thickness - 4, round(21 * context.scale))
        let image = NSImage(size: NSSize(width: width, height: context.thickness))
        image.lockFocus()
        let capsule = NSRect(x: 0, y: (context.thickness - height) / 2, width: width, height: height)
        let ink: NSColor = context.isMonochrome ? .black : context.palette.color(for: context.appearance)
        ink.withAlphaComponent(sample.isActive ? 0.24 : 0.10).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: height / 2, yRadius: height / 2).fill()
        if let symbol = NSImage(systemSymbolName: sample.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12 * context.scale, weight: .semibold))
        {
            let size = symbol.size
            let rect = NSRect(x: (width - size.width) / 2, y: (context.thickness - size.height) / 2,
                              width: size.width, height: size.height)
            let tinted = NSImage(size: size)
            tinted.lockFocus()
            let bounds = NSRect(origin: .zero, size: size)
            symbol.draw(in: bounds)
            ink.setFill()
            bounds.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        }
        image.unlockFocus()
        image.isTemplate = context.isMonochrome
        return StatusItemContent(image: image, accessibilityValue: sample.accessibilityValue)
    }
}
