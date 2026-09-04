import AppKit
import MenuBarStatsCore
import ServiceManagement
import SwiftUI

/// Owns and presents the MenuBarStats settings window.
@MainActor
public final class SettingsWindowController: NSWindowController {
    /// Creates the settings window controller.
    public convenience init(
        settingsStore: SettingsStore,
        networkStore: ModuleStore<NetworkSample>,
        diskStore: ModuleStore<DiskSample>,
        sensorStore: ModuleStore<SensorSample>
    ) {
        let rootView = SettingsRootView(
            settingsStore: settingsStore,
            networkStore: networkStore,
            diskStore: diskStore,
            sensorStore: sensorStore
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Barometer Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    /// Brings the settings window to the front.
    public func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private enum SettingsSelection: Hashable {
    case general
    case module(ModuleID)

    var title: String {
        switch self {
        case .general: "General"
        case let .module(module): module.displayName
        }
    }
}

private struct SettingsRootView: View {
    let settingsStore: SettingsStore
    let networkStore: ModuleStore<NetworkSample>
    let diskStore: ModuleStore<DiskSample>
    let sensorStore: ModuleStore<SensorSample>
    @State private var selection: SettingsSelection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsSelection.general)

                Section("Modules") {
                    ForEach(ModuleID.allCases, id: \.self) { module in
                        Label(module.displayName, systemImage: module.symbolName)
                            .tag(SettingsSelection.module(module))
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 175, ideal: 195)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralSettingsView(settingsStore: settingsStore)
            case let .module(module) where module == .cpu || module == .memory:
                ModuleSettingsView(module: module, settingsStore: settingsStore)
            case let .module(module) where module == .weather:
                WeatherSettingsView(settingsStore: settingsStore)
            case let .module(module) where module == .network:
                NetworkSettingsView(store: networkStore, settingsStore: settingsStore)
            case let .module(module) where module == .disks:
                DiskSettingsView(store: diskStore, settingsStore: settingsStore)
            case let .module(module) where module == .sensors:
                SensorSettingsView(store: sensorStore, settingsStore: settingsStore)
            case let .module(module):
                FutureModuleSettingsView(module: module)
            }
        }
    }
}

private struct GeneralSettingsView: View {
    let settingsStore: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var serviceError: String?

    var body: some View {
        Form {
            Section("Application") {
                LabeledContent("Launch Barometer at login") {
                    Button(launchAtLogin ? "Disable" : "Enable") {
                        updateLaunchAtLogin(!launchAtLogin)
                    }
                }
                if let serviceError {
                    Text(serviceError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Reduce sampling rate on battery", isOn: appBinding(\.reducesSamplingOnBattery))
                    .help("Doubles sampling intervals while the Mac is running on battery power.")
            }

            Section("Appearance") {
                Toggle("Monochrome menu bar", isOn: appBinding(\.isMonochrome))
                HStack {
                    Text("Font size")
                    Slider(value: appBinding(\.fontSize), in: 9...14, step: 0.5)
                    Text(String(format: "%.1f pt", settingsStore.settings.fontSize))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
                HStack {
                    Text("Icon and graph size")
                    Slider(value: appBinding(\.menuBarScale), in: 0.75...1.35, step: 0.05)
                    Text(settingsStore.settings.menuBarScale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Text("Item spacing")
                    Slider(value: appBinding(\.menuBarSpacing), in: 0...12, step: 1)
                    Text("\(Int(settingsStore.settings.menuBarSpacing)) pt")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                Text("Adds space around each independent, movable menu bar item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar Colors") {
                Toggle("Use one palette for every module", isOn: appBinding(\.usesGlobalColors))
                MenuBarColorPickerRows(
                    lightColor: globalColorBinding(\.globalLightColor),
                    darkColor: globalColorBinding(\.globalDarkColor),
                    isDisabled: !settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                if settingsStore.settings.isMonochrome {
                    Text("Turn off Monochrome menu bar to display colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !settingsStore.settings.usesGlobalColors {
                    Text("Each module uses its own light and dark colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Measurement Units") {
                Picker("Hardware temperatures", selection: appBinding(\.sensorTemperatureUnit)) {
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                }
                Text("Used by Sensors, GPU, and Battery temperature readouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Settings File") {
                HStack {
                    Button("Export Settings…", action: exportSettings)
                    Button("Import Settings…", action: importSettings)
                    Spacer()
                }
                Text("Exported files contain display and sampling preferences, but no system data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func appBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                var settings = settingsStore.settings
                settings[keyPath: keyPath] = value
                settingsStore.settings = settings
            }
        )
    }

    private func globalColorBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(hex: settingsStore.settings[keyPath: keyPath]) ?? .controlAccentColor)
            },
            set: { color in
                guard let hex = NSColor(color).hexRGB else {
                    return
                }
                var settings = settingsStore.settings
                settings[keyPath: keyPath] = hex
                settingsStore.settings = settings
            }
        )
    }

    private func updateLaunchAtLogin(_ shouldLaunch: Bool) {
        do {
            if shouldLaunch {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = shouldLaunch
            serviceError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            serviceError = error.localizedDescription
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Barometer Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settingsStore.exportJSON().write(to: url, options: .atomic)
        } catch {
            showError("Unable to export settings", error: error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settingsStore.importJSON(Data(contentsOf: url))
        } catch {
            showError("Unable to import settings", error: error)
        }
    }

    private func showError(_ message: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private struct ModuleSettingsView: View {
    let module: ModuleID
    let settingsStore: SettingsStore

    private var settings: ModuleSettings {
        settingsStore.settings.modules[module] ?? ModuleSettings()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: moduleBinding(\.isEnabled))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Live Preview").font(.caption).foregroundStyle(.secondary)
                    Image(nsImage: previewImage)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
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
        .navigationTitle(module.displayName)
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
        let scale = appSettings.menuBarScale
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            fontSize: min(14, max(9, appSettings.fontSize)),
            isMonochrome: appSettings.isMonochrome,
            scale: scale,
            horizontalSpacing: appSettings.menuBarSpacing
        )
        let value = module == .cpu ? "42%" : "68%"
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "stacked":
            renderer = StackedLabelRenderer(label: module == .cpu ? "CPU" : "MEM", value: value)
        case "graph":
            renderer = GraphRenderer(values: [0.2, 0.35, 0.28, 0.7, 0.48, 0.62], style: settings.graphStyle)
        case "perCore":
            renderer = GraphRenderer(values: [0.2, 0.8, 0.45, 0.62, 0.25, 0.7], style: .bars, width: 34)
        case "bar":
            renderer = GraphRenderer(values: [0.68], style: .bars, width: 14)
        case "iconText":
            renderer = IconTextRenderer(symbolName: "cpu", text: value)
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

private struct FutureModuleSettingsView: View {
    let module: ModuleID

    var body: some View {
        ContentUnavailableView(
            "\(module.displayName) arrives in a later phase",
            systemImage: module.symbolName,
            description: Text("Its permanent menu-bar identity is already reserved.")
        )
        .navigationTitle(module.displayName)
    }
}

private extension ModuleID {
    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .disks: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .battery: "battery.75percent"
        case .weather: "cloud.sun"
        case .time: "clock"
        case .combined: "rectangle.3.group"
        }
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let integer = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((integer >> 16) & 0xFF) / 255,
            green: CGFloat((integer >> 8) & 0xFF) / 255,
            blue: CGFloat(integer & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexRGB: String? {
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
