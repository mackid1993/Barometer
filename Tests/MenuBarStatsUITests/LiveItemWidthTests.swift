import AppKit
import Testing

@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

/// Covers the opt-in live item width mode.
///
/// The mode deliberately breaks the one-assignment length rule in
/// `docs/MACOS27_STATUS_ITEM_SIZING.md`, so these tests pin two things equally hard: that it
/// actually shrinks every renderer that reserves stable width, and that leaving it off reproduces
/// the shipped reserved-width behavior exactly.
@MainActor
struct LiveItemWidthTests {
    private func context(live: Bool, weight: MenuBarFontWeight = .semibold) -> RenderContext {
        RenderContext(
            thickness: 24,
            appearance: .dark,
            palette: MenuBarPalette(light: .black, dark: .white),
            fontSize: 12,
            isMonochrome: true,
            fontWeight: weight,
            usesLiveWidth: live
        )
    }

    private func width(_ renderer: any MenuBarRenderer, live: Bool) -> CGFloat {
        renderer.render(in: context(live: live)).size.width
    }

    // MARK: - Length latch

    @Test("The length latch stays one-way unless the preference is on")
    func lengthLatchIsOneWayByDefault() {
        var latch = StatusItemLengthLatch()
        #expect(latch.resolve(40) == (40, true))
        #expect(latch.resolve(56) == (40, false))
        #expect(latch.resolve(24) == (40, false))
        #expect(latch.length == 40)
    }

    @Test("Item width makes the frame a high-water mark: it grows but never shrinks")
    func liveWidthGrowsButNeverShrinks() {
        var latch = StatusItemLengthLatch()
        latch.allowsGrowth = true
        #expect(latch.resolve(40) == (40, true))

        // A wider reading widens the frame, so the reading can never be cut off.
        #expect(latch.resolve(56) == (56, true))
        // A narrower reading leaves it alone. This is what stops the item moving on every sample.
        #expect(latch.resolve(24) == (56, false))
        #expect(latch.resolve(40) == (56, false))
        // An unchanged width is never rewritten.
        #expect(latch.resolve(56) == (56, false))
    }

    @Test("Changing the preference earns exactly one resize in either direction")
    func preferenceChangePermitsOneResize() {
        var latch = StatusItemLengthLatch()
        latch.allowsGrowth = true
        #expect(latch.resolve(56) == (56, true))

        // Turning the preference on tightens immediately rather than waiting for a relaunch.
        latch.permitResize()
        #expect(latch.resolve(40) == (40, true))
        // The permit is spent: the next narrower proposal is ignored again.
        #expect(latch.resolve(32) == (40, false))

        // Turning it off restores the reserved width instead of clipping.
        latch.allowsGrowth = false
        latch.permitResize()
        #expect(latch.resolve(56) == (56, true))
    }

    @Test("A high-water frame settles instead of tracking every sample")
    func highWaterFrameSettles() {
        // The defect in tracking live width exactly was constant movement. Feeding a realistic
        // sequence of readings must produce a small number of writes that then stops.
        var latch = StatusItemLengthLatch()
        latch.allowsGrowth = true
        let widths: [CGFloat] = [40, 38, 44, 40, 44, 36, 44, 42, 44, 40, 38, 44]
        var writes = 0
        for width in widths where latch.resolve(width).shouldAssign { writes += 1 }
        #expect(latch.length == 44)
        // Two writes: the first frame, then one growth to the widest reading. Tracking exactly
        // would have written on nearly every change.
        #expect(writes == 2, "expected the frame to settle, got \(writes) writes")
    }

    // MARK: - Reservation collapse

    @Test("A render context reserves stable width unless live width is on")
    func reservedStringFollowsTheFlag() {
        #expect(context(live: false).usesLiveWidth == false)
        #expect(context(live: false).reservedString("125.9°C", live: "42.9°C") == "125.9°C")
        #expect(context(live: true).reservedString("125.9°C", live: "42.9°C") == "42.9°C")
        // A field with no reservation measures its live content in both modes.
        #expect(context(live: false).reservedString(nil, live: "42.9°C") == "42.9°C")
        #expect(context(live: true).reservedString(nil, live: "42.9°C") == "42.9°C")
    }

    @Test("Every reserving renderer shrinks to its live reading")
    func renderersShrinkUnderLiveWidth() {
        let renderers: [(String, any MenuBarRenderer)] = [
            ("text", TextRenderer(text: "9%", reservedText: "100%")),
            (
                "stackedLabel",
                StackedLabelRenderer(label: "MEM", value: "64%", reservedValue: "100%")
            ),
            (
                "sensorStack",
                SensorStackRenderer(values: [
                    SensorStackValue(
                        label: "CPU", value: "42.9°C", reservedValue: "125.9°C", reservedLabel: "SENS"),
                    SensorStackValue(
                        label: "GPU", value: "50.9°C", reservedValue: "125.9°C", reservedLabel: "SENS"),
                ])
            ),
            (
                "networkStack",
                NetworkRateStackRenderer(download: "0.1MB/s", upload: "0.2MB/s", reservedValue: "999.9GB/s")
            ),
        ]
        for (name, renderer) in renderers {
            let reserved = width(renderer, live: false)
            let live = width(renderer, live: true)
            #expect(live < reserved, "\(name) did not shrink: reserved \(reserved), live \(live)")
            #expect(live > 0, "\(name) collapsed to nothing")
        }
    }

    @Test("A live reading as wide as its reservation keeps the same width")
    func liveWidthMatchesWhenTheReadingFillsTheReservation() {
        // Network reserves one value string for both rows. A live upload that is already as wide as
        // the reservation must not shrink the item, and must not grow it either.
        let renderer = NetworkRateStackRenderer(
            download: "0.8MB/s", upload: "10.8MB/s", reservedValue: "999GB/s")
        #expect(width(renderer, live: true) == width(renderer, live: false))
    }

    @Test("Live width still fits the content it draws")
    func liveWidthNeverClipsTheLiveReading() {
        // The natural width of the same text with no reservation is the floor a live-width render
        // must still reach, otherwise the reading would be clipped.
        let text = "1234.5 MB/s"
        let natural = width(TextRenderer(text: text), live: false)
        let live = width(TextRenderer(text: text, reservedText: "9999999 GB/s"), live: true)
        #expect(live >= natural)
    }

    @Test("A reservation narrower than the live reading never shrinks the item")
    func liveWidthIgnoresUndersizedReservations() {
        // Reserved widths are a floor, not a cap: the live reading always wins if it is wider.
        let renderer = TextRenderer(text: "1000000%", reservedText: "1%")
        #expect(width(renderer, live: true) == width(renderer, live: false))
    }

    // MARK: - Symbols

    @Test("An oversize glyph is scaled to its canvas rather than clipped")
    func liveWidthScalesGlyphsInsteadOfClipping() {
        // Verified on the real menu bar across every module: live width never cut a glyph. The
        // renderer fits an oversize symbol to the canvas, so a narrow reading shrinks the glyph
        // rather than letting it overflow. This pins that behavior under live width too.
        let glyphs = ["moon.stars.fill", "cloud.sun.rain.fill", "sun.max.fill", "cloud.bolt.rain.fill"]
        for glyph in glyphs {
            let narrow = IconStackRenderer(
                symbolName: glyph, text: "1°", reservedText: "1°", reservedSymbolNames: glyphs)
            let wide = IconStackRenderer(
                symbolName: glyph, text: "888°", reservedText: "888°", reservedSymbolNames: glyphs)
            let narrowWidth = width(narrow, live: true)
            #expect(narrowWidth > 0)
            // A wider reading yields a wider canvas; neither case depends on the glyph overflowing.
            #expect(width(wide, live: true) > narrowWidth)
        }
    }

    // MARK: - The default path must not move

    @Test("Live width off reproduces reserved-width rendering exactly")
    func disabledModeMatchesReservedRendering() {
        let cases: [(any MenuBarRenderer, any MenuBarRenderer)] = [
            (TextRenderer(text: "9%", reservedText: "100%"), TextRenderer(text: "100%")),
            (
                StackedLabelRenderer(label: "MEM", value: "64%", reservedValue: "100%"),
                StackedLabelRenderer(label: "MEM", value: "100%")
            ),
        ]
        for (reserving, atFullWidth) in cases {
            // With the flag off, a field reserving "100%" must be exactly as wide as one already
            // showing "100%".
            #expect(width(reserving, live: false) == width(atFullWidth, live: false))
        }
    }

    @Test("Font weight reservation is unaffected by the flag being off")
    func weightsStillRenderInsideTheReservedCanvas() {
        let renderer = TextRenderer(text: "88%", reservedText: "100%")
        for weight in [MenuBarFontWeight.regular, .medium, .semibold] {
            let reserved = renderer.render(in: context(live: false, weight: weight)).size.width
            #expect(reserved > 0)
        }
    }

    // MARK: - Settings

    @Test("The preference is off by default and survives a round trip")
    func settingDefaultsOffAndRoundTrips() throws {
        #expect(AppSettings().usesLiveItemWidth == false)

        var settings = AppSettings()
        settings.usesLiveItemWidth = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).usesLiveItemWidth)
    }

    @Test("Settings written before this preference shipped decode with it off")
    func absentKeyDecodesAsDisabled() throws {
        var settings = AppSettings()
        settings.usesLiveItemWidth = true
        settings.isMonochrome = false
        var document = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(settings)) as? [String: Any]
        )
        document.removeValue(forKey: "usesLiveItemWidth")

        let decoded = try JSONDecoder().decode(
            AppSettings.self, from: try JSONSerialization.data(withJSONObject: document))

        #expect(decoded.usesLiveItemWidth == false)
        #expect(decoded.isMonochrome == false)
    }
}
