import AppKit
import MenuBarStatsCore

/// Draws the temperature as the weather mark itself, with the condition hugging the digits.
///
/// There is no container. The number is drawn as plain text at full size, and the condition lives
/// in the bands above and below it that a 22-point status item otherwise leaves empty: a cloud cap
/// rests on top of the digits, rain, snow, a bolt, or fog hangs underneath, a sunburst fans around
/// them, and a clear night tucks a crescent over the degree sign. The item is the digits plus two
/// points a side, so it weighs no more in the bar than a plain reading.
///
/// The set covers the same fourteen conditions as the system symbols, so the marks have to differ
/// in shape, never only in color: the wet family is told apart by how many strokes hang under the
/// cloud and how far they reach, sleet puts a flake between two strokes, a storm with rain flanks
/// the bolt with two strokes, and the sun or moon beside a partial cloud says whether it is day.
///
/// In monochrome mode everything is one template color. In color mode the digits take the
/// condition's color where the color carries meaning (amber for sun, lavender for night) and stay
/// in the module color otherwise, while the marks are tinted: gray cloud, blue rain, icy snow, a
/// yellow bolt.
public struct WeatherBadgeRenderer: MenuBarRenderer {
    private let condition: WeatherMenuBarCondition?
    private let text: String
    private let reservedText: String
    private let colorful: Bool

    /// Horizontal room either side of the digits for rays and the crescent.
    static let sidePadding: CGFloat = 2

    /// Creates a weather mark for one condition and reading.
    ///
    /// A nil condition draws the reading alone, for the moment before a forecast exists. It keeps
    /// the same width as a real mark so the item does not move when the weather arrives.
    ///
    /// `colorful` keeps the mark in color even when the menu bar is otherwise monochrome, so the
    /// weather can carry its splash of color without changing every other module.
    public init(condition: WeatherMenuBarCondition?, text: String, reservedText: String? = nil, colorful: Bool = false) {
        self.condition = condition
        self.text = text
        self.reservedText = reservedText ?? text
        self.colorful = colorful
    }

    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let font = context.font(ofSize: context.fontSize, weight: .semibold, monospacedDigits: true)
        let monochrome = context.isMonochrome && !colorful
        let palette = WeatherBadgePalette.resolve(
            condition, appearance: context.appearance, monochrome: monochrome,
            moduleColor: monochrome ? context.foregroundColor : Self.neutralDigits(for: context.appearance))
        let digits = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: palette.digits])
        let reserved = NSAttributedString(
            string: context.reservedString(reservedText, live: text), attributes: [.font: font])
        let textWidth = ceil(max(digits.size().width, reserved.size().width))
        let width = ceil(textWidth + Self.sidePadding * 2)
        let capHeight = font.capHeight

        let image = NSImage(size: NSSize(width: width, height: context.thickness), flipped: false) { rect in
            let size = digits.size()
            let origin = NSPoint(x: (rect.width - size.width) / 2, y: rect.midY - size.height / 2)
            // The box the marks are measured from: the digits' cap height, centered in the item.
            let box = NSRect(
                x: Self.sidePadding, y: rect.midY - capHeight / 2,
                width: rect.width - Self.sidePadding * 2, height: capHeight)

            palette.cloud.setFill()
            palette.cloud.setStroke()
            if let condition, condition != .clearDay, condition != .clearNight, condition != .unknown {
                let partial = condition == .partlyCloudy || condition == .partlyCloudyNight
                Self.cloudCap(box, trailingRoom: partial ? 6.5 : 0)
            }

            // The rain that shares a mark with something else goes down first, in its own color.
            palette.rain.setFill()
            palette.rain.setStroke()
            switch condition {
            case .sleet: Self.drops(box, at: [0.2, 0.8])
            case .thunderstorm: Self.drops(box, at: [0.12, 0.88])
            default: break
            }

            palette.mark.setFill()
            palette.mark.setStroke()
            switch condition {
            case nil: break
            case .clearDay: Self.rays(box)
            case .clearNight: Self.moon(box)
            case .partlyCloudy: Self.sunDisc(box)
            case .partlyCloudyNight: Self.cloudMoon(box)
            case .cloudy: break
            case .fog: Self.fogLines(box)
            case .drizzle: Self.drizzleTicks(box)
            case .rain: Self.drops(box, at: [0.24, 0.5, 0.76])
            case .heavyRain: Self.drops(box, at: [0.1, 0.37, 0.63, 0.9], reach: 1.2...5.4)
            case .sleet: Self.flakes(box, at: [0.5])
            case .snow: Self.flakes(box, at: [0.24, 0.5, 0.76])
            case .thunder, .thunderstorm: Self.bolt(box)
            case .unknown: Self.questionMark(box)
            }

            digits.draw(at: origin)
            return true
        }
        image.isTemplate = monochrome
        return image
    }

    /// Digit color for cloud-family marks when drawing in color over a monochrome bar.
    private static func neutralDigits(for appearance: MenuBarAppearance) -> NSColor {
        appearance == .dark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.12, alpha: 1)
    }

    // MARK: - Marks (all measured off the digits' cap box)

    /// A cloud resting on the digits: a low rounded bar with three puffs, the width of the number.
    private static func cloudCap(_ box: NSRect, trailingRoom: CGFloat) {
        let base = NSRect(x: box.minX, y: box.maxY + 1.2, width: box.width - trailingRoom, height: 1.8)
        let path = NSBezierPath(roundedRect: base, xRadius: 0.9, yRadius: 0.9)
        for (fraction, radius) in [(0.22, 2.2), (0.50, 2.9), (0.78, 2.3)] as [(CGFloat, CGFloat)] {
            let x = base.minX + base.width * fraction
            path.appendOval(in: NSRect(x: x - radius, y: base.maxY - radius * 0.55, width: radius * 2, height: radius * 2))
        }
        path.fill()
    }

    /// Short rays fanning off the top and bottom of the number.
    private static func rays(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        let center = NSPoint(x: box.midX, y: box.midY)
        for fraction in [0.06, 0.28, 0.5, 0.72, 0.94] as [CGFloat] {
            for edgeY in [box.maxY + 1.0, box.minY - 1.0] {
                let x = box.minX + box.width * fraction
                var direction = NSPoint(x: x - center.x, y: edgeY - center.y)
                let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
                direction.x /= length
                direction.y /= length
                path.move(to: NSPoint(x: x + direction.x * 0.8, y: edgeY + direction.y * 0.8))
                path.line(to: NSPoint(x: x + direction.x * 3.0, y: edgeY + direction.y * 3.0))
            }
        }
        path.stroke()
    }

    /// A crescent tucked over the degree sign.
    private static func moon(_ box: NSRect) {
        let r: CGFloat = 3.2
        let c = NSPoint(x: box.maxX - r + 0.6, y: box.maxY + r + 0.4)
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: NSRect(x: c.x - r + 2.0, y: c.y - r + 1.2, width: r * 2, height: r * 2)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// A sun disc peeking out beside the cloud cap.
    private static func sunDisc(_ box: NSRect) {
        let r: CGFloat = 2.5
        let c = NSPoint(x: box.maxX - r - 0.2, y: box.maxY + 3.6)
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        for degrees in stride(from: CGFloat(0), to: 360, by: 60) {
            let angle = degrees * .pi / 180
            path.move(to: NSPoint(x: c.x + cos(angle) * (r + 0.7), y: c.y + sin(angle) * (r + 0.7)))
            path.line(to: NSPoint(x: c.x + cos(angle) * (r + 1.9), y: c.y + sin(angle) * (r + 1.9)))
        }
        path.stroke()
    }

    /// A crescent peeking out beside the cloud cap, in the spot the day mark gives its sun.
    private static func cloudMoon(_ box: NSRect) {
        let r: CGFloat = 2.8
        let c = NSPoint(x: box.maxX - r + 0.2, y: box.maxY + 3.8)
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        // The bite is cut from everything drawn so far, so it stays inside the cap's trailing room:
        // its left edge is 3.6 points in from the box, the cap's last puff never reaches past 4.2.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: NSRect(x: c.x - r + 1.8, y: c.y - r + 1.1, width: r * 2, height: r * 2)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// Rain: slanted strokes hanging under the cloud, at the given fractions of the number's width.
    ///
    /// `reach` is how far below the digits a stroke starts and ends; the slant stays the same, so a
    /// longer reach is a longer stroke. Three at the default reach are rain, four at a longer one
    /// are heavy rain, and two make room for something between them.
    private static func drops(_ box: NSRect, at fractions: [CGFloat], reach: ClosedRange<CGFloat> = 1.6...4.8) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        let lean = (reach.upperBound - reach.lowerBound) * 0.2
        for fraction in fractions {
            let x = box.minX + box.width * fraction
            path.move(to: NSPoint(x: x + lean, y: box.minY - reach.lowerBound))
            path.line(to: NSPoint(x: x - lean, y: box.minY - reach.upperBound))
        }
        path.stroke()
    }

    /// Drizzle: five short ticks in two staggered rows, rain's slant with a third of its length.
    private static func drizzleTicks(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        let ticks: [(fraction: CGFloat, top: CGFloat)] = [
            (0.24, 1.6), (0.5, 1.6), (0.76, 1.6), (0.37, 3.9), (0.63, 3.9),
        ]
        for (fraction, top) in ticks {
            let x = box.minX + box.width * fraction
            path.move(to: NSPoint(x: x + 0.25, y: box.minY - top))
            path.line(to: NSPoint(x: x - 0.25, y: box.minY - top - 1.2))
        }
        path.stroke()
    }

    /// Snow: six-armed flakes under the cloud, at the given fractions of the number's width.
    private static func flakes(_ box: NSRect, at fractions: [CGFloat]) {
        let path = NSBezierPath()
        path.lineWidth = 1.0
        path.lineCapStyle = .round
        for fraction in fractions {
            let c = NSPoint(x: box.minX + box.width * fraction, y: box.minY - 3.4)
            for arm in 0..<3 {
                let angle = CGFloat(arm) * .pi / 3
                path.move(to: NSPoint(x: c.x - cos(angle) * 1.9, y: c.y - sin(angle) * 1.9))
                path.line(to: NSPoint(x: c.x + cos(angle) * 1.9, y: c.y + sin(angle) * 1.9))
            }
        }
        path.stroke()
    }

    private static func bolt(_ box: NSRect) {
        let c = NSPoint(x: box.midX, y: box.minY - 1.0)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c.x + 2.2, y: c.y))
        path.line(to: NSPoint(x: c.x - 0.8, y: c.y - 2.6))
        path.line(to: NSPoint(x: c.x + 0.8, y: c.y - 2.6))
        path.line(to: NSPoint(x: c.x - 2.0, y: c.y - 5.6))
        path.line(to: NSPoint(x: c.x - 1.0, y: c.y - 3.1))
        path.line(to: NSPoint(x: c.x - 2.6, y: c.y - 3.1))
        path.close()
        path.fill()
    }

    private static func fogLines(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        for (row, inset) in [(0, 1.0), (1, 3.5)] as [(Int, CGFloat)] {
            let y = box.minY - 2.0 - CGFloat(row) * 2.6
            path.move(to: NSPoint(x: box.minX + inset, y: y))
            path.line(to: NSPoint(x: box.maxX - inset, y: y))
        }
        path.stroke()
    }

    /// A question mark where the cloud would sit, for a code the forecast source has not named.
    ///
    /// Only the hook and the dot: at this size a stem between them closes the gap that makes it
    /// read as two parts, and the hook alone is enough of the letter.
    private static func questionMark(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        let r: CGFloat = 1.6
        let c = NSPoint(x: box.midX, y: box.maxY + 4.7)
        path.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: -90, clockwise: true)
        path.line(to: NSPoint(x: c.x, y: c.y - r - 0.4))
        path.stroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - 0.8, y: box.maxY + 0.4, width: 1.6, height: 1.6)).fill()
    }
}

/// Colors for one mark: the digits, the cloud cap, the condition detail, and the rain that shares
/// a mark with a bolt or a flake.
struct WeatherBadgePalette {
    let digits: NSColor
    let cloud: NSColor
    let mark: NSColor
    let rain: NSColor

    /// Resolves colors for the appearance, or a single template color for monochrome.
    static func resolve(
        _ condition: WeatherMenuBarCondition?, appearance: MenuBarAppearance, monochrome: Bool, moduleColor: NSColor
    ) -> WeatherBadgePalette {
        if monochrome {
            return WeatherBadgePalette(digits: .black, cloud: .black, mark: .black, rain: .black)
        }
        let dark = appearance == .dark
        let cloud = NSColor(hex: dark ? 0xC9CED6 : 0x8D96A3)
        let rain = NSColor(hex: dark ? 0x4DA3FF : 0x1F6FE0)
        let amber = NSColor(hex: dark ? 0xFFC53D : 0xA86E00)
        let night = NSColor(hex: dark ? 0xC7C4FF : 0x5B54C9)
        let ice = NSColor(hex: dark ? 0x8FD3FF : 0x2E86D6)
        let stormCloud = NSColor(hex: dark ? 0x9AA3B0 : 0x5F6873)
        let bolt = NSColor(hex: dark ? 0xFFD23F : 0xE5A800)
        switch condition {
        case nil, .cloudy, .fog, .unknown:
            return WeatherBadgePalette(digits: moduleColor, cloud: cloud, mark: cloud, rain: rain)
        case .clearDay:
            return WeatherBadgePalette(digits: amber, cloud: cloud, mark: amber, rain: rain)
        case .clearNight:
            return WeatherBadgePalette(digits: night, cloud: cloud, mark: night, rain: rain)
        case .partlyCloudy:
            return WeatherBadgePalette(digits: moduleColor, cloud: cloud, mark: amber, rain: rain)
        case .partlyCloudyNight:
            return WeatherBadgePalette(digits: moduleColor, cloud: cloud, mark: night, rain: rain)
        case .drizzle, .rain:
            return WeatherBadgePalette(digits: moduleColor, cloud: cloud, mark: rain, rain: rain)
        case .heavyRain:
            return WeatherBadgePalette(digits: moduleColor, cloud: stormCloud, mark: rain, rain: rain)
        case .sleet, .snow:
            return WeatherBadgePalette(digits: moduleColor, cloud: cloud, mark: ice, rain: rain)
        case .thunder, .thunderstorm:
            return WeatherBadgePalette(digits: moduleColor, cloud: stormCloud, mark: bolt, rain: rain)
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
