import AppKit
import MenuBarStatsCore
import Observation
import ServiceManagement
import SwiftUI

/// Owns and presents the MenuBarStats settings window.
@MainActor
public final class SettingsWindowController: NSWindowController {
    private var navigationModel: SettingsNavigationModel?

    /// Creates the settings window controller.
    public convenience init(
        settingsStore: SettingsStore,
        gpuStore: ModuleStore<GPUSample>,
        batteryStore: ModuleStore<BatterySample>,
        timeStore: ModuleStore<TimeSample>,
        networkStore: ModuleStore<NetworkSample>,
        diskStore: ModuleStore<DiskSample>,
        sensorStore: ModuleStore<SensorSample>,
        calendarAccessAction: @escaping @MainActor () -> Void
    ) {
        let navigationModel = SettingsNavigationModel()
        let rootView = SettingsRootView(
            settingsStore: settingsStore,
            gpuStore: gpuStore,
            batteryStore: batteryStore,
            timeStore: timeStore,
            networkStore: networkStore,
            diskStore: diskStore,
            sensorStore: sensorStore,
            calendarAccessAction: calendarAccessAction,
            navigationModel: navigationModel
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
        self.navigationModel = navigationModel
    }

    /// Brings the settings window to the front.
    public func show(module: ModuleID? = nil) {
        navigationModel?.selection = module.map(SettingsSelection.module) ?? .general
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

@MainActor
@Observable
private final class SettingsNavigationModel {
    var selection: SettingsSelection? = .general
}

private struct SettingsRootView: View {
    let settingsStore: SettingsStore
    let gpuStore: ModuleStore<GPUSample>
    let batteryStore: ModuleStore<BatterySample>
    let timeStore: ModuleStore<TimeSample>
    let networkStore: ModuleStore<NetworkSample>
    let diskStore: ModuleStore<DiskSample>
    let sensorStore: ModuleStore<SensorSample>
    let calendarAccessAction: @MainActor () -> Void
    @Bindable var navigationModel: SettingsNavigationModel

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationModel.selection) {
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
            switch navigationModel.selection ?? .general {
            case .general:
                GeneralSettingsView(settingsStore: settingsStore)
            case let .module(module) where module == .cpu || module == .memory:
                ModuleSettingsView(module: module, settingsStore: settingsStore)
            case let .module(module) where module == .gpu:
                GPUSettingsView(store: gpuStore, settingsStore: settingsStore)
            case let .module(module) where module == .battery:
                BatterySettingsView(store: batteryStore, settingsStore: settingsStore)
            case let .module(module) where module == .time:
                TimeSettingsView(
                    store: timeStore,
                    settingsStore: settingsStore,
                    requestCalendarAccess: calendarAccessAction
                )
            case let .module(module) where module == .combined:
                CombinedSettingsView(settingsStore: settingsStore)
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
    @State private var colorModule: ModuleID = .cpu

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
                Picker("Theme", selection: appearancePresetBinding) {
                    ForEach(AppearancePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                        Text(preset.rawValue.capitalized).tag(preset)
                    }
                    if settingsStore.settings.appearancePreset == .custom {
                        Text("Custom").tag(AppearancePreset.custom)
                    }
                }
                Toggle("Monochrome menu bar", isOn: appBinding(\.isMonochrome))
                Picker("Font weight", selection: appBinding(\.fontWeight)) {
                    Text("Regular").tag(MenuBarFontWeight.regular)
                    Text("Medium").tag(MenuBarFontWeight.medium)
                    Text("Semibold").tag(MenuBarFontWeight.semibold)
                }
                Toggle("Compact internal layout", isOn: appBinding(\.usesCompactLayout))
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
                HStack {
                    Text("Graph opacity")
                    Slider(value: appBinding(\.graphOpacity), in: 0.1...1, step: 0.05)
                    Text(settingsStore.settings.graphOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Live Preview").font(.caption).foregroundStyle(.secondary)
                    Image(nsImage: appearancePreview)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Section("Menu Bar Colors") {
                Toggle("Use one palette for every module", isOn: appBinding(\.usesGlobalColors))
                MenuBarColorPickerRows(
                    lightColor: globalColorBinding(\.globalLightColor),
                    darkColor: globalColorBinding(\.globalDarkColor),
                    isDisabled: !settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Graph",
                    light: globalColorBinding(\.globalGraphLightColor),
                    dark: globalColorBinding(\.globalGraphDarkColor),
                    isDisabled: !settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Fill",
                    light: globalColorBinding(\.globalFillLightColor),
                    dark: globalColorBinding(\.globalFillDarkColor),
                    isDisabled: !settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Warning",
                    light: globalColorBinding(\.globalWarningLightColor),
                    dark: globalColorBinding(\.globalWarningDarkColor),
                    isDisabled: !settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Critical",
                    light: globalColorBinding(\.globalCriticalLightColor),
                    dark: globalColorBinding(\.globalCriticalDarkColor),
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

            Section("Per-Module Color Roles") {
                Picker("Module", selection: $colorModule) {
                    ForEach(ModuleID.allCases, id: \.self) { module in Text(module.displayName).tag(module) }
                }
                AppearanceColorRoleRow(
                    role: "Graph",
                    light: moduleRoleColorBinding(\.graphLightColor, dark: false),
                    dark: moduleRoleColorBinding(\.graphDarkColor, dark: true),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Fill",
                    light: moduleRoleColorBinding(\.fillLightColor, dark: false),
                    dark: moduleRoleColorBinding(\.fillDarkColor, dark: true),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Warning",
                    light: moduleRoleColorBinding(\.warningLightColor, dark: false),
                    dark: moduleRoleColorBinding(\.warningDarkColor, dark: true),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                AppearanceColorRoleRow(
                    role: "Critical",
                    light: moduleRoleColorBinding(\.criticalLightColor, dark: false),
                    dark: moduleRoleColorBinding(\.criticalDarkColor, dark: true),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                Button("Reset Colors to Selected Theme") {
                    var settings = settingsStore.settings
                    let preset = settings.appearancePreset == .custom
                        ? AppearancePreset.system
                        : settings.appearancePreset
                    settings.applyTheme(preset)
                    settingsStore.settings = settings
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

    private var appearancePresetBinding: Binding<AppearancePreset> {
        Binding(
            get: { settingsStore.settings.appearancePreset },
            set: { preset in
                var settings = settingsStore.settings
                settings.applyTheme(preset)
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
                settings.appearancePreset = .custom
                settingsStore.settings = settings
            }
        )
    }

    private func moduleRoleColorBinding(
        _ keyPath: WritableKeyPath<ModuleSettings, String?>,
        dark: Bool
    ) -> Binding<Color> {
        Binding(
            get: {
                let module = settingsStore.settings.modules[colorModule] ?? ModuleSettings()
                let fallback = dark ? module.darkColor : module.lightColor
                return Color(nsColor: NSColor(hex: module[keyPath: keyPath] ?? fallback) ?? .controlAccentColor)
            },
            set: { color in
                guard let hex = NSColor(color).hexRGB else { return }
                var settings = settingsStore.settings
                var module = settings.modules[colorModule] ?? ModuleSettings()
                module[keyPath: keyPath] = hex
                settings.modules[colorModule] = module
                settings.appearancePreset = .custom
                settingsStore.settings = settings
            }
        )
    }

    private var appearancePreview: NSImage {
        let settings = settingsStore.settings
        let module = settings.modules[.cpu] ?? ModuleSettings()
        let normal = NSColor(hex: settings.darkColor(for: module)) ?? .white
        let graph = NSColor(hex: settings.graphDarkColor(for: module)) ?? normal
        let fill = NSColor(hex: settings.fillDarkColor(for: module)) ?? graph
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: normal, dark: normal),
            graphPalette: MenuBarPalette(light: graph, dark: graph),
            fillPalette: MenuBarPalette(light: fill, dark: fill),
            fontSize: settings.fontSize,
            isMonochrome: settings.isMonochrome,
            scale: settings.menuBarScale,
            horizontalSpacing: 1,
            graphOpacity: settings.graphOpacity,
            fontWeight: settings.fontWeight,
            usesCompactLayout: settings.usesCompactLayout
        )
        return CombinedRenderer(renderers: [
            StackedLabelRenderer(label: "CPU", value: "42%"),
            GraphRenderer(values: [0.2, 0.45, 0.3, 0.8, 0.55], style: .area, width: 30),
            IconStackRenderer(symbolName: "cloud.sun", text: "72°F"),
        ]).render(in: context)
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

private struct AppearanceColorRoleRow: View {
    let role: String
    let light: Binding<Color>
    let dark: Binding<Color>
    let isDisabled: Bool

    var body: some View {
        HStack {
            Text(role).frame(width: 70, alignment: .leading)
            ColorPicker("Light", selection: light, supportsOpacity: false)
            ColorPicker("Dark", selection: dark, supportsOpacity: false)
        }
        .disabled(isDisabled)
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

extension ModuleID {
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
