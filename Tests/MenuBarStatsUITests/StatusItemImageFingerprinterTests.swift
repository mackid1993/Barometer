import AppKit
import Testing

@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@MainActor
struct StatusItemImageFingerprinterTests {
    private let context = RenderContext(
        thickness: 24,
        appearance: .dark,
        palette: MenuBarPalette(light: .black, dark: .white),
        fontSize: 12.65,
        isMonochrome: true,
        scale: 1.15,
        backingScaleFactor: 2
    )

    @Test
    func identicalRendersShareAFingerprint() {
        var fingerprinter = StatusItemImageFingerprinter()
        let first = GraphRenderer(values: [0.2, 0.8, 0.4], style: .line).render(in: context)
        let second = GraphRenderer(values: [0.2, 0.8, 0.4], style: .line).render(in: context)

        let firstFingerprint = fingerprinter.fingerprint(of: first, backingScaleFactor: 2)
        let secondFingerprint = fingerprinter.fingerprint(of: second, backingScaleFactor: 2)

        #expect(firstFingerprint != nil)
        #expect(firstFingerprint == secondFingerprint)
    }

    @Test
    func changedHistoryWindowChangesTheFingerprint() {
        var fingerprinter = StatusItemImageFingerprinter()
        let older = GraphRenderer(values: [0.2, 0.8, 0.4], style: .line).render(in: context)
        let newer = GraphRenderer(values: [0.8, 0.4, 0.6], style: .line).render(in: context)

        let olderFingerprint = fingerprinter.fingerprint(of: older, backingScaleFactor: 2)
        let newerFingerprint = fingerprinter.fingerprint(of: newer, backingScaleFactor: 2)

        #expect(olderFingerprint != nil)
        #expect(newerFingerprint != nil)
        #expect(olderFingerprint != newerFingerprint)
    }

    @Test
    func framedImagesReuseOneBitmapAcrossUpdates() {
        var fingerprinter = StatusItemImageFingerprinter()
        let graph = GraphRenderer(values: [0.2, 0.8, 0.4], style: .line).render(in: context)
        let framed = StatusItemRendering.image(graph, framedTo: 64)
        let unframed = StatusItemRendering.image(graph, framedTo: graph.size.width)

        let framedFingerprint = fingerprinter.fingerprint(of: framed, backingScaleFactor: 2)
        let repeated = fingerprinter.fingerprint(of: framed, backingScaleFactor: 2)
        let unframedFingerprint = fingerprinter.fingerprint(of: unframed, backingScaleFactor: 2)

        #expect(framedFingerprint == repeated)
        #expect(framedFingerprint != unframedFingerprint)
    }
}
