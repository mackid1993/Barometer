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

    @Test("A condition change never changes the item width, in any appearance or style")
    func conditionsShareOneWidth() {
        for monochrome in [true, false] {
            for appearance in [MenuBarAppearance.dark, .light] {
                let widths = Set(WeatherMenuBarCondition.allCases.map {
                    WeatherBadgeRenderer(condition: $0, text: "64°", reservedText: "-99°")
                        .render(in: context(monochrome: monochrome, appearance: appearance)).size.width
                })
                #expect(widths.count == 1, "monochrome \(monochrome), \(appearance)")
            }
        }
    }

    @Test("Monochrome renders a template image for every condition; color never does")
    func templateFollowsMonochrome() {
        for condition in WeatherMenuBarCondition.allCases {
            let mono = WeatherBadgeRenderer(condition: condition, text: "64°").render(in: context(monochrome: true))
            let color = WeatherBadgeRenderer(condition: condition, text: "64°").render(in: context(monochrome: false))
            #expect(mono.isTemplate, "\(condition)")
            #expect(!color.isTemplate, "\(condition)")
        }
    }

    @Test("Flattened to one template color, no two conditions draw the same mark")
    func conditionsDifferInShape() {
        // Monochrome throws away every color difference, so the marks have to differ in shape.
        var masks: [WeatherMenuBarCondition: [Bool]] = [:]
        for condition in WeatherMenuBarCondition.allCases {
            masks[condition] = inkMask(
                WeatherBadgeRenderer(condition: condition, text: "64°").render(in: context(monochrome: true)))
        }
        for (a, aMask) in masks {
            for (b, bMask) in masks where a != b {
                #expect(aMask != bMask, "\(a) and \(b) draw the same mark")
            }
        }
    }

    @Test("The wet family is told apart by how much hangs under the cloud")
    func wetFamilyOrdersByInk() {
        func ink(_ condition: WeatherMenuBarCondition) -> Int {
            inkPixels(
                WeatherBadgeRenderer(condition: condition, text: "64°").render(in: context(monochrome: true)))
        }
        // Drizzle's ticks are shorter than rain's strokes, and heavy rain has one more, longer stroke.
        #expect(ink(.drizzle) < ink(.rain))
        #expect(ink(.rain) < ink(.heavyRain))
        // A storm with rain is the dry storm's bolt plus two strokes.
        #expect(ink(.thunder) < ink(.thunderstorm))
        // Sleet keeps a flake between its strokes, so it carries more than two strokes alone would.
        #expect(ink(.sleet) > ink(.cloudy))
    }

    @Test("The drawn set covers exactly the symbols the system style reserves")
    func drawnSetMatchesSystemSymbols() {
        let drawn = Set(WeatherMenuBarCondition.allCases.map(\.symbolName))
        #expect(drawn == Set(WeatherPresentationFormatter.menuBarSymbolNames))
        #expect(drawn.count == WeatherMenuBarCondition.allCases.count, "two conditions share a symbol")
        // Every code the source can send resolves to the same symbol by either route.
        for code in 0...99 {
            for isDay in [true, false] {
                let wmo = WMOCode(rawValue: code)
                #expect(wmo.symbolName(isDay: isDay) == wmo.menuBarCondition(isDay: isDay).symbolName)
            }
        }
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
        #expect(WMOCode(rawValue: 1).menuBarCondition(isDay: true) == .partlyCloudy)
        #expect(WMOCode(rawValue: 2).menuBarCondition(isDay: false) == .partlyCloudyNight)
        #expect(WMOCode(rawValue: 3).menuBarCondition(isDay: true) == .cloudy)
        #expect(WMOCode(rawValue: 3).menuBarCondition(isDay: false) == .cloudy)
        #expect(WMOCode(rawValue: 45).menuBarCondition(isDay: true) == .fog)
        #expect(WMOCode(rawValue: 48).menuBarCondition(isDay: false) == .fog)
        #expect(WMOCode(rawValue: 51).menuBarCondition(isDay: true) == .drizzle)
        #expect(WMOCode(rawValue: 57).menuBarCondition(isDay: true) == .drizzle)
        #expect(WMOCode(rawValue: 61).menuBarCondition(isDay: true) == .rain)
        #expect(WMOCode(rawValue: 63).menuBarCondition(isDay: false) == .rain)
        #expect(WMOCode(rawValue: 65).menuBarCondition(isDay: true) == .heavyRain)
        #expect(WMOCode(rawValue: 80).menuBarCondition(isDay: true) == .heavyRain)
        #expect(WMOCode(rawValue: 82).menuBarCondition(isDay: true) == .heavyRain)
        #expect(WMOCode(rawValue: 66).menuBarCondition(isDay: true) == .sleet)
        #expect(WMOCode(rawValue: 67).menuBarCondition(isDay: false) == .sleet)
        #expect(WMOCode(rawValue: 71).menuBarCondition(isDay: true) == .snow)
        #expect(WMOCode(rawValue: 77).menuBarCondition(isDay: true) == .snow)
        #expect(WMOCode(rawValue: 86).menuBarCondition(isDay: true) == .snow)
        #expect(WMOCode(rawValue: 95).menuBarCondition(isDay: true) == .thunder)
        #expect(WMOCode(rawValue: 96).menuBarCondition(isDay: true) == .thunderstorm)
        #expect(WMOCode(rawValue: 99).menuBarCondition(isDay: false) == .thunderstorm)
        #expect(WMOCode(rawValue: 42).menuBarCondition(isDay: true) == .unknown)
        #expect(WMOCode(rawValue: -1).menuBarCondition(isDay: true) == .unknown)
    }

    private func inkPixels(_ image: NSImage) -> Int {
        inkMask(image).filter { $0 }.count
    }

    /// Which pixels carry ink, rendered at the Retina scale the menu bar uses.
    private func inkMask(_ image: NSImage) -> [Bool] {
        let w = Int(image.size.width * 2), h = Int(image.size.height * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var mask: [Bool] = []
        mask.reserveCapacity(w * h)
        for y in 0..<h { for x in 0..<w { mask.append((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5) } }
        return mask
    }
}
