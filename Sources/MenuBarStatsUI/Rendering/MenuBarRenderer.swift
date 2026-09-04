import AppKit
import MenuBarStatsCore

/// Appearance used to resolve menu bar colors.
public enum MenuBarAppearance {
    case light
    case dark
}

/// Light and dark colors for one module.
public struct MenuBarPalette {
    /// Color used in light appearance.
    public let light: NSColor

    /// Color used in dark appearance.
    public let dark: NSColor

    /// Creates a menu bar palette.
    public init(light: NSColor, dark: NSColor) {
        self.light = light
        self.dark = dark
    }

    /// Resolves the appropriate color for an appearance.
    public func color(for appearance: MenuBarAppearance) -> NSColor {
        appearance == .dark ? dark : light
    }
}

/// Shared rendering inputs derived from a status item and application settings.
public struct RenderContext {
    /// Current status bar thickness.
    public let thickness: CGFloat

    /// Effective light or dark appearance.
    public let appearance: MenuBarAppearance

    /// Module color palette.
    public let palette: MenuBarPalette

    /// Graph stroke and fill palettes plus threshold roles.
    public let graphPalette: MenuBarPalette
    public let fillPalette: MenuBarPalette
    public let warningPalette: MenuBarPalette
    public let criticalPalette: MenuBarPalette

    /// Menu bar font size.
    public let fontSize: CGFloat

    /// Whether the result should be an adaptive template image.
    public let isMonochrome: Bool

    /// Scale applied to renderer widths and symbol sizes.
    public let scale: CGFloat

    /// Blank horizontal space added to each side of an item.
    public let horizontalSpacing: CGFloat

    /// Shared graph opacity, type weight, and compact-layout choice.
    public let graphOpacity: CGFloat
    public let fontWeight: MenuBarFontWeight
    public let usesCompactLayout: Bool

    /// Creates a render context.
    public init(
        thickness: CGFloat,
        appearance: MenuBarAppearance,
        palette: MenuBarPalette,
        graphPalette: MenuBarPalette? = nil,
        fillPalette: MenuBarPalette? = nil,
        warningPalette: MenuBarPalette? = nil,
        criticalPalette: MenuBarPalette? = nil,
        fontSize: CGFloat,
        isMonochrome: Bool,
        scale: CGFloat = 1,
        horizontalSpacing: CGFloat = 0,
        graphOpacity: CGFloat = 0.85,
        fontWeight: MenuBarFontWeight = .medium,
        usesCompactLayout: Bool = false
    ) {
        self.thickness = thickness
        self.appearance = appearance
        self.palette = palette
        self.graphPalette = graphPalette ?? palette
        self.fillPalette = fillPalette ?? graphPalette ?? palette
        self.warningPalette = warningPalette ?? palette
        self.criticalPalette = criticalPalette ?? warningPalette ?? palette
        self.fontSize = fontSize
        self.isMonochrome = isMonochrome
        self.scale = scale
        self.horizontalSpacing = horizontalSpacing
        self.graphOpacity = min(1, max(0.1, graphOpacity))
        self.fontWeight = fontWeight
        self.usesCompactLayout = usesCompactLayout
    }

    /// Foreground color to use when drawing.
    public var foregroundColor: NSColor {
        isMonochrome ? .black : palette.color(for: appearance)
    }

    public var graphColor: NSColor {
        isMonochrome ? .black : graphPalette.color(for: appearance)
    }

    public var fillColor: NSColor {
        isMonochrome ? .black : fillPalette.color(for: appearance)
    }

    public var warningColor: NSColor {
        isMonochrome ? .black : warningPalette.color(for: appearance)
    }

    public var criticalColor: NSColor {
        isMonochrome ? .black : criticalPalette.color(for: appearance)
    }
}

/// Canonical geometry for every text-based menu bar renderer.
///
/// Keeping these calculations in one place prevents modules from acquiring subtly
/// different baselines, insets, and gaps as their renderers evolve.
struct MenuBarLayoutMetrics {
    static let contentInset: CGFloat = 0.5

    let context: RenderContext

    var iconTextGap: CGFloat {
        context.usesCompactLayout ? 1 : max(3, round(3.5 * context.scale))
    }

    func centeredY(for height: CGFloat) -> CGFloat {
        floor((context.thickness - height) / 2)
    }

    func symbolY(for size: NSSize, nativeSize: NSSize, alignmentRect: NSRect) -> CGFloat {
        guard nativeSize.height > 0 else {
            return centeredY(for: size.height)
        }
        // SF Symbols include transparent optical padding. Align the symbol's
        // published alignment rect instead of its full image canvas.
        let scale = size.height / nativeSize.height
        let opticalAdjustment = (nativeSize.height / 2 - alignmentRect.midY) * scale
        return centeredY(for: size.height) + opticalAdjustment
    }

    func stackedOrigins(labelHeight: CGFloat, valueHeight: CGFloat) -> (label: NSPoint, value: NSPoint) {
        let rowGap: CGFloat = 0
        let contentHeight = labelHeight + rowGap + valueHeight
        let bottom = floor((context.thickness - contentHeight) / 2)
        return (
            label: NSPoint(x: Self.contentInset, y: bottom + valueHeight + rowGap),
            value: NSPoint(x: Self.contentInset, y: bottom)
        )
    }

    var compactPointSize: CGFloat {
        min(max(8, context.fontSize - 2), max(8, context.thickness / 2 - 2))
    }

    func compactRowY(_ row: Int, textHeight: CGFloat) -> CGFloat {
        let rowHeight = context.thickness / 2
        let rowBottom = row == 0 ? rowHeight : 0
        return rowBottom + floor((rowHeight - textHeight) / 2)
    }

    func compactSymbolSize(nativeSize: NSSize) -> NSSize {
        let rowHeight = context.thickness / 2
        let scaledHeight = compactPointSize * context.scale
        let targetHeight = min(rowHeight - 1, max(scaledHeight, (rowHeight - 1) * min(1, context.scale)))
        let aspectRatio = max(0.5, nativeSize.width / max(1, nativeSize.height))
        return NSSize(width: ceil(targetHeight * aspectRatio), height: targetHeight)
    }

    func compactSymbolY(for size: NSSize, nativeSize: NSSize, alignmentRect: NSRect) -> CGFloat {
        let centered = compactRowY(0, textHeight: size.height)
        guard nativeSize.height > 0 else {
            return centered
        }
        let scale = size.height / nativeSize.height
        let opticalAdjustment = (nativeSize.height / 2 - alignmentRect.midY) * scale
        return centered + opticalAdjustment
    }

    func symbolSize(nativeSize: NSSize, font: NSFont) -> NSSize {
        let height = min(font.pointSize * context.scale, context.thickness - 4)
        let aspectRatio = max(0.5, nativeSize.width / max(1, nativeSize.height))
        return NSSize(width: ceil(height * aspectRatio), height: height)
    }
}

/// Produces one resolution-independent menu bar image.
@MainActor
public protocol MenuBarRenderer {
    /// Renders an image for the supplied context.
    func render(in context: RenderContext) -> NSImage
}

/// Renders a single line of monospaced-digit text.
public struct TextRenderer: MenuBarRenderer {
    private let text: String
    private let reservedText: String?

    /// Creates a text renderer, optionally reserving the width of a larger value.
    public init(text: String, reservedText: String? = nil) {
        self.text = text
        self.reservedText = reservedText
    }

    /// Renders the text image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: context.fontSize, weight: context.fontWeight.nsWeight),
            .foregroundColor: context.foregroundColor,
        ]
        let value = NSAttributedString(string: text, attributes: attributes)
        let reserved = NSAttributedString(string: reservedText ?? text, attributes: attributes)
        let width = ceil(max(value.size().width, reserved.size().width)) + 4
        return makeImage(width: width, context: context) { rect in
            let size = value.size()
            value.draw(at: NSPoint(x: floor((rect.width - size.width) / 2), y: floor((rect.height - size.height) / 2)))
        }
    }
}

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
                    .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: context.foregroundColor,
                ]
            )
            let textSize = text.size()
            text.draw(at: NSPoint(
                x: floor(bodyRect.midX - textSize.width / 2),
                y: floor(bodyRect.midY - textSize.height / 2)
            ))
        }
    }
}

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
        let compactScale = context.usesCompactLayout ? 0.85 : 1
        return makeImage(width: width * context.scale * compactScale, context: context) { rect in
            let drawingRect = rect.insetBy(dx: 2, dy: 3)
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
        makeImage(width: width * context.scale, context: context) { rect in
            let drawingRect = rect.insetBy(dx: 2, dy: 2)
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
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pointSize, weight: context.fontWeight.nsWeight),
            .foregroundColor: context.foregroundColor,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: context.fontWeight.nsWeight),
            .foregroundColor: context.foregroundColor,
        ]
        let labelText = NSAttributedString(string: label, attributes: labelAttributes)
        let reservedLabelText = NSAttributedString(string: reservedLabel, attributes: labelAttributes)
        let valueText = NSAttributedString(string: value, attributes: valueAttributes)
        let reservedText = NSAttributedString(string: reservedValue ?? value, attributes: valueAttributes)
        let width = ceil(
            max(
                labelText.size().width,
                reservedLabelText.size().width,
                valueText.size().width,
                reservedText.size().width
            )
        ) + MenuBarLayoutMetrics.contentInset * 2
        return makeImage(width: width, context: context) { _ in
            labelText.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset,
                    y: metrics.compactRowY(0, textHeight: labelText.size().height)
                )
            )
            valueText.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset,
                    y: metrics.compactRowY(1, textHeight: valueText.size().height)
                )
            )
        }
    }
}

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
        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: context.fontWeight.nsWeight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: context.foregroundColor,
        ]
        let topText = NSAttributedString(string: top, attributes: attributes)
        let bottomText = NSAttributedString(string: bottom, attributes: attributes)
        let reservedTopText = NSAttributedString(string: reservedTop, attributes: attributes)
        let reservedBottomText = NSAttributedString(string: reservedBottom, attributes: attributes)
        let width = MenuBarLayoutMetrics.contentInset * 2 + ceil(
            max(
                topText.size().width,
                bottomText.size().width,
                reservedTopText.size().width,
                reservedBottomText.size().width
            )
        )

        return makeImage(width: width, context: context) { _ in
            topText.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset,
                    y: metrics.compactRowY(0, textHeight: topText.size().height)
                )
            )
            bottomText.draw(
                at: NSPoint(
                    x: MenuBarLayoutMetrics.contentInset,
                    y: metrics.compactRowY(1, textHeight: bottomText.size().height)
                )
            )
        }
    }
}

/// One labeled, stable-width field in a compact Sensors stack.
public struct SensorStackValue {
    public let label: String
    public let value: String
    public let reservedValue: String

    /// Creates one menu bar sensor field.
    public init(label: String, value: String, reservedValue: String) {
        self.label = label
        self.value = value
        self.reservedValue = reservedValue
    }
}

/// Renders arbitrary labeled readings in matched two-row columns.
public struct SensorStackRenderer: MenuBarRenderer {
    private let values: [SensorStackValue]

    /// Creates a compact stack in user-selected order.
    public init(values: [SensorStackValue]) {
        self.values = values
    }

    static func displayLabel(_ label: String) -> String {
        guard !label.isEmpty, !label.hasSuffix(":") else { return label }
        return "\(label):"
    }

    /// Renders two readings per column and expands horizontally for additional values.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        let valuePointSize = metrics.compactPointSize
        let labelPointSize = valuePointSize
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: labelPointSize, weight: context.fontWeight.nsWeight),
            .foregroundColor: context.foregroundColor.withAlphaComponent(0.82),
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: valuePointSize,
                weight: context.fontWeight.nsWeight
            ),
            .foregroundColor: context.foregroundColor,
        ]
        let fields = values.isEmpty
            ? [SensorStackValue(label: "SENS", value: "—", reservedValue: "999.9°C")]
            : values
        let columns = stride(from: 0, to: fields.count, by: 2).map { start in
            Array(fields[start..<min(start + 2, fields.count)])
        }
        let labelGap: CGFloat = 0
        let columnGap: CGFloat = 2
        let columnWidths = columns.map { column in
            column.reduce(CGFloat(0)) { width, field in
                let labelWidth = NSAttributedString(
                    string: Self.displayLabel(field.label),
                    attributes: labelAttributes
                ).size().width
                let reservedWidth = NSAttributedString(
                    string: field.reservedValue,
                    attributes: valueAttributes
                ).size().width
                let valueWidth = NSAttributedString(string: field.value, attributes: valueAttributes).size().width
                return max(width, ceil(labelWidth + labelGap + max(reservedWidth, valueWidth)))
            }
        }
        let contentWidth = MenuBarLayoutMetrics.contentInset * 2
            + columnWidths.reduce(0, +)
            + columnGap * CGFloat(max(0, columns.count - 1))

        return makeImage(width: contentWidth, context: context) { rect in
            var x = MenuBarLayoutMetrics.contentInset
            for (columnIndex, column) in columns.enumerated() {
                let columnWidth = columnWidths[columnIndex]
                for (rowIndex, field) in column.enumerated() {
                    let label = NSMutableAttributedString(
                        string: Self.displayLabel(field.label),
                        attributes: labelAttributes
                    )
                    let value = NSAttributedString(string: field.value, attributes: valueAttributes)
                    let flexibleGap = max(labelGap, columnWidth - label.size().width - value.size().width)
                    if label.length > 0 {
                        label.addAttribute(
                            .kern,
                            value: flexibleGap,
                            range: NSRange(location: label.length - 1, length: 1)
                        )
                    }
                    label.append(value)
                    let combinedHeight = label.size().height
                    let y = fields.count == 1
                        ? floor((rect.height - combinedHeight) / 2)
                        : metrics.compactRowY(rowIndex, textHeight: combinedHeight)
                    label.draw(at: NSPoint(x: x, y: y))
                }
                x += columnWidth + columnGap
            }
        }
    }
}

/// Renders an SF Symbol followed by text.
public struct IconTextRenderer: MenuBarRenderer {
    private let symbolName: String
    private let text: String
    private let reservedText: String
    private let reservedSymbolNames: [String]

    /// Creates an icon-and-text renderer.
    public init(
        symbolName: String,
        text: String,
        reservedText: String? = nil,
        reservedSymbolNames: [String] = []
    ) {
        self.symbolName = symbolName
        self.text = text
        self.reservedText = reservedText ?? text
        self.reservedSymbolNames = reservedSymbolNames
    }

    /// Renders the icon and text image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: context.fontSize,
            weight: context.fontWeight.nsWeight
        )
        let symbolPointSize = min(context.fontSize * context.scale, context.thickness - 4)
        let baseConfiguration = NSImage.SymbolConfiguration(
            pointSize: symbolPointSize,
            weight: context.fontWeight.nsWeight
        )
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [context.foregroundColor])
        let configuration = baseConfiguration.applying(colorConfiguration)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: context.foregroundColor,
        ]
        let textValue = NSAttributedString(string: text, attributes: attributes)
        let textSize = textValue.size()
        let reservedTextSize = NSAttributedString(string: reservedText, attributes: attributes).size()
        let metrics = MenuBarLayoutMetrics(context: context)
        let symbolSize = symbol.map { metrics.symbolSize(nativeSize: $0.size, font: font) } ?? .zero
        let reservedSymbolWidth = reservedSymbolNames.compactMap { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }.map { metrics.symbolSize(nativeSize: $0.size, font: font).width }.max() ?? 0
        let gap = symbol == nil ? 0 : metrics.iconTextGap
        let width = MenuBarLayoutMetrics.contentInset * 2
            + max(symbolSize.width, reservedSymbolWidth)
            + gap
            + ceil(max(textSize.width, reservedTextSize.width))
        return makeImage(width: width, context: context) { rect in
            var x = MenuBarLayoutMetrics.contentInset
            if let symbol {
                let symbolRect = NSRect(
                    x: x,
                    y: metrics.symbolY(
                        for: symbolSize,
                        nativeSize: symbol.size,
                        alignmentRect: symbol.alignmentRect
                    ),
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbol.draw(in: symbolRect)
                x = symbolRect.maxX + gap
            }
            textValue.draw(at: NSPoint(x: x, y: metrics.centeredY(for: textSize.height)))
        }
    }
}

/// Renders one SF Symbol without adding an empty text gap.
public struct SymbolRenderer: MenuBarRenderer {
    private let symbolName: String
    private let reservedSymbolName: String

    /// Creates a symbol renderer with an optional stable-width reference symbol.
    public init(symbolName: String, reservedSymbolName: String? = nil) {
        self.symbolName = symbolName
        self.reservedSymbolName = reservedSymbolName ?? symbolName
    }

    /// Renders the symbol centered on the canonical menu bar canvas.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let font = NSFont.systemFont(ofSize: context.fontSize, weight: context.fontWeight.nsWeight)
        let pointSize = min(context.fontSize * context.scale, context.thickness - 4)
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: context.fontWeight.nsWeight)
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [context.foregroundColor])
        let configuration = baseConfiguration.applying(colorConfiguration)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let reserved = NSImage(systemSymbolName: reservedSymbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let metrics = MenuBarLayoutMetrics(context: context)
        let size = symbol.map { metrics.symbolSize(nativeSize: $0.size, font: font) } ?? .zero
        let reservedSize = reserved.map { metrics.symbolSize(nativeSize: $0.size, font: font) } ?? size
        let width = MenuBarLayoutMetrics.contentInset * 2 + ceil(max(size.width, reservedSize.width))
        return makeImage(width: width, context: context) { rect in
            guard let symbol else { return }
            symbol.draw(
                in: NSRect(
                    x: floor((rect.width - size.width) / 2),
                    y: metrics.symbolY(for: size, nativeSize: symbol.size, alignmentRect: symbol.alignmentRect),
                    width: size.width,
                    height: size.height
                )
            )
        }
    }
}

/// Renders an SF Symbol directly above compact text.
public struct IconStackRenderer: MenuBarRenderer {
    private let symbolName: String
    private let text: String
    private let reservedText: String
    private let reservedSymbolNames: [String]

    /// Creates a vertically stacked icon-and-text renderer.
    public init(
        symbolName: String,
        text: String,
        reservedText: String? = nil,
        reservedSymbolNames: [String] = []
    ) {
        self.symbolName = symbolName
        self.text = text
        self.reservedText = reservedText ?? text
        self.reservedSymbolNames = reservedSymbolNames
    }

    /// Renders the icon and text on the canonical compact two-row grid.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        let pointSize = metrics.compactPointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: context.fontWeight.nsWeight)
        let symbolPointSize = min(context.thickness / 2 - 1, max(pointSize, pointSize * context.scale))
        let baseConfiguration = NSImage.SymbolConfiguration(
            pointSize: symbolPointSize,
            weight: context.fontWeight.nsWeight
        )
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [context.foregroundColor])
        let configuration = baseConfiguration.applying(colorConfiguration)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: context.foregroundColor,
        ]
        let textValue = NSAttributedString(string: text, attributes: attributes)
        let textSize = textValue.size()
        let reservedTextSize = NSAttributedString(string: reservedText, attributes: attributes).size()
        let symbolSize = symbol.map { metrics.compactSymbolSize(nativeSize: $0.size) } ?? .zero
        let reservedSymbolWidth = reservedSymbolNames.compactMap { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }.map { metrics.compactSymbolSize(nativeSize: $0.size).width }.max() ?? 0
        let width = MenuBarLayoutMetrics.contentInset * 2
            + ceil(max(symbolSize.width, reservedSymbolWidth, textSize.width, reservedTextSize.width))

        return makeImage(width: width, context: context) { rect in
            if let symbol {
                let symbolRect = NSRect(
                    x: floor((rect.width - symbolSize.width) / 2),
                    y: metrics.compactSymbolY(
                        for: symbolSize,
                        nativeSize: symbol.size,
                        alignmentRect: symbol.alignmentRect
                    ),
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbol.draw(in: symbolRect)
            }
            textValue.draw(
                at: NSPoint(
                    x: floor((rect.width - textSize.width) / 2),
                    y: metrics.compactRowY(1, textHeight: textSize.height)
                )
            )
        }
    }
}

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
        let width = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(max(0, images.count - 1))
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
        let width = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(max(0, images.count - 1))
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

@MainActor
private func makeImage(
    width: CGFloat,
    context: RenderContext,
    drawing: @escaping (NSRect) -> Void
) -> NSImage {
    let contentWidth = max(1, ceil(width))
    let spacing = max(0, context.horizontalSpacing)
    let image = NSImage(
        size: NSSize(width: contentWidth + spacing * 2, height: context.thickness),
        flipped: false
    ) { rect in
        drawing(NSRect(x: spacing, y: 0, width: contentWidth, height: rect.height))
        return true
    }
    image.isTemplate = context.isMonochrome
    return image
}

private extension MenuBarFontWeight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}
