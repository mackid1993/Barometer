import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("SettingsTests")
struct SettingsTests {
    @Test("settings encode and decode without loss")
    func roundTrip() throws {
        var settings = AppSettings()
        settings.fontSize = 13
        settings.modules[.cpu]?.mode = "graph"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("version zero settings migrate to schema one")
    func migrateVersionZero() throws {
        let versionZero = Data(
            #"{"reducesSamplingOnBattery":false,"isMonochrome":false,"fontSize":12}"#.utf8
        )
        let migrated = try JSONDecoder().decode(AppSettings.self, from: versionZero)

        #expect(migrated.schemaVersion == 1)
        #expect(!migrated.reducesSamplingOnBattery)
        #expect(!migrated.isMonochrome)
        #expect(migrated.fontSize == 12)
        #expect(migrated.modules[.cpu]?.isEnabled == true)
        #expect(migrated.modules[.memory]?.isEnabled == true)
    }

    @Test("settings store persists immediately")
    @MainActor
    func settingsStoreRoundTrip() throws {
        let suiteName = "net.brustein.MenuBarStats.Tests.Settings"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        var updated = store.settings
        updated.fontSize = 14
        store.settings = updated
        store.saveNow()

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.fontSize == 14)
    }
}
