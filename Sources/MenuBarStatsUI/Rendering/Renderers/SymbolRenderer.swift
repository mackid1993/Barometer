import AppKit
import MenuBarStatsCore

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
        let font = context.font(ofSize: context.fontSize, weight: context.fontWeight.nsWeight, monospacedDigits: false)
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
