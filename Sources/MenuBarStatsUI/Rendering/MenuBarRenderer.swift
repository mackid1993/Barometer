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

    /// Menu bar font size.
    public let fontSize: CGFloat

    /// Whether the result should be an adaptive template image.
    public let isMonochrome: Bool

    /// Scale applied to renderer widths and symbol sizes.
    public let scale: CGFloat

    /// Blank horizontal space added to each side of an item.
    public let horizontalSpacing: CGFloat

    /// Creates a render context.
    public init(
        thickness: CGFloat,
        appearance: MenuBarAppearance,
        palette: MenuBarPalette,
        fontSize: CGFloat,
        isMonochrome: Bool,
        scale: CGFloat = 1,
        horizontalSpacing: CGFloat = 0
    ) {
        self.thickness = thickness
        self.appearance = appearance
        self.palette = palette
        self.fontSize = fontSize
        self.isMonochrome = isMonochrome
        self.scale = scale
        self.horizontalSpacing = horizontalSpacing
    }

    /// Foreground color to use when drawing.
    public var foregroundColor: NSColor {
        isMonochrome ? .black : palette.color(for: appearance)
    }
}

/// Canonical geometry for every text-based menu bar renderer.
///
/// Keeping these calculations in one place prevents modules from acquiring subtly
/// different baselines, insets, and gaps as their renderers evolve.
struct MenuBarLayoutMetrics {
    static let contentInset: CGFloat = 2

    let context: RenderContext

    var iconTextGap: CGFloat {
        max(3, round(3.5 * context.scale))
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
            .font: NSFont.monospacedDigitSystemFont(ofSize: context.fontSize, weight: .medium),
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
        makeImage(width: width * context.scale, context: context) { rect in
            let drawingRect = rect.insetBy(dx: 2, dy: 3)
            let normalized = values.isEmpty ? [0] : values.map { min(1, max(0, $0)) }
            context.foregroundColor.setFill()
            context.foregroundColor.setStroke()

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
                color: context.foregroundColor,
                drawingRect: drawingRect
            )
            drawHalf(
                values: writes,
                baseline: centerY,
                extent: centerY - drawingRect.minY,
                direction: -1,
                color: context.foregroundColor.withAlphaComponent(0.62),
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
    private let value: String
    private let reservedValue: String?

    /// Creates a stacked label renderer.
    public init(label: String, value: String, reservedValue: String? = nil) {
        self.label = label
        self.value = value
        self.reservedValue = reservedValue
    }

    /// Renders the stacked image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(7, context.fontSize - 4), weight: .medium),
            .foregroundColor: context.foregroundColor,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(8, context.fontSize - 2), weight: .semibold),
            .foregroundColor: context.foregroundColor,
        ]
        let labelText = NSAttributedString(string: label, attributes: labelAttributes)
        let valueText = NSAttributedString(string: value, attributes: valueAttributes)
        let reservedText = NSAttributedString(string: reservedValue ?? value, attributes: valueAttributes)
        let metrics = MenuBarLayoutMetrics(context: context)
        let width = ceil(max(labelText.size().width, max(valueText.size().width, reservedText.size().width)))
            + MenuBarLayoutMetrics.contentInset * 2
        return makeImage(width: width, context: context) { rect in
            let labelSize = labelText.size()
            let valueSize = valueText.size()
            let origins = metrics.stackedOrigins(labelHeight: labelSize.height, valueHeight: valueSize.height)
            labelText.draw(at: origins.label)
            valueText.draw(at: origins.value)
        }
    }
}

/// Renders download and upload as two visually equal, stable-width rows.
public struct NetworkRateStackRenderer: MenuBarRenderer {
    private let download: String
    private let upload: String
    private let reservedValue: String

    /// Creates an equal two-row network renderer.
    public init(download: String, upload: String, reservedValue: String) {
        self.download = download
        self.upload = upload
        self.reservedValue = reservedValue
    }

    /// Renders matched arrow symbols and right-aligned values on a fixed canvas.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let pointSize = min(max(8, context.fontSize - 3), max(8, context.thickness / 2 - 2))
        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: context.foregroundColor,
        ]
        let downloadText = NSAttributedString(string: download, attributes: attributes)
        let uploadText = NSAttributedString(string: upload, attributes: attributes)
        let reservedWidth = ceil(NSAttributedString(string: reservedValue, attributes: attributes).size().width)
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize - 0.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [context.foregroundColor]))
        let downloadSymbol = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        let uploadSymbol = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        let symbolWidth = ceil(max(downloadSymbol?.size.width ?? 0, uploadSymbol?.size.width ?? 0))
        let symbolGap: CGFloat = 2
        let width = MenuBarLayoutMetrics.contentInset * 2 + symbolWidth + symbolGap + reservedWidth

        return makeImage(width: width, context: context) { rect in
            let rowHeight = rect.height / 2
            drawNetworkRow(
                symbol: downloadSymbol,
                value: downloadText,
                y: rowHeight,
                rowHeight: rowHeight,
                symbolWidth: symbolWidth,
                reservedWidth: reservedWidth,
                symbolGap: symbolGap
            )
            drawNetworkRow(
                symbol: uploadSymbol,
                value: uploadText,
                y: 0,
                rowHeight: rowHeight,
                symbolWidth: symbolWidth,
                reservedWidth: reservedWidth,
                symbolGap: symbolGap
            )
        }
    }

    @MainActor
    private func drawNetworkRow(
        symbol: NSImage?,
        value: NSAttributedString,
        y: CGFloat,
        rowHeight: CGFloat,
        symbolWidth: CGFloat,
        reservedWidth: CGFloat,
        symbolGap: CGFloat
    ) {
        let inset = MenuBarLayoutMetrics.contentInset
        if let symbol {
            let symbolOrigin = NSPoint(
                x: inset + floor((symbolWidth - symbol.size.width) / 2),
                y: y + floor((rowHeight - symbol.size.height) / 2)
            )
            symbol.draw(at: symbolOrigin, from: .zero, operation: .sourceOver, fraction: 1)
        }
        let valueSize = value.size()
        let valueX = inset + symbolWidth + symbolGap + reservedWidth - valueSize.width
        value.draw(at: NSPoint(x: valueX, y: y + floor((rowHeight - valueSize.height) / 2)))
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

    /// Renders two readings per column and expands horizontally for additional values.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let valuePointSize = min(max(8, context.fontSize - 3), max(8, context.thickness / 2 - 2))
        let labelPointSize = max(7, valuePointSize - 1)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: labelPointSize, weight: .medium),
            .foregroundColor: context.foregroundColor.withAlphaComponent(0.82),
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: valuePointSize, weight: .semibold),
            .foregroundColor: context.foregroundColor,
        ]
        let fields = values.isEmpty
            ? [SensorStackValue(label: "SENS", value: "—", reservedValue: "999.9°C")]
            : values
        let columns = stride(from: 0, to: fields.count, by: 2).map { start in
            Array(fields[start..<min(start + 2, fields.count)])
        }
        let labelGap: CGFloat = 3
        let columnGap: CGFloat = 5
        let columnWidths = columns.map { column in
            column.reduce(CGFloat(0)) { width, field in
                let labelWidth = NSAttributedString(string: field.label, attributes: labelAttributes).size().width
                let valueWidth = NSAttributedString(
                    string: field.reservedValue,
                    attributes: valueAttributes
                ).size().width
                return max(width, ceil(labelWidth + labelGap + valueWidth))
            }
        }
        let contentWidth = MenuBarLayoutMetrics.contentInset * 2
            + columnWidths.reduce(0, +)
            + columnGap * CGFloat(max(0, columns.count - 1))

        return makeImage(width: contentWidth, context: context) { rect in
            var x = MenuBarLayoutMetrics.contentInset
            let rowHeight = rect.height / 2
            for (columnIndex, column) in columns.enumerated() {
                let columnWidth = columnWidths[columnIndex]
                for (rowIndex, field) in column.enumerated() {
                    let label = NSAttributedString(string: field.label, attributes: labelAttributes)
                    let value = NSAttributedString(string: field.value, attributes: valueAttributes)
                    let combinedHeight = max(label.size().height, value.size().height)
                    let y: CGFloat
                    if fields.count == 1 {
                        y = floor((rect.height - combinedHeight) / 2)
                    } else {
                        let rowBottom = rowIndex == 0 ? rowHeight : 0
                        y = rowBottom + floor((rowHeight - combinedHeight) / 2)
                    }
                    label.draw(at: NSPoint(x: x, y: y))
                    value.draw(at: NSPoint(x: x + columnWidth - value.size().width, y: y))
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

    /// Creates an icon-and-text renderer.
    public init(symbolName: String, text: String) {
        self.symbolName = symbolName
        self.text = text
    }

    /// Renders the icon and text image.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: context.fontSize, weight: .medium)
        let symbolPointSize = min(context.fontSize * context.scale, context.thickness - 4)
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
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
        let metrics = MenuBarLayoutMetrics(context: context)
        let symbolSize = symbol.map { metrics.symbolSize(nativeSize: $0.size, font: font) } ?? .zero
        let gap = symbol == nil ? 0 : metrics.iconTextGap
        let width = MenuBarLayoutMetrics.contentInset * 2 + symbolSize.width + gap + ceil(textSize.width)
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
