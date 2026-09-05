import AppKit
import MenuBarStatsCore

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
        let font = context.font(ofSize: context.fontSize, weight: context.fontWeight.nsWeight, monospacedDigits: true)
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
        // Every glyph is fitted to one square field measured by its ink, so the icon occupies the
        // same width whatever it is currently showing. Reserving the widest glyph instead left a
        // round symbol like sun.max sitting in a pocket of empty space, because it is far narrower
        // than cloud.sun once both are normalized to the same height, and the pocket changed size
        // with the weather. An SF Symbol's image box is not used at all: it carries transparent
        // optical padding that would reappear as unexplained space beside the value.
        let symbolField = metrics.inlineSymbolFieldSize
        let inkKey = "\(symbolName)|\(symbolPointSize)|\(context.fontWeight)|inline"
        let placement = symbol
            .map { SymbolInkMeasurer.placement(of: $0, key: inkKey, visibleHeight: symbolField) }
            .map { $0.fitted(toWidth: symbolField) }
        // A renderer that shows an icon keeps the gap even when the symbol fails to resolve, so one
        // missing glyph cannot change the item's width.
        let hasIcon = symbol != nil || !reservedSymbolNames.isEmpty
        let gap = hasIcon ? metrics.inlineIconTextGap : 0
        let symbolFieldWidth = hasIcon ? symbolField : 0
        let textFieldWidth = ceil(max(textSize.width, reservedTextSize.width))
        let width =
            MenuBarLayoutMetrics.contentInset * 2
            + symbolFieldWidth
            + gap
            + textFieldWidth
        // Centered on what is drawn: the glyph's ink, the gap, and the value. The remaining point
        // of asymmetry is the trailing side bearing of the degree sign, which cannot be removed
        // without moving the value closer to the icon than the rest of the bar's spacing.
        // The group is measured from the icon's fixed field, not from the current glyph's ink.
        // Ink widths differ between conditions, so measuring from them moved the whole item by a
        // point as the weather changed, which is worse than being a point off center.
        let groupWidth = symbolFieldWidth + gap + ceil(textSize.width)
        return makeImage(width: width, context: context) { rect in
            var x = MenuBarLayoutMetrics.contentInset
                + TextRenderer.centeringOffset(contentWidth: groupWidth, canvasWidth: rect.width)
            if let symbol, let placement {
                // Icon, gap, and value are laid out as one group against the leading edge, and the
                // canvas is sized for the worst case so all the spare width collects at the trailing
                // edge. Anything else puts the difference between this condition's glyph and the
                // widest one around the icon: a round symbol like sun.max is far narrower than
                // cloud.sun once both are normalized to the same height, so it would sit in a pocket
                // of empty space that changed size with the weather.
                let inkOrigin = x + (symbolFieldWidth - placement.inkSize.width) / 2
                let symbolRect = NSRect(
                    x: inkOrigin - (placement.inkCenter.x - placement.inkSize.width / 2),
                    y: rect.height / 2 - placement.inkCenter.y,
                    width: placement.boxSize.width,
                    height: placement.boxSize.height
                )
                symbol.draw(in: symbolRect)
            }
            if hasIcon {
                x += symbolFieldWidth + gap
            }
            textValue.draw(
                at: NSPoint(
                    // Against the icon, not against the trailing edge. Positioned by the string's
                    // advance rather than its ink: shifting by the left bearing centers the item
                    // one point better but visibly tightens the gap to the icon, which matters more.
                    x: x,
                    y: metrics.centeredY(for: textSize.height)
                )
            )
        }
    }
}
