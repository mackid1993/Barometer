import AppKit
import MenuBarStatsCore
import SwiftUI

/// Battery menu bar, warning, sampling, and dropdown preferences.
struct BatterySettingsView: View {
    let settingsStore: SettingsStore

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.battery] ?? ModuleSettings(mode: "glyphPercentage", interval: 10)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: moduleBinding(\.isEnabled))
            }
            Section("Menu Bar") {
                Picker("Display", selection: moduleBinding(\.mode)) {
                    Text("Percentage inside battery").tag("glyphPercentage")
                    Text("BAT label and percentage").tag("labeledPercentage")
                }
                Toggle("Show while connected to power", isOn: batteryBinding(\.showsWhenConnectedToPower))
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
            }
            Section("Low Battery") {
                Stepper(value: batteryBinding(\.lowBatteryThresholdPercent), in: 5...50, step: 5) {
                    Text("Warning threshold: \(settingsStore.settings.battery.lowBatteryThresholdPercent)%")
                }
                Text("The menu bar item turns red below this level when colors are enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sampling") {
                HStack {
                    Text("Interval")
                    Slider(value: moduleBinding(\.interval), in: 2...60, step: 1)
                    Text("\(Int(moduleSettings.interval)) s")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                Text("Power connection changes refresh immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Devices") {
                Toggle("Show Bluetooth batteries", isOn: batteryBinding(\.showsBluetoothDevices))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Battery")
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { moduleSettings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.battery] ?? ModuleSettings(mode: "glyphPercentage", interval: 10)
                settings[keyPath: keyPath] = value
                appSettings.modules[.battery] = settings
                settingsStore.settings = appSettings
            }
        )
    }

    private func batteryBinding<Value>(_ keyPath: WritableKeyPath<BatterySettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.battery[keyPath: keyPath] },
            set: { value in
                var settings = settingsStore.settings
                settings.battery[keyPath: keyPath] = value
                settingsStore.settings = settings
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor) },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.battery] ?? ModuleSettings(mode: "glyphPercentage", interval: 10)
                settings[keyPath: keyPath] = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                appSettings.modules[.battery] = settings
                settingsStore.settings = appSettings
            }
        )
    }
}
