import AppKit
import MenuBarStatsCore

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
        let font = context.font(ofSize: pointSize, weight: context.fontWeight.nsWeight, monospacedDigits: true)
        let symbolPointSize = max(pointSize, metrics.compactSymbolVisibleHeight * 1.3)
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
        // Size the glyph by its actual ink so the visible symbol, not its transparent
        // padding, follows the icon scale and never runs into the value row.
        let inkKey = "\(symbolName)|\(symbolPointSize)|\(context.fontWeight)"
        let placement = symbol.map {
            SymbolInkMeasurer.placement(of: $0, key: inkKey, visibleHeight: metrics.compactSymbolVisibleHeight)
        }
        let reservedSymbolWidth =
            reservedSymbolNames.compactMap { name -> CGFloat? in
                guard
                    let reservedImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                        .withSymbolConfiguration(configuration)
                else {
                    return nil
                }
                let reservedKey = "\(name)|\(symbolPointSize)|\(context.fontWeight)"
                return SymbolInkMeasurer.placement(
                    of: reservedImage,
                    key: reservedKey,
                    visibleHeight: metrics.compactSymbolVisibleHeight
                ).inkSize.width
            }.max() ?? 0
        // The canvas is sized by the reserved text and reserved symbols only, so a live
        // condition glyph can never change the status item's width. A glyph wider than
        // the canvas is scaled down to fit instead.
        let contentWidth = ceil(max(reservedSymbolWidth, textSize.width, reservedTextSize.width))
        let width = MenuBarLayoutMetrics.contentInset * 2 + contentWidth
        let fittedPlacement = placement.map { $0.fitted(toWidth: contentWidth) }

        return makeImage(width: width, context: context) { rect in
            if let symbol, let placement = fittedPlacement {
                let rowCenterY = context.thickness * 0.75
                let symbolRect = NSRect(
                    x: rect.width / 2 - placement.inkCenter.x,
                    y: rowCenterY - placement.inkCenter.y,
                    width: placement.boxSize.width,
                    height: placement.boxSize.height
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
