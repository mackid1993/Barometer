import AppKit
import MenuBarStatsCore

/// Renders normalized history values as a line, filled area, or bars.
public struct GraphRenderer: MenuBarRenderer {
    private let values: [Double]
    private let style: GraphStyle
    private let width: CGFloat

    /// Creates a graph renderer.
    public init(values: [Double], style: GraphStyle, width: CGFloat = 42) {
        self.values = values
        self.style = style
        self.width = width
    }

    /// Renders the graph image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        return makeImage(width: width * context.scale, context: context) { rect in
            let drawingRect = rect.insetBy(dx: 2, dy: metrics.graphVerticalInset(default: 3))
            let normalized = values.isEmpty ? [0] : values.map { min(1, max(0, $0)) }
            context.fillColor.withAlphaComponent(context.graphOpacity).setFill()
            context.graphColor.withAlphaComponent(context.graphOpacity).setStroke()

            switch style {
            case .bars:
                let barWidth = drawingRect.width / CGFloat(normalized.count)
                for (index, value) in normalized.enumerated() {
                    let height = max(1, drawingRect.height * CGFloat(value))
                    NSBezierPath(
                        rect: NSRect(
                            x: drawingRect.minX + CGFloat(index) * barWidth,
                            y: drawingRect.minY,
                            width: max(1, barWidth - 1),
                            height: height
                        )
                    ).fill()
                }
            case .line, .area:
                let path = NSBezierPath()
                for (index, value) in normalized.enumerated() {
                    let fraction = normalized.count == 1 ? 1 : CGFloat(index) / CGFloat(normalized.count - 1)
                    let point = NSPoint(
                        x: drawingRect.minX + fraction * drawingRect.width,
                        y: drawingRect.minY + CGFloat(value) * drawingRect.height
                    )
                    index == 0 ? path.move(to: point) : path.line(to: point)
                }
                if style == .area {
                    path.line(to: NSPoint(x: drawingRect.maxX, y: drawingRect.minY))
                    path.line(to: NSPoint(x: drawingRect.minX, y: drawingRect.minY))
                    path.close()
                    path.fill()
                } else {
                    path.lineWidth = 1.5
                    path.stroke()
                }
            }
        }
    }
}
