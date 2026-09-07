import AppKit
import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Battery menu bar, warning, sampling, and dropdown preferences.
struct BatterySettingsView: View {
    let settingsStore: SettingsStore

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.battery] ?? ModuleSettings(mode: "glyphPercentage", interval: 10)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: .battery))
            }
            Section("Menu Bar") {
                Picker("Display", selection: moduleBinding(\.mode)) {
                    Text("Percentage inside battery").tag("glyphPercentage")
                    Text("BAT label and percentage").tag("labeledPercentage")
                    Text("Percentage and time remaining").tag("percentageTime")
                    Text("BAT label and time remaining").tag("labeledTime")
                }
                Text(
                    "Time remaining counts down to empty on battery and up to full while charging, and always "
                        + "appears in the dropdown. Changing this takes effect the next time Barometer opens."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                SamplingIntervalNote()
            }
            Section("Devices") {
                Toggle("Show Bluetooth batteries", isOn: batteryBinding(\.showsBluetoothDevices))
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .battery, settings: settingsStore.settings, preview: previewImage)
    }

    /// The Battery item exactly as the menu bar draws it, in whichever mode is selected.
    ///
    /// The presenter behind the real status item renders the preview too, so each mode arrives
    /// centered on the one canvas the item reserves for all four rather than at its own natural
    /// width, which is what the menu bar does. The stand-in charge sits above the warning
    /// threshold, which stops at half, so the preview always carries the module's own color.
    private var previewImage: NSImage {
        let appSettings = settingsStore.settings
        let color = NSColor(hex: appSettings.darkColor(for: moduleSettings)) ?? .controlAccentColor
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            fontSize: appSettings.effectiveMenuBarFontSize,
            isMonochrome: appSettings.isMonochrome,
            scale: appSettings.effectiveMenuBarScale,
            fontWeight: appSettings.fontWeight
        )
        let snapshot = BatterySnapshot(
            name: "Internal Battery",
            chargePercent: 68,
            state: .discharging,
            isExternalConnected: false,
            isCharging: false,
            isFullyCharged: false,
            healthPercent: nil,
            cycleCount: nil,
            temperatureCelsius: nil,
            voltageVolts: nil,
            amperageAmps: nil,
            wattageWatts: nil,
            condition: nil,
            adapter: nil,
            isLowPowerModeEnabled: false,
            timeToEmptyMinutes: 200
        )
        return BatteryMenuBarPresenter.content(
            sample: BatterySample(snapshot: snapshot),
            moduleSettings: moduleSettings,
            batterySettings: appSettings.battery,
            context: context
        ).image
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
