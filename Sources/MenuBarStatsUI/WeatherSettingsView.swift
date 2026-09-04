import AppKit
import CoreLocation
import MenuBarStatsCore
import SwiftUI

/// Location, unit, refresh, and presentation settings for Weather.
struct WeatherSettingsView: View {
    let settingsStore: SettingsStore

    @State private var searchQuery = ""
    @State private var searchResults: [GeocodingResult] = []
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var locationError: String?

    private let client = OpenMeteoClient()

    var body: some View {
        Form {
            Section("Locations") {
                Toggle("Use current location", isOn: currentLocationBinding)
                if let locationError {
                    Text(locationError).font(.caption).foregroundStyle(.red)
                }

                if settingsStore.settings.weather.locations.isEmpty {
                    Text("Add a city below to start Weather.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settingsStore.settings.weather.locations.enumerated()), id: \.element.id) {
                        index, location in
                        locationRow(location, index: index)
                    }
                }
            }

            Section("Add a Location") {
                TextField("Search cities", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                if isSearching {
                    ProgressView().controlSize(.small)
                }
                if let searchError {
                    Text(searchError).font(.caption).foregroundStyle(.red)
                }
                ForEach(searchResults.prefix(6)) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                            Text([result.admin, result.country].compactMap { $0 }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") { add(result.location) }
                            .disabled(settingsStore.settings.weather.locations.contains { $0.id == result.location.id })
                    }
                }
            }

            Section("Units") {
                Picker("Temperature", selection: temperatureBinding) {
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                }
                Picker("Wind", selection: windBinding) {
                    Text("Miles per hour (mph)").tag(WindSpeedUnit.milesPerHour)
                    Text("Kilometers per hour (km/h)").tag(WindSpeedUnit.kilometersPerHour)
                    Text("Meters per second (m/s)").tag(WindSpeedUnit.metersPerSecond)
                    Text("Knots (kn)").tag(WindSpeedUnit.knots)
                }
                Picker("Pressure", selection: pressureBinding) {
                    Text("Inches of mercury (inHg)").tag(PressureUnit.inchesOfMercury)
                    Text("Hectopascals (hPa)").tag(PressureUnit.hectopascals)
                    Text("Millimeters of mercury (mmHg)").tag(PressureUnit.millimetersOfMercury)
                }
                Picker("Precipitation", selection: precipitationBinding) {
                    Text("Inches (in)").tag(PrecipitationUnit.inches)
                    Text("Millimeters (mm)").tag(PrecipitationUnit.millimeters)
                }
            }

            Section("Refresh") {
                Stepper(value: refreshIntervalBinding, in: 5...60, step: 5) {
                    LabeledContent("Interval", value: "\(weather.refreshIntervalMinutes) minutes")
                }
            }

            Section("Menu Bar") {
                Toggle("Show in menu bar", isOn: moduleEnabledBinding)
                Text("Shows the current conditions and temperature. Set the unit under Units.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar Colors") {
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                if settingsStore.settings.usesGlobalColors {
                    Text("The global palette in General is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if settingsStore.settings.isMonochrome {
                    Text("Turn off Monochrome menu bar in General to display colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .weather, settings: settingsStore.settings)
        .task(id: searchQuery) {
            await search()
        }
    }

    private var weather: WeatherSettings {
        settingsStore.settings.weather
    }

    @ViewBuilder
    private func locationRow(_ location: Location, index: Int) -> some View {
        HStack {
            Button {
                updateWeather { $0.primaryLocationID = location.id }
            } label: {
                Image(systemName: weather.primaryLocation?.id == location.id ? "circle.inset.filled" : "circle")
            }
            .buttonStyle(.plain)
            .help("Use in the menu bar")
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                Text([location.admin, location.country].compactMap { $0 }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                moveLocation(from: index, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            Button {
                moveLocation(from: index, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == weather.locations.count - 1)
            Button(role: .destructive) {
                remove(location)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var currentLocationBinding: Binding<Bool> {
        Binding(
            get: { weather.usesCurrentLocation },
            set: { enabled in
                updateWeather { $0.usesCurrentLocation = enabled }
                if enabled {
                    requestCurrentLocation()
                } else {
                    removeCurrentLocation()
                }
            }
        )
    }

    private var moduleEnabledBinding: Binding<Bool> {
        settingsStore.menuBarVisibilityBinding(for: .weather)
    }


    private var temperatureBinding: Binding<TemperatureUnit> {
        unitBinding(\.temperature)
    }

    private var windBinding: Binding<WindSpeedUnit> {
        unitBinding(\.windSpeed)
    }

    private var pressureBinding: Binding<PressureUnit> {
        unitBinding(\.pressure)
    }

    private var precipitationBinding: Binding<PrecipitationUnit> {
        unitBinding(\.precipitation)
    }

    private var refreshIntervalBinding: Binding<Int> {
        weatherBinding(\.refreshIntervalMinutes)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: {
                let module = settingsStore.settings.modules[.weather] ?? ModuleSettings()
                return Color(nsColor: NSColor(hex: module[keyPath: keyPath]) ?? .controlAccentColor)
            },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                var settings = settingsStore.settings
                var module = settings.modules[.weather] ?? ModuleSettings()
                module[keyPath: keyPath] = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                settings.modules[.weather] = module
                settings.appearancePreset = .custom
                settingsStore.settings = settings
            }
        )
    }

    private func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            searchResults = try await client.geocode(query)
            searchError = searchResults.isEmpty ? "No matching locations." : nil
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    private func add(_ location: Location) {
        updateWeather { settings in
            guard !settings.locations.contains(where: { $0.id == location.id }) else {
                return
            }
            settings.locations.append(location)
            settings.primaryLocationID = settings.primaryLocationID ?? location.id
        }
        setWeatherEnabled(true)
    }

    private func remove(_ location: Location) {
        updateWeather { settings in
            settings.locations.removeAll { $0.id == location.id }
            if settings.primaryLocationID == location.id {
                settings.primaryLocationID = settings.locations.first?.id
            }
            if location.id == "current-location" {
                settings.usesCurrentLocation = false
            }
        }
    }

    private func moveLocation(from index: Int, offset: Int) {
        updateWeather { settings in
            let destination = index + offset
            guard settings.locations.indices.contains(index), settings.locations.indices.contains(destination) else {
                return
            }
            settings.locations.swapAt(index, destination)
        }
    }

    private func requestCurrentLocation() {
        locationError = nil
        CurrentLocationProvider.shared.start { value in
            let location = Location(
                id: "current-location",
                name: "Current Location",
                admin: nil,
                country: "",
                latitude: value.coordinate.latitude,
                longitude: value.coordinate.longitude,
                timeZone: TimeZone.current.identifier
            )
            updateWeather { settings in
                settings.locations.removeAll { $0.id == location.id }
                settings.locations.insert(location, at: 0)
                settings.primaryLocationID = location.id
            }
            setWeatherEnabled(true)
        } failure: { error in
            locationError = error.localizedDescription
            updateWeather { $0.usesCurrentLocation = false }
        }
    }

    private func removeCurrentLocation() {
        CurrentLocationProvider.shared.stop()
        if let current = weather.locations.first(where: { $0.id == "current-location" }) {
            remove(current)
        }
    }

    private func weatherBinding<Value>(_ keyPath: WritableKeyPath<WeatherSettings, Value>) -> Binding<Value> {
        Binding(
            get: { weather[keyPath: keyPath] },
            set: { value in updateWeather { $0[keyPath: keyPath] = value } }
        )
    }

    private func unitBinding<Value>(_ keyPath: WritableKeyPath<WeatherUnits, Value>) -> Binding<Value> {
        Binding(
            get: { weather.units[keyPath: keyPath] },
            set: { value in
                updateWeather { $0.units[keyPath: keyPath] = value }
            }
        )
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.modules[.weather]?[keyPath: keyPath] ?? ModuleSettings()[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var moduleSettings = appSettings.modules[.weather] ?? ModuleSettings()
                moduleSettings[keyPath: keyPath] = value
                appSettings.modules[.weather] = moduleSettings
                settingsStore.settings = appSettings
            }
        )
    }

    private func updateWeather(_ update: (inout WeatherSettings) -> Void) {
        var appSettings = settingsStore.settings
        update(&appSettings.weather)
        settingsStore.settings = appSettings
    }

    private func setWeatherEnabled(_ enabled: Bool) {
        settingsStore.stageMenuBarVisibility(enabled, for: .weather)
        var appSettings = settingsStore.settings
        var moduleSettings = appSettings.modules[.weather] ?? ModuleSettings()
        if moduleSettings.mode == "percentage" {
            moduleSettings.mode = "iconTemperature"
        }
        appSettings.modules[.weather] = moduleSettings
        settingsStore.settings = appSettings
    }
}
