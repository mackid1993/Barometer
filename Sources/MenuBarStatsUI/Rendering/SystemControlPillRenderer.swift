import AppKit
import MenuBarStatsCore

/// Fixed-width status glyphs for Focus and Now Playing.
@MainActor
enum SystemControlPillRenderer {
    /// A purple status-only moon. Focus is controlled through macOS Control Center.
    static func renderFocus(_ sample: SystemControlSample, in context: RenderContext) -> StatusItemContent {
        let width = round(18 * context.scale)
        let image = NSImage(size: NSSize(width: width, height: context.thickness))
        image.lockFocus()
        if let symbol = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15 * context.scale, weight: .semibold))
        {
            let size = symbol.size
            let tinted = NSImage(size: size)
            tinted.lockFocus()
            let bounds = NSRect(origin: .zero, size: size)
            symbol.draw(in: bounds)
            NSColor(srgbRed: 0.68, green: 0.55, blue: 1.0, alpha: 1).setFill()
            bounds.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: (width - size.width) / 2, y: (context.thickness - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        image.unlockFocus()
        image.isTemplate = false
        return StatusItemContent(image: image, accessibilityValue: sample.accessibilityValue)
    }

    static func render(
        _ sample: SystemControlSample,
        in context: RenderContext,
        symbolPointSize: CGFloat = 12
    ) -> StatusItemContent {
        let width = round(22 * context.scale)
        let image = NSImage(size: NSSize(width: width, height: context.thickness))
        image.lockFocus()
        let ink: NSColor = context.isMonochrome ? .black : context.palette.color(for: context.appearance)
        if let symbol = NSImage(systemSymbolName: sample.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: symbolPointSize * context.scale, weight: .semibold))
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
