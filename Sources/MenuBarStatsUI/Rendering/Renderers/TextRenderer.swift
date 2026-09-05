import AppKit
import MenuBarStatsCore

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
            .font: context.font(ofSize: context.fontSize, weight: context.fontWeight.nsWeight, monospacedDigits: true),
            .foregroundColor: context.foregroundColor,
        ]
        let value = NSAttributedString(string: text, attributes: attributes)
        let reserved = NSAttributedString(string: reservedText ?? text, attributes: attributes)
        let width = ceil(max(value.size().width, reserved.size().width))
        return makeImage(width: width, context: context) { rect in
            let size = value.size()
            value.draw(
                at: NSPoint(
                    x: Self.centeringOffset(contentWidth: size.width, canvasWidth: rect.width),
                    y: floor((rect.height - size.height) / 2)
                )
            )
        }
    }

    /// Keeps a changing reading adjacent to the following status-item frame.
    /// Leading offset that centers live content inside a canvas sized for the reserved value.
    ///
    /// A canvas is as wide as the widest value an item can ever show, so a shorter live value leaves
    /// spare width. Pinning content to either edge collects all of it on the other side, and the
    /// hover highlight covers the whole item, so the highlight then reads as offset from what it is
    /// highlighting. Renderers disagreed about which edge to pin to, which made it worse.
    static func centeringOffset(contentWidth: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        max(0, ((canvasWidth - contentWidth) / 2).rounded(.down))
    }
}
