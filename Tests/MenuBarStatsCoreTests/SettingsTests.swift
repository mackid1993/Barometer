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

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("version zero settings migrate to the current schema")
    func migrateVersionZero() throws {
        let versionZero = Data(
            #"{"reducesSamplingOnBattery":false,"isMonochrome":false,"fontSize":12}"#.utf8
        )
        let migrated = try JSONDecoder().decode(AppSettings.self, from: versionZero)

        #expect(migrated.schemaVersion == 11)
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

        #expect(migrated.schemaVersion == 11)
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

        #expect(migrated.schemaVersion == 11)
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

        #expect(migrated.schemaVersion == 11)
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

        #expect(migrated.schemaVersion == 11)
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
