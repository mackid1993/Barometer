import MenuBarStatsCore
import Testing

@testable import MenuBarStatsUI

@Suite("SystemControlsCoordinatorTests")
@MainActor
struct SystemControlsCoordinatorTests {
    @Test("Focus appears only while its system state is active")
    func focusVisibility() {
        #expect(!SystemControlsCoordinator.shouldPresentFocus(nil))
        #expect(!SystemControlsCoordinator.shouldPresentFocus(Self.sample(isActive: false)))
        #expect(SystemControlsCoordinator.shouldPresentFocus(Self.sample(isActive: true)))
    }

    @Test("Now Playing follows the persisted presentation choice")
    func nowPlayingVisibility() {
        let inactive = Self.sample(isActive: false)
        let active = Self.sample(isActive: true)

        #expect(!SystemControlsCoordinator.shouldPresentNowPlaying(nil, visibility: .whenPlaying))
        #expect(!SystemControlsCoordinator.shouldPresentNowPlaying(inactive, visibility: .whenPlaying))
        #expect(SystemControlsCoordinator.shouldPresentNowPlaying(active, visibility: .whenPlaying))
        #expect(SystemControlsCoordinator.shouldPresentNowPlaying(nil, visibility: .always))
        #expect(SystemControlsCoordinator.shouldPresentNowPlaying(inactive, visibility: .always))
    }

    private static func sample(isActive: Bool) -> SystemControlSample {
        SystemControlSample(symbolName: "circle", accessibilityValue: "State", isActive: isActive)
    }
}
