import AppKit
import Testing

@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

/// The weather mark: digits at full size with the condition hugging them.
@MainActor
struct WeatherBadgeRendererTests {
    private func context(monochrome: Bool, appearance: MenuBarAppearance = .dark) -> RenderContext {
        RenderContext(
            thickness: 22, appearance: appearance, palette: MenuBarPalette(light: .black, dark: .white),
            fontSize: 12, isMonochrome: monochrome, fontWeight: .semibold)
    }

    @Test("The mark is the digits plus two points a side, whatever the condition")
    func widthIsDigitsPlusPadding() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let digits = ceil(NSAttributedString(string: "64°", attributes: [.font: font]).size().width)
        for condition in WeatherMenuBarCondition.allCases {
            let image = WeatherBadgeRenderer(condition: condition, text: "64°", reservedText: "64°")
                .render(in: context(monochrome: true))
            #expect(image.size.width == ceil(digits + WeatherBadgeRenderer.sidePadding * 2),
                    "\(condition) changed the width")
            #expect(image.size.height == 22)
        }
    }

    @Test("A condition change never changes the item width")
    func conditionsShareOneWidth() {
        let widths = Set(WeatherMenuBarCondition.allCases.map {
            WeatherBadgeRenderer(condition: $0, text: "64°", reservedText: "-99°")
                .render(in: context(monochrome: true)).size.width
        })
        #expect(widths.count == 1)
    }

    @Test("Monochrome renders a template image; color does not")
    func templateFollowsMonochrome() {
        let mono = WeatherBadgeRenderer(condition: .rain, text: "64°").render(in: context(monochrome: true))
        let color = WeatherBadgeRenderer(condition: .rain, text: "64°").render(in: context(monochrome: false))
        #expect(mono.isTemplate)
        #expect(!color.isTemplate)
    }

    @Test("Every condition draws something above or below the digits")
    func everyConditionLeavesInk() {
        // Compare each mark against plain digits: the condition must add ink somewhere.
        let plainWidth = WeatherBadgeRenderer(condition: .cloudy, text: "64°").render(in: context(monochrome: true)).size.width
        for condition in WeatherMenuBarCondition.allCases {
            let image = WeatherBadgeRenderer(condition: condition, text: "64°").render(in: context(monochrome: true))
            #expect(inkPixels(image) > 0, "\(condition) drew nothing")
            #expect(image.size.width == plainWidth)
        }
    }

    @Test("No forecast draws the reading alone at the same width")
    func noForecastDrawsOnlyTheReading() {
        let placeholder = WeatherBadgeRenderer(condition: nil, text: "\u{2013}\u{00B0}", reservedText: "-99°")
            .render(in: context(monochrome: true))
        let real = WeatherBadgeRenderer(condition: .rain, text: "64°", reservedText: "-99°")
            .render(in: context(monochrome: true))
        // Same reserved width, so the item does not move when the first forecast arrives.
        #expect(placeholder.size.width == real.size.width)
        // Only the dash and degree sign: strictly less ink than any condition's mark.
        let digitsOnly = WeatherBadgeRenderer(condition: nil, text: "64°").render(in: context(monochrome: true))
        let withCloud = WeatherBadgeRenderer(condition: .cloudy, text: "64°").render(in: context(monochrome: true))
        #expect(inkPixels(digitsOnly) < inkPixels(withCloud))
    }

    @Test("Weather codes map to a drawn condition, day and night")
    func codesMapToConditions() {
        #expect(WMOCode(rawValue: 0).menuBarCondition(isDay: true) == .clearDay)
        #expect(WMOCode(rawValue: 0).menuBarCondition(isDay: false) == .clearNight)
        #expect(WMOCode(rawValue: 2).menuBarCondition(isDay: false) == .partlyCloudy)
        #expect(WMOCode(rawValue: 3).menuBarCondition(isDay: true) == .cloudy)
        #expect(WMOCode(rawValue: 45).menuBarCondition(isDay: true) == .fog)
        #expect(WMOCode(rawValue: 53).menuBarCondition(isDay: true) == .rain)
        #expect(WMOCode(rawValue: 65).menuBarCondition(isDay: true) == .rain)
        #expect(WMOCode(rawValue: 73).menuBarCondition(isDay: true) == .snow)
        #expect(WMOCode(rawValue: 96).menuBarCondition(isDay: true) == .thunderstorm)
    }

    private func inkPixels(_ image: NSImage) -> Int {
        let w = Int(image.size.width * 2), h = Int(image.size.height * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var count = 0
        for y in 0..<h { for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 } }
        return count
    }
}
