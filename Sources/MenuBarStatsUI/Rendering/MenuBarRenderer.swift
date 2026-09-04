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

    /// Creates a render context.
    public init(
        thickness: CGFloat,
        appearance: MenuBarAppearance,
        palette: MenuBarPalette,
        fontSize: CGFloat,
        isMonochrome: Bool
    ) {
        self.thickness = thickness
        self.appearance = appearance
        self.palette = palette
        self.fontSize = fontSize
        self.isMonochrome = isMonochrome
    }

    /// Foreground color to use when drawing.
    public var foregroundColor: NSColor {
        isMonochrome ? .black : palette.color(for: appearance)
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
        makeImage(width: width, context: context) { rect in
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

/// Renders a small label above a value.
public struct StackedLabelRenderer: MenuBarRenderer {
    private let label: String
    private let value: String

    /// Creates a stacked label renderer.
    public init(label: String, value: String) {
        self.label = label
        self.value = value
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
        let width = ceil(max(labelText.size().width, valueText.size().width)) + 4
        return makeImage(width: width, context: context) { rect in
            let labelSize = labelText.size()
            let valueSize = valueText.size()
            labelText.draw(at: NSPoint(x: floor((rect.width - labelSize.width) / 2), y: rect.midY + 1))
            valueText.draw(at: NSPoint(x: floor((rect.width - valueSize.width) / 2), y: rect.midY - valueSize.height))
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
        let configuration = NSImage.SymbolConfiguration(pointSize: context.fontSize, weight: .medium)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: context.fontSize, weight: .medium),
            .foregroundColor: context.foregroundColor,
        ]
        let textValue = NSAttributedString(string: text, attributes: attributes)
        let symbolWidth: CGFloat = symbol == nil ? 0 : context.fontSize + 3
        let width = symbolWidth + ceil(textValue.size().width) + 4
        return makeImage(width: width, context: context) { rect in
            symbol?.draw(
                in: NSRect(
                    x: 2,
                    y: floor((rect.height - context.fontSize) / 2),
                    width: context.fontSize,
                    height: context.fontSize
                )
            )
            let size = textValue.size()
            textValue.draw(at: NSPoint(x: 2 + symbolWidth, y: floor((rect.height - size.height) / 2)))
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
        let gap: CGFloat = 6
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
    let image = NSImage(
        size: NSSize(width: max(1, ceil(width)), height: context.thickness),
        flipped: false
    ) { rect in
        drawing(rect)
        return true
    }
    image.isTemplate = context.isMonochrome
    return image
}
