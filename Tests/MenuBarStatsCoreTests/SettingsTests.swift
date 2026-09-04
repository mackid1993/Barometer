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
        settings.weather.units.temperature = .celsius
        settings.sensorTemperatureUnit = .fahrenheit
        settings.applyTheme(.neon)
        settings.graphOpacity = 0.62
        settings.fontWeight = .semibold
        settings.usesCompactLayout = true
        settings.modules[.cpu]?.warningLightColor = "#ABCDEF"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("settings import rejects invalid values without changing current settings")
    @MainActor
    func rejectsInvalidImport() throws {
        let suite = try #require(UserDefaults(suiteName: "SettingsTests.invalid-import"))
        suite.removePersistentDomain(forName: "SettingsTests.invalid-import")
        let store = SettingsStore(defaults: suite)
        let original = store.settings
        var invalid = original
        invalid.graphOpacity = 4

        #expect(throws: SettingsImportError.valueOutOfRange("graph opacity")) {
            try store.importJSON(JSONEncoder().encode(invalid))
        }
        #expect(store.settings == original)
    }

    @Test("version zero settings migrate to the current schema")
    func migrateVersionZero() throws {
        let versionZero = Data(
            #"{"reducesSamplingOnBattery":false,"isMonochrome":false,"fontSize":12}"#.utf8
        )
        let migrated = try JSONDecoder().decode(AppSettings.self, from: versionZero)

        #expect(migrated.schemaVersion == 12)
        #expect(!migrated.reducesSamplingOnBattery)
        #expect(!migrated.isMonochrome)
        #expect(migrated.fontSize == 12)
        #expect(migrated.menuBarScale == 1)
        #expect(migrated.menuBarSpacing == 3)
        #expect(migrated.modules[.cpu]?.isEnabled == true)
        #expect(migrated.modules[.memory]?.isEnabled == true)
        #expect(migrated.weather.locations.isEmpty)
        #expect(migrated.weather.units == .imperial)
        #expect(migrated.sensorTemperatureUnit == .celsius)
        #expect(!migrated.usesGlobalColors)
    }

    @Test("schema one settings gain weather and hardware temperature defaults")
    func migrateSchemaOne() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "weather")
        object.removeValue(forKey: "sensorTemperatureUnit")

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 12)
        #expect(migrated.weather.refreshIntervalMinutes == 15)
        #expect(migrated.weather.units.temperature == .fahrenheit)
        #expect(migrated.sensorTemperatureUnit == .celsius)
        #expect(migrated.modules[.weather]?.mode == "iconTemperature")
    }

    @Test("schema four settings gain Network defaults")
    func migrateSchemaFourNetworkDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 4
        object.removeValue(forKey: "network")
        var modules = try #require(object["modules"] as? [Any])
        if let index = modules.firstIndex(where: { ($0 as? String) == ModuleID.network.rawValue }),
           modules.indices.contains(index + 1),
           var networkModule = modules[index + 1] as? [String: Any] {
            networkModule["mode"] = "percentage"
            modules[index + 1] = networkModule
            object["modules"] = modules
        }

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 12)
        #expect(migrated.network == NetworkSettings())
        #expect(migrated.modules[.network]?.mode == "twoLine")
        #expect(migrated.disks == DiskSettings())
    }

    @Test("older settings gain an inactive global palette")
    func migrateGlobalPaletteDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 5
        object.removeValue(forKey: "usesGlobalColors")
        object.removeValue(forKey: "globalLightColor")
        object.removeValue(forKey: "globalDarkColor")

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(!migrated.usesGlobalColors)
        #expect(migrated.globalLightColor == "#2F7CF6")
        #expect(migrated.globalDarkColor == "#6BA4FF")
    }

    @Test("schema six settings gain Disk defaults")
    func migrateSchemaSixDiskDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 6
        object.removeValue(forKey: "disks")
        var modules = try #require(object["modules"] as? [Any])
        if let index = modules.firstIndex(where: { ($0 as? String) == ModuleID.disks.rawValue }),
           modules.indices.contains(index + 1),
           var diskModule = modules[index + 1] as? [String: Any] {
            diskModule["mode"] = "percentage"
            modules[index + 1] = diskModule
            object["modules"] = modules
        }

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 12)
        #expect(migrated.disks == DiskSettings())
        #expect(migrated.modules[.disks]?.mode == "activityGraph")
    }

    @Test("schema seven settings gain Sensors defaults")
    func migrateSchemaSevenSensorDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 7
        object.removeValue(forKey: "sensors")
        var modules = try #require(object["modules"] as? [Any])
        if let index = modules.firstIndex(where: { ($0 as? String) == ModuleID.sensors.rawValue }),
           modules.indices.contains(index + 1),
           var sensorModule = modules[index + 1] as? [String: Any] {
            sensorModule["mode"] = "percentage"
            modules[index + 1] = sensorModule
            object["modules"] = modules
        }

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 12)
        #expect(migrated.sensors == SensorSettings())
        #expect(migrated.modules[.sensors]?.mode == "compactStack")
    }

    @Test("global palette overrides module colors without erasing them")
    func resolvesGlobalPalette() {
        let module = ModuleSettings(lightColor: "#111111", darkColor: "#EEEEEE")
        var settings = AppSettings(
            usesGlobalColors: true,
            globalLightColor: "#123456",
            globalDarkColor: "#ABCDEF"
        )

        #expect(settings.lightColor(for: module) == "#123456")
        #expect(settings.darkColor(for: module) == "#ABCDEF")
        settings.usesGlobalColors = false
        #expect(settings.lightColor(for: module) == "#111111")
        #expect(settings.darkColor(for: module) == "#EEEEEE")
    }

    @Test("appearance presets apply complete global color roles")
    func appliesAppearancePreset() {
        var settings = AppSettings()
        settings.applyTheme(.ocean)

        #expect(settings.appearancePreset == .ocean)
        #expect(!settings.isMonochrome)
        #expect(settings.usesGlobalColors)
        #expect(settings.globalLightColor == "#1677FF")
        #expect(settings.globalGraphLightColor == "#00A7C7")
        #expect(settings.globalWarningLightColor == "#F59E0B")
        #expect(settings.globalCriticalLightColor == "#DC2626")
    }

    @Test("module role colors fall back without erasing custom values")
    func resolvesAppearanceRoles() {
        let module = ModuleSettings(
            lightColor: "#111111",
            darkColor: "#EEEEEE",
            graphLightColor: "#123456",
            warningDarkColor: "#FEDCBA"
        )
        var settings = AppSettings(usesGlobalColors: false)

        #expect(settings.graphLightColor(for: module) == "#123456")
        #expect(settings.graphDarkColor(for: module) == "#EEEEEE")
        #expect(settings.warningDarkColor(for: module) == "#FEDCBA")
        settings.usesGlobalColors = true
        #expect(settings.graphLightColor(for: module) == settings.globalGraphLightColor)
    }

    @Test("weather primary location falls back without losing order")
    func weatherPrimaryLocationFallback() {
        let first = Location(
            id: "first",
            name: "Boston",
            admin: "Massachusetts",
            country: "United States",
            latitude: 42.36,
            longitude: -71.06,
            timeZone: "America/New_York"
        )
        let second = Location(
            id: "second",
            name: "Montréal",
            admin: "Quebec",
            country: "Canada",
            latitude: 45.50,
            longitude: -73.57,
            timeZone: "America/Toronto"
        )
        let weather = WeatherSettings(
            locations: [first, second],
            primaryLocationID: "missing"
        )

        #expect(weather.primaryLocation == first)
        #expect(weather.locations == [first, second])
    }

    @Test("existing schema one settings gain size and spacing defaults")
    func migratePresentationDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "menuBarScale")
        object.removeValue(forKey: "menuBarSpacing")
        object["presentationDefaultsVersion"] = 1

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.menuBarScale == 1)
        #expect(migrated.menuBarSpacing == 3)
        #expect(abs(migrated.fontSize - 13.8) < 0.001)
    }

    @Test("settings store persists immediately")
    @MainActor
    func settingsStoreRoundTrip() throws {
        let suiteName = "com.barometer.app.Tests.Settings"
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
