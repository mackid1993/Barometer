import AppKit
import Foundation
import Testing
@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@Suite("System control pills")
@MainActor
struct SystemControlPillTests {
    @Test("Focus and Now Playing toggles are independent and take effect only when applied")
    func independentVisibility() throws {
        let suite = "SystemControlPillTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(!store.menuBarVisibility(for: .focus))
        #expect(!store.menuBarVisibility(for: .nowPlaying))
        store.stageMenuBarVisibility(true, for: .focus)
        #expect(store.menuBarVisibility(for: .focus))
        #expect(!store.menuBarVisibility(for: .nowPlaying))
        #expect(store.settings.modules[.focus]?.isEnabled == false)
        #expect(!store.settings.time.hidesSystemClock)
        store.applyPendingMenuBarChanges()
        #expect(store.settings.modules[.focus]?.isEnabled == true)
        #expect(store.settings.modules[.nowPlaying]?.isEnabled == false)
        #expect(StatusItemRegistry.launchIdentities(settings: store.settings).contains(.init(module: .focus)))
        store.stageMenuBarVisibility(false, for: .focus)
        store.stageMenuBarVisibility(true, for: .nowPlaying)
        store.applyPendingMenuBarChanges()
        #expect(store.settings.modules[.focus]?.isEnabled == false)
        #expect(store.settings.modules[.nowPlaying]?.isEnabled == true)
        #expect(!store.settings.time.hidesSystemClock)
    }

    @Test("pill width stays fixed across state and symbol changes")
    func fixedWidth() {
        let context = RenderContext(thickness: 33, appearance: .dark,
                                    palette: .init(light: .black, dark: .white), fontSize: 12, isMonochrome: true)
        let states = [
            SystemControlSample(symbolName: "moon", accessibilityValue: "Focus off", isActive: false),
            SystemControlSample(symbolName: "moon.fill", accessibilityValue: "Focus: Work", isActive: true),
            SystemControlSample(symbolName: "waveform", accessibilityValue: "Now Playing: Song", isActive: true),
            SystemControlSample(symbolName: "pause.fill", accessibilityValue: "Now Playing: Paused", isActive: false),
        ]
        let content = states.map { SystemControlPillRenderer.render($0, in: context) }
        #expect(Set(content.map { $0.image.size.width }) == [30])
        #expect(content.allSatisfy { $0.image.isTemplate && $0.image.size.height == 33 })
        #expect(content.map(\.accessibilityValue) == states.map(\.accessibilityValue))
    }
}
