import AppKit
import MenuBarStatsCore

@MainActor
/// Measures the opaque bounds of symbol images so stacked glyphs can be sized by their ink.
enum SymbolInkMeasurer {
    struct Placement {
        /// Size of the full image box after scaling.
        let boxSize: NSSize
        /// Size of the visible ink after scaling.
        let inkSize: NSSize
        /// Center of the visible ink relative to the box origin, after scaling.
        let inkCenter: NSPoint

        /// Scales the placement down so the ink is no wider than width.
        func fitted(toWidth width: CGFloat) -> Placement {
            guard inkSize.width > width, inkSize.width > 0 else {
                return self
            }
            let factor = width / inkSize.width
            return Placement(
                boxSize: NSSize(width: boxSize.width * factor, height: boxSize.height * factor),
                inkSize: NSSize(width: inkSize.width * factor, height: inkSize.height * factor),
                inkCenter: NSPoint(x: inkCenter.x * factor, y: inkCenter.y * factor)
            )
        }
    }

    private static var cache: [String: NSRect] = [:]

    /// Scales image so its visible ink is visibleHeight tall and reports where that ink sits.
    static func placement(of image: NSImage, key: String, visibleHeight: CGFloat) -> Placement {
        let ink = inkRect(of: image, key: key)
        let factor = visibleHeight / max(1, ink.height)
        return Placement(
            boxSize: NSSize(width: image.size.width * factor, height: image.size.height * factor),
            inkSize: NSSize(width: ink.width * factor, height: ink.height * factor),
            inkCenter: NSPoint(x: ink.midX * factor, y: ink.midY * factor)
        )
    }

    /// Opaque bounds of image in its own point coordinates (origin at the bottom left).
    static func inkRect(of image: NSImage, key: String) -> NSRect {
        if let cached = cache[key] {
            return cached
        }
        let size = image.size
        let scale: CGFloat = 4
        let pixelWidth = Int(ceil(size.width * scale))
        let pixelHeight = Int(ceil(size.height * scale))
        let fallback = image.alignmentRect.isEmpty ? NSRect(origin: .zero, size: size) : image.alignmentRect
        guard pixelWidth > 0, pixelHeight > 0,
            let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            return fallback
        }
        // The context's user space follows the representation's point size, so set it
        // before creating the context; otherwise drawing lands in a quarter of the bitmap.
        representation.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return fallback
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.bitmapData else {
            return fallback
        }
        let bytesPerRow = representation.bytesPerRow
        let samples = representation.samplesPerPixel
        var minX = pixelWidth
        var minY = pixelHeight
        var maxX = -1
        var maxY = -1
        for row in 0..<pixelHeight {
            for column in 0..<pixelWidth {
                let alpha = data[row * bytesPerRow + column * samples + 3]
                guard alpha > 24 else { continue }
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return fallback
        }
        // Bitmap rows run top-down; convert to AppKit's bottom-left origin.
        let rect = NSRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(pixelHeight - 1 - maxY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
        cache[key] = rect
        return rect
    }
}
