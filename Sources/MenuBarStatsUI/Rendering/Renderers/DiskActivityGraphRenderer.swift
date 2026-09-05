import AppKit
import MenuBarStatsCore

/// Renders disk reads above a centerline and writes below it.
public struct DiskActivityGraphRenderer: MenuBarRenderer {
    private let reads: [Double]
    private let writes: [Double]
    private let style: GraphStyle
    private let width: CGFloat

    /// Creates a bidirectional disk activity graph from normalized values.
    public init(reads: [Double], writes: [Double], style: GraphStyle, width: CGFloat = 42) {
        self.reads = reads
        self.writes = writes
        self.style = style
        self.width = width
    }

    /// Renders read and write activity around one shared centerline.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        return makeImage(width: width * context.scale, context: context) { rect in
            let drawingRect = rect.insetBy(dx: 2, dy: metrics.graphVerticalInset(default: 2))
            let centerY = floor(drawingRect.midY)
            drawHalf(
                values: reads,
                baseline: centerY,
                extent: drawingRect.maxY - centerY,
                direction: 1,
                color: context.graphColor.withAlphaComponent(context.graphOpacity),
                drawingRect: drawingRect
            )
            drawHalf(
                values: writes,
                baseline: centerY,
                extent: centerY - drawingRect.minY,
                direction: -1,
                color: context.fillColor.withAlphaComponent(context.graphOpacity * 0.7),
                drawingRect: drawingRect
            )
        }
    }

    @MainActor
    private func drawHalf(
        values: [Double],
        baseline: CGFloat,
        extent: CGFloat,
        direction: CGFloat,
        color: NSColor,
        drawingRect: NSRect
    ) {
        let normalized = values.isEmpty ? [0] : values.map { min(1, max(0, $0)) }
        color.setFill()
        color.setStroke()
        if style == .bars {
            let barWidth = drawingRect.width / CGFloat(normalized.count)
            for (index, value) in normalized.enumerated() {
                let height = max(value > 0 ? 1 : 0, extent * CGFloat(value))
                let y = direction > 0 ? baseline : baseline - height
                NSBezierPath(
                    rect: NSRect(
                        x: drawingRect.minX + CGFloat(index) * barWidth,
                        y: y,
                        width: max(1, barWidth - 1),
                        height: height
                    )
                ).fill()
            }
            return
        }

        let path = NSBezierPath()
        for (index, value) in normalized.enumerated() {
            let fraction = normalized.count == 1 ? 1 : CGFloat(index) / CGFloat(normalized.count - 1)
            let point = NSPoint(
                x: drawingRect.minX + fraction * drawingRect.width,
                y: baseline + direction * extent * CGFloat(value)
            )
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        if style == .area {
            path.line(to: NSPoint(x: drawingRect.maxX, y: baseline))
            path.line(to: NSPoint(x: drawingRect.minX, y: baseline))
            path.close()
            path.fill()
        } else {
            path.lineWidth = 1.25
            path.stroke()
        }
    }
}
