import AppKit
import MenuBarStatsCore

/// Renders a small label above a value.
public struct StackedLabelRenderer: MenuBarRenderer {
    private let label: String
    private let reservedLabel: String
    private let value: String
    private let reservedValue: String?

    /// Creates a stacked label renderer.
    public init(
        label: String,
        value: String,
        reservedLabel: String? = nil,
        reservedValue: String? = nil
    ) {
        self.label = label
        self.reservedLabel = reservedLabel ?? label
        self.value = value
        self.reservedValue = reservedValue
    }

    /// Renders the stacked image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        let pointSize = metrics.compactPointSize
        // Labels sit at the same reduced emphasis as the Sensors stack labels so every
        // two-row item reads as "dim label over bright value".
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: context.font(ofSize: pointSize, weight: context.fontWeight.nsWeight, monospacedDigits: false),
            .foregroundColor: context.foregroundColor.withAlphaComponent(MenuBarLayoutMetrics.labelEmphasis),
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: context.font(ofSize: pointSize, weight: context.fontWeight.nsWeight, monospacedDigits: true),
            .foregroundColor: context.foregroundColor,
        ]
        let labelText = NSAttributedString(string: label, attributes: labelAttributes)
        let reservedLabelText = NSAttributedString(string: reservedLabel, attributes: labelAttributes)
        let valueText = NSAttributedString(string: value, attributes: valueAttributes)
        let reservedText = NSAttributedString(string: reservedValue ?? value, attributes: valueAttributes)
        let contentWidth = ceil(
            max(
                labelText.size().width,
                reservedLabelText.size().width,
                valueText.size().width,
                reservedText.size().width
            )
        )
        let width =
            contentWidth + MenuBarLayoutMetrics.contentInset * 2
        return makeImage(width: width, context: context) { rect in
            labelText.draw(
                at: NSPoint(
                    x: TextRenderer.centeringOffset(
                        contentWidth: labelText.size().width,
                        canvasWidth: rect.width
                    ),
                    y: metrics.compactRowY(0, textHeight: labelText.size().height)
                )
            )
            valueText.draw(
                at: NSPoint(
                    x: TextRenderer.centeringOffset(
                        contentWidth: valueText.size().width,
                        canvasWidth: rect.width
                    ),
                    y: metrics.compactRowY(1, textHeight: valueText.size().height)
                )
            )
        }
    }

    /// Every label-over-value mode shares one horizontal origin for both rows.
    static var rowXOrigins: (label: CGFloat, value: CGFloat) {
        (MenuBarLayoutMetrics.contentInset, MenuBarLayoutMetrics.contentInset)
    }
}
