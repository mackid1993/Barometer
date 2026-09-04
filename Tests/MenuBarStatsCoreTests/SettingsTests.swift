import Foundation
import Testing

@testable import MenuBarStatsCore

@Suite("SettingsTests")
struct SettingsTests {
    @Test("settings encode and decode without loss")
    func roundTrip() throws {
        var settings = AppSettings()
        settings.fontSize = 11.5
        settings.modules[.cpu]?.mode = "graph"
        settings.weather.units.temperature = .celsius
        settings.sensorTemperatureUnit = .fahrenheit
        settings.applyTheme(.neon)
        settings.graphOpacity = 0.62
        settings.fontWeight = .semibold
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

    @Test("legacy battery presentations migrate to the percentage glyph")
    func migratesLegacyBatteryPresentation() throws {
        var settings = AppSettings()
        settings.modules[.battery]?.mode = "time"

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.modules[.battery]?.mode == "glyphPercentage")
    }

    @Test("supported battery presentations survive settings decoding")
    func preservesSupportedBatteryPresentations() throws {
        for mode in ["glyphPercentage", "labeledPercentage", "percentageTime", "labeledTime"] {
            var settings = AppSettings()
            settings.modules[.battery]?.mode = mode

            let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

            #expect(decoded.modules[.battery]?.mode == mode)
        }
    }

    @Test("version zero settings migrate to the current schema")
    func migrateVersionZero() throws {
        let versionZero = Data(
            #"{"reducesSamplingOnBattery":false,"isMonochrome":false,"fontSize":12}"#.utf8
        )
        let migrated = try JSONDecoder().decode(AppSettings.self, from: versionZero)

        #expect(migrated.schemaVersion == 14)
        #expect(!migrated.reducesSamplingOnBattery)
        #expect(!migrated.isMonochrome)
        #expect(migrated.fontSize == 12)
        #expect(migrated.effectiveMenuBarScale == 1.15)
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

        #expect(migrated.schemaVersion == 14)
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
            var networkModule = modules[index + 1] as? [String: Any]
        {
            networkModule["mode"] = "percentage"
            modules[index + 1] = networkModule
            object["modules"] = modules
        }

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 14)
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
            var diskModule = modules[index + 1] as? [String: Any]
        {
            diskModule["mode"] = "percentage"
            modules[index + 1] = diskModule
            object["modules"] = modules
        }

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 14)
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
            var sensorModule = modules[index + 1] as? [String: Any]
        {
            sensorModule["mode"] = "percentage"
            modules[index + 1] = sensorModule
            object["modules"] = modules
        }

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.schemaVersion == 14)
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

    @Test("legacy presentation scale is ignored")
    func migratePresentationDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["menuBarScale"] = 0.75
        object["presentationDefaultsVersion"] = 1

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let migrated = try JSONDecoder().decode(AppSettings.self, from: oldData)

        #expect(migrated.effectiveMenuBarScale == 1.15)
        #expect(migrated.fontSize == 12)
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
        updated.fontSize = 12
        store.settings = updated
        store.saveNow()

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.fontSize == 12)
    }

    @Test("menu bar font size is capped at the fixed canvas maximum")
    func capsMenuBarFontSize() {
        var settings = AppSettings(fontSize: 14)
        #expect(settings.fontSize == 12)
        settings.fontSize = 13
        #expect(settings.fontSize == 12)
        settings.fontSize = 8
        #expect(settings.fontSize == 9)
    }

    @Test("icon and graph scale follows widget density")
    func automaticallyScalesMenuBarGraphics() {
        #expect(AppSettings.menuBarScale(forItemCount: 3) == 1.15)
        #expect(AppSettings.menuBarScale(forItemCount: 4) == 1)
        #expect(AppSettings.menuBarScale(forItemCount: 7) == 0.9)
        #expect(AppSettings.menuBarScale(forItemCount: 9) == 0.85)
        #expect(AppSettings.menuBarScale(forItemCount: 12) == 0.8)
        #expect(AppSettings.menuBarScale(forItemCount: 15) == 0.75)
    }

    @Test("removed density settings are ignored and no longer exported")
    func ignoresRemovedDensitySettings() throws {
        let data = Data(#"{"menuBarScale":0.75,"menuBarSpacing":3,"usesCompactLayout":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let encoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )

        #expect(encoded["menuBarScale"] == nil)
        #expect(encoded["menuBarSpacing"] == nil)
        #expect(encoded["usesCompactLayout"] == nil)
    }

    @Test("active widget count automatically limits effective font size")
    func limitsFontSizeForDensity() {
        var settings = AppSettings(fontSize: 9)
        #expect(settings.enabledMenuBarItemCount == 2)
        #expect(settings.effectiveMenuBarFontSize == 12)
        #expect(settings.effectiveMenuBarScale == 1.15)

        for module in [ModuleID.gpu, .network, .sensors, .weather] {
            settings.modules[module]?.isEnabled = true
        }
        #expect(settings.enabledMenuBarItemCount == 6)
        #expect(settings.effectiveMenuBarFontSize == 12)
        #expect(settings.effectiveMenuBarScale == 1)

        settings.modules[.battery]?.isEnabled = true
        settings.modules[.time]?.isEnabled = true
        settings.modules[.disks]?.isEnabled = true
        #expect(settings.enabledMenuBarItemCount == 9)
        #expect(settings.effectiveMenuBarFontSize == 11)
        #expect(settings.effectiveMenuBarScale == 0.85)

        settings.sensors.widgets.append(SensorWidgetSettings(id: 2))
        #expect(settings.enabledMenuBarItemCount == 10)
        #expect(settings.effectiveMenuBarFontSize == 11)

        settings.sensors.widgets.append(SensorWidgetSettings(id: 3))
        settings.sensors.widgets.append(SensorWidgetSettings(id: 4))
        #expect(settings.enabledMenuBarItemCount == 12)
        #expect(settings.effectiveMenuBarFontSize == 10)
        #expect(settings.effectiveMenuBarScale == 0.8)

        // One stack replacing CPU, Memory, and every Sensors widget: eleven items collapse to the
        // six that remain plus the stack itself.
        settings.modules[.combined]?.isEnabled = true
        settings.stacks = StacksSettings(stacks: [
            StackSettings(
                id: 1,
                metrics: [.cpuTotal, .memoryUsedPercent, .sensorsHottest],
                hidesSourceItems: true
            )
        ])
        #expect(settings.enabledMenuBarItemCount == 7)
        #expect(settings.effectiveMenuBarFontSize == 12)
        #expect(settings.effectiveMenuBarScale == 0.9)

        settings.modules[.combined]?.isEnabled = false
        #expect(settings.enabledMenuBarItemCount == 12)
        #expect(settings.effectiveMenuBarFontSize == 10)
        #expect(settings.effectiveMenuBarScale == 0.8)

        settings.sensors.widgets.append(SensorWidgetSettings(id: 5))
        settings.sensors.widgets.append(SensorWidgetSettings(id: 6))
        settings.sensors.widgets.append(SensorWidgetSettings(id: 7))
        #expect(settings.enabledMenuBarItemCount == 15)
        #expect(settings.effectiveMenuBarFontSize == 9)
        #expect(settings.effectiveMenuBarScale == 0.75)
    }

    @Test("launch menu bar geometry remains fixed after settings change")
    @MainActor
    func freezesLaunchMenuBarGeometry() {
        let suiteName = "com.barometer.app.Tests.LaunchGeometry"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        #expect(store.launchMenuBarFontSize == 12)
        #expect(store.launchMenuBarScale == 1.15)

        for module in ModuleID.allCases {
            store.settings.modules[module]?.isEnabled = true
        }
        store.settings.fontWeight = .semibold
        #expect(store.settings.effectiveMenuBarScale < store.launchMenuBarScale)
        #expect(store.launchMenuBarFontSize == 12)
        #expect(store.launchMenuBarScale == 1.15)
        #expect(store.settings.fontWeight == .semibold)
    }

    @Test("menu bar visibility remains pending until applied")
    @MainActor
    func stagesMenuBarVisibility() {
        let suiteName = "com.barometer.app.Tests.PendingVisibility"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        #expect(store.settings.modules[.network]?.isEnabled == false)

        store.stageMenuBarVisibility(true, for: .network)

        #expect(store.menuBarVisibility(for: .network))
        #expect(store.settings.modules[.network]?.isEnabled == false)
        #expect(store.settingsIncludingPendingMenuBarChanges.modules[.network]?.isEnabled == true)
        #expect(store.hasPendingMenuBarChanges)

        store.applyPendingMenuBarChanges()

        #expect(store.settings.modules[.network]?.isEnabled == true)
        #expect(!store.hasPendingMenuBarChanges)
    }

    @Test("returning a visibility toggle to its saved value clears the pending change")
    @MainActor
    func cancelsPendingMenuBarVisibility() {
        let suiteName = "com.barometer.app.Tests.CanceledVisibility"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.stageMenuBarVisibility(true, for: .weather)
        store.stageMenuBarVisibility(false, for: .weather)

        #expect(!store.hasPendingMenuBarChanges)
        #expect(store.settings.modules[.weather]?.isEnabled == false)
    }

    @Test("Sensors widget visibility uses the same apply boundary")
    @MainActor
    func stagesSensorWidgetVisibility() {
        let suiteName = "com.barometer.app.Tests.PendingSensorVisibility"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let widgetID = store.settings.sensors.widgets[0].id
        #expect(store.settings.sensors.widgets[0].isEnabled)

        store.stageSensorWidgetVisibility(false, for: widgetID)

        #expect(!store.sensorWidgetVisibility(for: widgetID))
        #expect(store.settings.sensors.widgets[0].isEnabled)

        store.applyPendingMenuBarChanges()

        #expect(store.settings.sensors.widgets[0].isEnabled == false)
        #expect(!store.hasPendingMenuBarChanges)
    }

    @Test("stack topology remains pending until applied")
    @MainActor
    func stagesStackTopology() {
        let suiteName = "com.barometer.app.Tests.PendingStackTopology"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        // Stacks start empty, so the one being staged has to exist first.
        var initial = store.settings
        initial.stacks = StacksSettings(stacks: [StackSettings(id: 1, metrics: [.cpuTotal])])
        store.settings = initial
        let savedMetrics = store.settings.stacks.stack(id: 1)?.metrics
        store.stageStackMetrics([.cpuTotal, .batteryTime], for: 1)
        store.stageStackHidesSourceItems(true, for: 1)
        store.stageStackVisibility(false, for: 1)

        #expect(store.hasPendingMenuBarChanges)
        #expect(store.settings.stacks.stack(id: 1)?.metrics == savedMetrics)
        let staged = store.settingsIncludingPendingMenuBarChanges.stacks.stack(id: 1)
        #expect(staged?.metrics == [.cpuTotal, .batteryTime])
        #expect(staged?.hidesSourceItems == true)
        #expect(staged?.isEnabled == false)

        store.applyPendingMenuBarChanges()

        #expect(!store.hasPendingMenuBarChanges)
        #expect(store.settings.stacks.stack(id: 1)?.metrics == [.cpuTotal, .batteryTime])
        #expect(store.settings.stacks.stack(id: 1)?.hidesSourceItems == true)
        #expect(store.settings.stacks.stack(id: 1)?.isEnabled == false)
    }

    @Test("settings written before stacks shipped migrate Combined into stack 1")
    func migratesCombinedSettingsIntoStacks() throws {
        var settings = AppSettings()
        settings.combined = CombinedSettings(members: [.cpu, .gpu], hidesIndividualMembers: true)
        // Only an item that was actually on migrates; someone who never enabled Combined gets no
        // stacks rather than one they never asked for.
        settings.modules[.combined]?.isEnabled = true
        var object = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(settings)
        ) as! [String: Any]
        object.removeValue(forKey: "stacks")

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.stacks.stacks.count == 1)
        #expect(decoded.stacks.stack(id: 1)?.metrics == [.cpuTotal, .gpuUtilization])
        #expect(decoded.stacks.stack(id: 1)?.hidesSourceItems == true)
    }

    @Test("every enabled stack counts toward the automatic menu bar sizing budget")
    func stacksCountTowardItemBudget() {
        var settings = AppSettings()
        settings.modules[.cpu]?.isEnabled = true
        settings.modules[.memory]?.isEnabled = true
        settings.modules[.combined]?.isEnabled = false
        let withoutStacks = settings.enabledMenuBarItemCount

        settings.modules[.combined]?.isEnabled = true
        settings.stacks = StacksSettings(stacks: [
            StackSettings(id: 1, metrics: [.cpuTotal]),
            StackSettings(id: 2, metrics: [.memoryUsedPercent]),
            StackSettings(id: 3, isEnabled: false, metrics: [.gpuUtilization]),
        ])
        // No cap: the count follows whatever the user created.
        #expect(settings.stacks.stacks.count == 3)

        // Two enabled stacks add two items; the disabled tombstone adds none.
        #expect(settings.enabledMenuBarItemCount == withoutStacks + 2)

        // A stack that replaces its source items removes them from the budget again.
        settings.stacks.stacks[0].hidesSourceItems = true
        #expect(settings.enabledMenuBarItemCount == withoutStacks + 1)
    }
}
