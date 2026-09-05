import AppKit
import MenuBarStatsCore
import SwiftUI

/// Menu bar, sampling, and dropdown preferences for the CPU and Memory modules.
struct ModuleSettingsView: View {
    let module: ModuleID
    let settingsStore: SettingsStore

    private var settings: ModuleSettings {
        settingsStore.settings.modules[module] ?? ModuleSettings()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: module))
            }

            Section("Menu Bar") {
                Picker("Display", selection: moduleBinding(\.mode)) {
                    ForEach(modeOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                Toggle("Use fixed-width numbers", isOn: moduleBinding(\.usesFixedWidth))
                Picker("Graph style", selection: moduleBinding(\.graphStyle)) {
                    ForEach(GraphStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
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

            Section("Sampling") {
                HStack {
                    Text("Interval")
                    Slider(value: moduleBinding(\.interval), in: 0.5...10, step: 0.5)
                    Text(String(format: "%.1f s", settings.interval))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Section("Dropdown") {
                Toggle("Show top processes", isOn: moduleBinding(\.showsProcesses))
                Stepper(value: moduleBinding(\.processCount), in: 1...10) {
                    Text("Process count: \(settings.processCount)")
                }
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: module, settings: settingsStore.settings, preview: previewImage)
    }

    private var modeOptions: [(value: String, label: String)] {
        if module == .cpu {
            return [
                ("stacked", "CPU label + percentage"),
                ("percentage", "Percentage"),
                ("graph", "History graph"),
                ("perCore", "Per-core bars"),
                ("iconText", "Icon + percentage"),
            ]
        }
        return [
            ("stacked", "MEM label + percentage"),
            ("usedPercentage", "Used percentage"),
            ("pressurePercentage", "Pressure percentage"),
            ("graph", "History graph"),
            ("bar", "Usage bar"),
        ]
    }

    private var previewImage: NSImage {
        let appSettings = settingsStore.settings
        let color = NSColor(hexString: appSettings.darkColor(for: settings)) ?? .controlAccentColor
        let scale = appSettings.effectiveMenuBarScale
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            fontSize: appSettings.effectiveMenuBarFontSize,
            isMonochrome: appSettings.isMonochrome,
            scale: scale
        )
        let value = module == .cpu ? "42%" : "68%"
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "stacked":
            renderer = StackedLabelRenderer(
                label: module == .cpu ? "CPU" : "MEM",
                value: value,
                reservedValue: "100%"
            )
        case "graph":
            renderer = GraphRenderer(values: [0.2, 0.35, 0.28, 0.7, 0.48, 0.62], style: settings.graphStyle)
        case "perCore":
            renderer = GraphRenderer(values: [0.2, 0.8, 0.45, 0.62, 0.25, 0.7], style: .bars, width: 34)
        case "bar":
            renderer = GraphRenderer(values: [0.68], style: .bars, width: 14)
        case "iconText":
            renderer = IconTextRenderer(symbolName: "cpu", text: value, reservedText: "100%")
        default:
            renderer = TextRenderer(text: value, reservedText: settings.usesFixedWidth ? "100%" : nil)
        }
        return renderer.render(in: context)
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var moduleSettings = appSettings.modules[module] ?? ModuleSettings()
                moduleSettings[keyPath: keyPath] = value
                appSettings.modules[module] = moduleSettings
                settingsStore.settings = appSettings
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hexString: settings[keyPath: keyPath]) ?? .controlAccentColor) },
            set: { color in
                guard let hex = NSColor(color).hexRGB else { return }
                var appSettings = settingsStore.settings
                var moduleSettings = appSettings.modules[module] ?? ModuleSettings()
                moduleSettings[keyPath: keyPath] = hex
                appSettings.modules[module] = moduleSettings
                settingsStore.settings = appSettings
            }
        )
    }
}

extension NSColor {
    fileprivate convenience init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let integer = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((integer >> 16) & 0xFF) / 255,
            green: CGFloat((integer >> 8) & 0xFF) / 255,
            blue: CGFloat(integer & 0xFF) / 255,
            alpha: 1
        )
    }

    fileprivate var hexRGB: String? {
        guard let components = usingColorSpace(.sRGB) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(components.redComponent * 255),
            Int(components.greenComponent * 255),
            Int(components.blueComponent * 255)
        )
    }
}
