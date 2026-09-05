import AppKit
import Darwin
import MenuBarStatsCore
import Testing
@testable import MenuBarStatsUI

@Suite("Update offer window")
@MainActor
struct UpdateOfferWindowControllerTests {
    @Test("Release notes use a modeless native scrolling window with both download paths")
    func modelessOffer() throws {
        let release = UpdateRelease(
            version: try #require(ReleaseVersion("1.0.4")),
            notes: "# Barometer 1.0.4\n\n- Smooth release notes",
            asset: UpdateAsset(
                name: "Barometer-1.0.4.dmg",
                downloadURL: try #require(
                    URL(string: "https://github.com/mackid1993/Barometer/releases/download/v1.0.4/Barometer-1.0.4.dmg")
                ),
                sha256: String(repeating: "a", count: 64)
            )
        )
        let controller = UpdateOfferWindowController(release: release) { _ in }
        let window = try #require(controller.window)
        defer { window.close() }

        #expect(window.title == "Barometer Update")
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(!window.titlebarAppearsTransparent)
        #expect(window.isOpaque)
        #expect(window.backgroundColor == .windowBackgroundColor)
        #expect(window.minSize.width >= 650)
        #expect(window.contentView is UpdateOfferContentView)
        #expect(window.contentLayoutRect.height < window.frame.height)
        let viewport = try #require(controller.releaseNotesViewport)
        #expect(viewport.textField.stringValue.contains("Smooth release notes"))
        #expect(!viewport.textField.isEditable)
        #expect(!viewport.textField.isSelectable)
        #expect(!containsScrollView(viewport))
    }

    @Test("Hosted maximum release notes scroll repeatedly within a bounded CPU budget")
    func scrollPerformance() throws {
        let markdown = (1...500).map { index in
            "- Change **\(index)** keeps Barometer fast, reliable, and easy to understand."
        }.joined(separator: "\n")
        let release = UpdateRelease(
            version: try #require(ReleaseVersion("1.0.4")),
            notes: String(markdown.prefix(16_000)),
            asset: UpdateAsset(
                name: "Barometer-1.0.4.dmg",
                downloadURL: try #require(
                    URL(string: "https://github.com/mackid1993/Barometer/releases/download/v1.0.4/Barometer-1.0.4.dmg")
                ),
                sha256: String(repeating: "a", count: 64)
            )
        )
        let controller = UpdateOfferWindowController(release: release) { _ in }
        let window = try #require(controller.window)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let viewport = try #require(controller.releaseNotesViewport)
        viewport.layoutSubtreeIfNeeded()
        viewport.prepareForScrolling()
        let maximumOffset = viewport.maximumOffset
        #expect(maximumOffset > 1_000)
        let originalDocument = viewport.textField.attributedStringValue
        let initialPreparationCount = viewport.layoutPreparationCount
        var maximumObservedOffset: CGFloat = 0
        let startCPU = processCPUTime()
        for step in 0..<400 {
            let progress = Double(step % 200) / 199
            let offset = maximumOffset * progress
            viewport.scroll(to: offset)
            viewport.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            maximumObservedOffset = max(maximumObservedOffset, viewport.verticalOffset)
        }
        let consumedCPU = processCPUTime() - startCPU

        #expect(viewport.textField.attributedStringValue.isEqual(to: originalDocument))
        #expect(viewport.layoutPreparationCount == initialPreparationCount)
        #expect(maximumObservedOffset > 1_000)
        #expect(consumedCPU < 0.25, "Scrolling consumed \(consumedCPU) seconds of CPU time")
    }

    @Test("Precise trackpad deltas scroll directly without restarting layout")
    func preciseTrackpadScrolling() throws {
        let document = NSAttributedString(
            string: (1...500).map { "Release note \($0)" }.joined(separator: "\n"),
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let viewport = ReleaseNotesViewport(document: document)
        viewport.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        viewport.layoutSubtreeIfNeeded()
        viewport.prepareForScrolling()

        let initialPreparationCount = viewport.layoutPreparationCount
        let startCPU = processCPUTime()
        for _ in 0..<500 {
            let coreGraphicsEvent = try #require(CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: -4,
                wheel2: 0,
                wheel3: 0
            ))
            let event = try #require(NSEvent(cgEvent: coreGraphicsEvent))
            #expect(event.hasPreciseScrollingDeltas)
            viewport.handleScrollWheel(event)
        }
        let consumedCPU = processCPUTime() - startCPU

        #expect(viewport.verticalOffset > 1_000)
        #expect(viewport.layoutPreparationCount == initialPreparationCount)
        #expect(consumedCPU < 0.10, "Precise scrolling consumed \(consumedCPU) seconds of CPU time")
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains(where: containsScrollView)
    }

    private func processCPUTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}
