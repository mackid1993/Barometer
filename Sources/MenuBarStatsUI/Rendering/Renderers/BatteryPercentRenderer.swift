import AppKit
import MenuBarStatsCore

/// Draws a compact battery outline with a stable percentage centered inside it.
public struct BatteryPercentRenderer: MenuBarRenderer {
    private let value: String

    /// Creates an iPhone-style percentage battery glyph.
    public init(percent: Double?) {
        if let percent, percent.isFinite {
            value = String(min(100, max(0, Int(percent.rounded()))))
        } else {
            value = "—"
        }
    }

    /// Renders the outlined battery and its percentage without a separate text label.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let bodyWidth = ceil(27 * context.scale)
        let terminalWidth = max(2, round(2 * context.scale))
        let totalWidth = bodyWidth + terminalWidth + 1
        return makeImage(width: totalWidth, context: context) { rect in
            let bodyHeight = min(rect.height - 6, ceil(14 * context.scale))
            let bodyRect = NSRect(
                x: 0.5,
                y: floor((rect.height - bodyHeight) / 2) + 0.5,
                width: bodyWidth - 1,
                height: bodyHeight - 1
            )
            context.foregroundColor.setStroke()
            context.foregroundColor.setFill()
            let outline = NSBezierPath(roundedRect: bodyRect, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.25
            outline.stroke()
            let terminalHeight = max(5, floor(bodyHeight * 0.42))
            NSBezierPath(
                roundedRect: NSRect(
                    x: bodyRect.maxX + 1,
                    y: floor((rect.height - terminalHeight) / 2),
                    width: terminalWidth,
                    height: terminalHeight
                ),
                xRadius: 1,
                yRadius: 1
            ).fill()

            let fontSize = min(9, max(7, bodyHeight - 5))
            let text = NSAttributedString(
                string: value,
                attributes: [
                    .font: context.font(ofSize: fontSize, weight: .semibold, monospacedDigits: true),
                    .foregroundColor: context.foregroundColor,
                ]
            )
            let textSize = text.size()
            text.draw(
                at: NSPoint(
                    x: floor(bodyRect.midX - textSize.width / 2),
                    y: floor(bodyRect.midY - textSize.height / 2)
                ))
        }
    }
}
