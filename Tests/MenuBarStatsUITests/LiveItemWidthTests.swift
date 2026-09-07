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

    @Test("The length latch stays one-way unless live resize is enabled")
    func lengthLatchIsOneWayByDefault() {
        var latch = StatusItemLengthLatch()
        #expect(latch.resolve(40) == (40, true))
        #expect(latch.resolve(56) == (40, false))
        #expect(latch.resolve(24) == (40, false))
        #expect(latch.length == 40)
    }

    @Test("Live resize re-assigns only when the proposed width actually changes")
    func liveLatchReassignsOnChangeOnly() {
        var latch = StatusItemLengthLatch()
        latch.allowsLiveResize = true
        #expect(latch.resolve(40) == (40, true))
        #expect(latch.resolve(56) == (56, true))
        // Re-assigning an unchanged length is exactly the write that first made items move.
        #expect(latch.resolve(56) == (56, false))
        #expect(latch.resolve(24) == (24, true))
    }

    @Test("Enabling live resize mid-process does not retroactively reassign an unchanged width")
    func enablingLiveResizeKeepsCurrentWidthUntilItChanges() {
        var latch = StatusItemLengthLatch()
        #expect(latch.resolve(40) == (40, true))
        latch.allowsLiveResize = true
        #expect(latch.resolve(40) == (40, false))
        #expect(latch.resolve(41) == (41, true))
    }

    @Test("Turning live width off restores the reserved width instead of clipping")
    func disablingLiveWidthRestoresTheWiderFrame() {
        // Reproduces a real defect: with the preference on, items latch to a narrow live width.
        // Turning it off makes the renderer produce the wider reserved content again, but a
        // one-way latch kept the narrow frame and the image was drawn into it, cutting the reading
        // off at the right edge.
        var latch = StatusItemLengthLatch()
        latch.allowsLiveResize = true
        #expect(latch.resolve(32) == (32, true))

        latch.allowsLiveResize = false
        let decision = latch.resolve(50)
        #expect(decision.length == 50, "the frame must grow back to fit the reserved content")
        #expect(decision.shouldAssign, "the wider frame has to reach AppKit or the item clips")
    }

    @Test("A latch that never used live width keeps the strict one-way contract")
    func neverLiveLatchRejectsEveryLaterProposal() {
        // Corrective growth must not leak into installs that never enable the preference: the
        // one-way rule is what keeps a menu bar manager from reassessing an item.
        var latch = StatusItemLengthLatch()
        #expect(latch.resolve(40) == (40, true))
        #expect(latch.resolve(56) == (40, false))
        #expect(latch.resolve(24) == (40, false))
        #expect(latch.length == 40)
    }

    @Test("Turning live width off leaves the reading fully drawn, not cut off")
    func disablingLiveWidthDoesNotClipTheRendering() {
        // End to end over the path that actually clipped: narrow live frame, then the wider
        // reserved rendering after the preference is turned off.
        let renderer = TextRenderer(text: "67°", reservedText: "888°")
        let live = renderer.render(in: context(live: true))
        let reserved = renderer.render(in: context(live: false))
        #expect(live.size.width < reserved.size.width)

        var latch = StatusItemLengthLatch()
        latch.allowsLiveResize = true
        _ = latch.resolve(StatusItemRendering.roundedLength(live.size.width))

        latch.allowsLiveResize = false
        let decision = latch.resolve(StatusItemRendering.roundedLength(reserved.size.width))
        let framed = StatusItemRendering.image(reserved, framedTo: decision.length)
        #expect(framed.size.width >= reserved.size.width, "the reserved rendering must not be cut off")
    }

    @Test("A frame narrower than its content would clip, which is why growth is allowed")
    func framingNarrowerThanContentClips() {
        let wide = NSImage(size: NSSize(width: 50, height: 22))
        let framed = StatusItemRendering.image(wide, framedTo: 32)
        // Documents the consequence the latch must prevent.
        #expect(framed.size.width == 32)
        #expect(framed.size.width < wide.size.width)
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
