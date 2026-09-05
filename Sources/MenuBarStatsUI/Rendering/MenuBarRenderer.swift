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

    /// Number of device pixels represented by one logical point.
    public let backingScaleFactor: CGFloat

    /// Shared graph opacity and type weight.
    public let graphOpacity: CGFloat
    public let fontWeight: MenuBarFontWeight

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
        backingScaleFactor: CGFloat = 2,
        graphOpacity: CGFloat = 0.85,
        fontWeight: MenuBarFontWeight = .medium
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
        self.backingScaleFactor = max(1, backingScaleFactor)
        self.graphOpacity = min(1, max(0.1, graphOpacity))
        self.fontWeight = fontWeight
    }

    /// Text font for menu bar renderers.
    ///
    /// Digits remain tabular so live values never shift their neighbors.
    public func font(ofSize pointSize: CGFloat, weight: NSFont.Weight, monospacedDigits: Bool) -> NSFont {
        monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weight)
            : NSFont.systemFont(ofSize: pointSize, weight: weight)
    }

    /// The font size setting that reproduces the original two-row grid exactly.
    public static let referenceFontSize: CGFloat = 12

    /// The icon and graph scale setting that reproduces the original symbol sizes exactly.
    public static let referenceScale: CGFloat = 1.15

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
    /// Status-item canvases are already separated by the system-wide menu bar spacing.
    /// Adding another inset here makes every independently movable Barometer item look
    /// farther apart, even when their AppKit frames are contiguous.
    static let contentInset: CGFloat = 0

    /// Alpha applied to descriptive labels (CPU, MEM, sensor names) so values stand out.
    static let labelEmphasis: CGFloat = 0.82

    let context: RenderContext

    var iconTextGap: CGFloat {
        max(3, round(3.5 * context.scale))
    }

    /// Visible separation between a glyph and the value beside it.
    ///
    /// Every other multi-part item ends up with five points of blank space between its label and
    /// its value: `densePairGap` plus the side bearing the label's last glyph carries. This
    /// renderer positions the icon by its measured ink, which has no bearing to contribute, so the
    /// constant has to be the visible gap itself for the spacing to match the rest of the bar.
    var inlineIconTextGap: CGFloat {
        densePairGap + 2
    }

    /// Side of the square field every inline glyph is fitted into.
    ///
    /// One field for every symbol means the icon never changes width, so nothing has to be reserved
    /// for the widest one and no empty pocket forms around a narrow glyph.
    var inlineSymbolFieldSize: CGFloat {
        min(context.thickness - 6, max(12, round(context.fontSize * 1.35)))
    }

    /// Dense blocks use the same edge contract as every other status-item renderer.
    var denseTextPadding: CGFloat {
        0
    }

    /// Minimal separator between independently configured sensor columns.
    var sensorColumnGap: CGFloat {
        oneDevicePixel
    }

    /// One physical pixel at the destination display's backing scale.
    var oneDevicePixel: CGFloat {
        1 / context.backingScaleFactor
    }

    /// Smallest prefix/value gap that remains optically visible after AppKit antialiasing.
    var densePairGap: CGFloat {
        3
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

    /// Point size shared by every two-row renderer.
    ///
    /// The default 12 pt font maps onto the same compact size the two-row grid always used
    /// (half the bar minus two points), and the size scales proportionally from there in
    /// half-point steps. The result is capped at the largest size whose two rows of glyph
    /// ink still fit inside the menu bar, so the setting has a visible effect without any
    /// row ever leaving its half of the bar.
    var compactPointSize: CGFloat {
        let defaultCompactSize = max(8, context.thickness / 2 - 2)
        let proportional = defaultCompactSize * context.fontSize / RenderContext.referenceFontSize
        let rounded = (proportional * 2).rounded() / 2
        return min(max(8, rounded), Self.maximumCompactPointSize(thickness: context.thickness))
    }

    /// Largest two-row point size whose glyph ink fits the bar with a one-point gap.
    ///
    /// Measured SF metrics: cap height is about 0.705 of the point size and the descender
    /// about 0.21, so one row of digits and capitals needs about 0.915 points of ink per
    /// point of font size. Two rows plus the gap must fit inside the thickness.
    static func maximumCompactPointSize(thickness: CGFloat) -> CGFloat {
        let raw = (thickness - 1) / 1.83
        return max(8, floor(raw * 2) / 2)
    }

    func compactRowY(_ row: Int, textHeight: CGFloat) -> CGFloat {
        let rowHeight = context.thickness / 2
        let rowBottom = row == 0 ? rowHeight : 0
        return rowBottom + floor((rowHeight - textHeight) / 2)
    }

    /// Drawn size of a symbol that shares the top row with a compact value.
    ///
    /// At the production default scale the symbol fills the row minus one point, exactly
    /// as before. Below that it shrinks proportionally, and above it grows by up to half a
    /// point past the row so the slider has a visible effect without touching the value row.
    func compactSymbolSize(nativeSize: NSSize) -> NSSize {
        let targetHeight = compactSymbolVisibleHeight
        let aspectRatio = max(0.5, nativeSize.width / max(1, nativeSize.height))
        return NSSize(width: ceil(targetHeight * aspectRatio), height: targetHeight)
    }

    /// Height of the visible glyph (the symbol's alignment rect) in the top row.
    ///
    /// SF Symbol images carry transparent optical padding, so sizing the image box alone
    /// leaves the visible glyph well short of the row. This targets the glyph itself: it
    /// fills the row at the top of the slider and shrinks to about half the row at the bottom.
    var compactSymbolVisibleHeight: CGFloat {
        let rowHeight = context.thickness / 2
        let unscaledHeight = (rowHeight - 1) / RenderContext.referenceScale
        return min(rowHeight - 0.5, max(5.5, unscaledHeight * context.scale))
    }

    /// Image box whose alignment rect matches `compactSymbolVisibleHeight`.
    func compactSymbolSize(nativeSize: NSSize, alignmentRect: NSRect) -> NSSize {
        let visibleNative =
            alignmentRect.height > 0 && alignmentRect.height <= nativeSize.height
            ? alignmentRect.height
            : nativeSize.height
        let ratio = compactSymbolVisibleHeight / max(1, visibleNative)
        let height = min(context.thickness / 2 * 1.7, nativeSize.height * ratio)
        let aspectRatio = max(0.5, nativeSize.width / max(1, nativeSize.height))
        return NSSize(width: ceil(height * aspectRatio), height: height)
    }

    /// Vertical inset for menu bar graphs; larger scales draw taller graphs.
    func graphVerticalInset(default defaultInset: CGFloat) -> CGFloat {
        let inset = (defaultInset + (RenderContext.referenceScale - context.scale) * 8).rounded()
        return min(6, max(1, inset))
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

/// Builds a template-aware menu bar image of the context thickness and draws drawing into it.
@MainActor
func makeImage(
    width: CGFloat,
    context: RenderContext,
    drawing: @escaping (NSRect) -> Void
) -> NSImage {
    let contentWidth = max(1, ceil(width))
    let image = NSImage(
        size: NSSize(width: contentWidth, height: context.thickness),
        flipped: false
    ) { rect in
        drawing(NSRect(x: 0, y: 0, width: contentWidth, height: rect.height))
        return true
    }
    image.isTemplate = context.isMonochrome
    return image
}

extension MenuBarFontWeight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}
