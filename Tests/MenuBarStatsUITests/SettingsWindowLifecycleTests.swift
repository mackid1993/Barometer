import Foundation
import Testing
@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@Suite("Settings window lifecycle", .serialized)
@MainActor
struct SettingsWindowLifecycleTests {
    @Test("Closing Settings detaches its hosted SwiftUI tree and notifies its owner")
    func closeReleasesController() throws {
        let suite = "SettingsWindowLifecycleTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(AppSettings()), forKey: SettingsStore.defaultsKey)
        let settingsStore = SettingsStore(defaults: defaults)
        var closeCount = 0
        var selectedModules: [ModuleID?] = []
        var controller: SettingsWindowController? = SettingsWindowController(
            settingsStore: settingsStore,
            gpuStore: .init(historyCapacity: 1),
            batteryStore: .init(historyCapacity: 1),
            timeStore: .init(historyCapacity: 1),
            networkStore: .init(historyCapacity: 1),
            diskStore: .init(historyCapacity: 1),
            sensorStore: .init(historyCapacity: 1),
            updateController: UpdateController(),
            calendarAccessAction: {},
            moduleSelectionAction: { selectedModules.append($0) },
            applyMenuBarChangesAction: {}
        )
        let window = try #require(controller?.window)
        controller?.windowCloseHandler = {
            closeCount += 1
            controller = nil
        }

        controller?.show(module: .sensors)
        window.close()

        #expect(closeCount == 1)
        #expect(controller == nil)
        #expect(window.contentViewController == nil)
        #expect(window.delegate == nil)
        #expect(selectedModules == [.sensors, nil])
    }

    @Test("Automatic update checks can be disabled and remain disabled")
    func automaticUpdatePreference() throws {
        let suite = "UpdatePreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let controller = UpdateController(defaults: defaults)
        #expect(controller.automaticChecksEnabled)
        controller.toggleAutomaticChecks()
        #expect(!controller.automaticChecksEnabled)
        #expect(controller.statusMessage == "Automatic checks are off")

        let restored = UpdateController(defaults: defaults)
        #expect(!restored.automaticChecksEnabled)
    }
}
