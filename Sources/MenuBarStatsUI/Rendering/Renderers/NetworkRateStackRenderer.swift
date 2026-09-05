import AppKit
import MenuBarStatsCore

/// Renders download and upload as two visually equal, stable-width rows.
public struct NetworkRateStackRenderer: MenuBarRenderer {
    private let top: String
    private let bottom: String
    private let reservedTop: String
    private let reservedBottom: String

    /// Creates an equal two-row network renderer.
    public init(download: String, upload: String, reservedValue: String) {
        top = "↓\(download)"
        bottom = "↑\(upload)"
        reservedTop = "↓\(reservedValue)"
        reservedBottom = "↑\(reservedValue)"
    }

    /// Creates two explicitly ordered transfer rows.
    public init(top: String, bottom: String, reservedTop: String, reservedBottom: String) {
        self.top = top
        self.bottom = bottom
        self.reservedTop = reservedTop
        self.reservedBottom = reservedBottom
    }

    /// Renders matched arrows and values on a fixed canvas.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        let pointSize = metrics.compactPointSize
        let font = context.font(ofSize: pointSize, weight: context.fontWeight.nsWeight, monospacedDigits: true)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: context.foregroundColor,
        ]
        let topParts = Self.rowParts(top)
        let bottomParts = Self.rowParts(bottom)
        let reservedTopParts = Self.rowParts(reservedTop)
        let reservedBottomParts = Self.rowParts(reservedBottom)
        let topMarker = NSAttributedString(string: topParts.marker, attributes: attributes)
        let bottomMarker = NSAttributedString(string: bottomParts.marker, attributes: attributes)
        let reservedTopMarker = NSAttributedString(string: reservedTopParts.marker, attributes: attributes)
        let reservedBottomMarker = NSAttributedString(string: reservedBottomParts.marker, attributes: attributes)
        let topValue = NSAttributedString(string: topParts.value, attributes: attributes)
        let bottomValue = NSAttributedString(string: bottomParts.value, attributes: attributes)
        let reservedTopValue = NSAttributedString(string: reservedTopParts.value, attributes: attributes)
        let reservedBottomValue = NSAttributedString(string: reservedBottomParts.value, attributes: attributes)
        // Rows without a leading arrow reserve no marker column at all. Keeping the gap would push
        // every value one gap off center, which is visible on a two-row item that has no arrows.
        let hasMarker =
            !(topParts.marker.isEmpty && bottomParts.marker.isEmpty
            && reservedTopParts.marker.isEmpty && reservedBottomParts.marker.isEmpty)
        let markerWidth = ceil(
            max(
                topMarker.size().width, bottomMarker.size().width, reservedTopMarker.size().width,
                reservedBottomMarker.size().width)
        )
        let valueWidth = ceil(
            max(
                topValue.size().width, bottomValue.size().width, reservedTopValue.size().width,
                reservedBottomValue.size().width)
        )
        let pairGap = hasMarker ? metrics.densePairGap : 0
        let width =
            MenuBarLayoutMetrics.contentInset * 2
            + markerWidth
            + pairGap
            + valueWidth

        // With arrows, every row starts at the same leading edge so the markers form one column.
        // Without them the rows are two bare readings of different lengths, and left-aligning leaves
        // a ragged column, so each row is centered on the other instead.
        let topValueOffset = hasMarker ? 0 : ((valueWidth - ceil(topValue.size().width)) / 2).rounded()
        let bottomValueOffset = hasMarker ? 0 : ((valueWidth - ceil(bottomValue.size().width)) / 2).rounded()
        // An empty marker must not take part in the row height. Attributes on an empty attributed
        // string apply to no characters, so it reports the default system font's line height rather
        // than this renderer's compact one, and taking the maximum pushed both rows below the row
        // every other two-row item uses.
        let topTextHeight =
            topParts.marker.isEmpty
            ? topValue.size().height
            : max(topMarker.size().height, topValue.size().height)
        let bottomTextHeight =
            bottomParts.marker.isEmpty
            ? bottomValue.size().height
            : max(bottomMarker.size().height, bottomValue.size().height)
        let groupWidth = markerWidth + pairGap + max(ceil(topValue.size().width), ceil(bottomValue.size().width))
        return makeImage(width: width, context: context) { rect in
            let groupOffset = TextRenderer.centeringOffset(contentWidth: groupWidth, canvasWidth: rect.width)
            let topOrigins = Self.rowOrigins(
                markerFieldWidth: markerWidth,
                gap: pairGap,
                backingScaleFactor: context.backingScaleFactor
            )
            let bottomOrigins = Self.rowOrigins(
                markerFieldWidth: markerWidth,
                gap: pairGap,
                backingScaleFactor: context.backingScaleFactor
            )
            topMarker.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset + groupOffset + topOrigins.marker,
                    y: metrics.compactRowY(0, textHeight: topTextHeight)
                )
            )
            topValue.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset + groupOffset + topOrigins.value + topValueOffset,
                    y: metrics.compactRowY(0, textHeight: topTextHeight)
                )
            )
            bottomMarker.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset + groupOffset + bottomOrigins.marker,
                    y: metrics.compactRowY(1, textHeight: bottomTextHeight)
                )
            )
            bottomValue.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset + groupOffset + bottomOrigins.value + bottomValueOffset,
                    y: metrics.compactRowY(1, textHeight: bottomTextHeight)
                )
            )
        }
    }

    static func rowParts(_ text: String) -> (marker: String, value: String) {
        guard let first = text.first, first == "↑" || first == "↓" else {
            return ("", text)
        }
        return (String(first), String(text.dropFirst()))
    }

    /// Pins every arrow to one leading column and starts every live value after the fixed internal gap.
    static func rowOrigins(
        markerFieldWidth: CGFloat,
        gap: CGFloat,
        backingScaleFactor: CGFloat
    ) -> (marker: CGFloat, value: CGFloat) {
        let scale = max(1, backingScaleFactor)
        let marker: CGFloat = 0
        let markerFieldEdge = ceil(markerFieldWidth * scale) / scale
        return (marker, markerFieldEdge + gap)
    }
}
