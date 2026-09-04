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
        calendarAccessAction: @escaping @MainActor () -> Void,
        applyMenuBarChangesAction: @escaping @MainActor () -> Void
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
            applyMenuBarChangesAction: applyMenuBarChangesAction,
            navigationModel: navigationModel
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Barometer Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 780, height: 580))
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        self.navigationModel = navigationModel
    }

    /// Brings the settings window to the front.
    public func show(module: ModuleID? = nil) {
        navigationModel?.open(module: module)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

enum SettingsSelection: Hashable {
    case general
    case module(ModuleID)
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .module(let module): module.settingsTitle
        case .about: "About"
        }
    }
}

@MainActor
@Observable
final class SettingsNavigationModel {
    var selection: SettingsSelection? = .general

    func open(module: ModuleID?) {
        selection = module.map(SettingsSelection.module) ?? .general
    }
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
    let applyMenuBarChangesAction: @MainActor () -> Void
    @Bindable var navigationModel: SettingsNavigationModel

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationModel.selection) {
                SettingsSidebarRow(
                    symbolName: "gearshape.fill",
                    title: "General",
                    accent: ModuleAccent(primary: Color(hex: 0x64748B), secondary: Color(hex: 0x94A3B8))
                )
                .tag(SettingsSelection.general)

                Section("Modules") {
                    ForEach(ModuleID.allCases, id: \.self) { module in
                        SettingsSidebarRow(
                            symbolName: module.symbolName,
                            title: module.settingsTitle,
                            accent: ModuleAccent.resolve(settingsStore.settings, module: module)
                        )
                        .tag(SettingsSelection.module(module))
                    }
                }

                SettingsSidebarRow(
                    symbolName: "info.circle.fill",
                    title: "About Barometer",
                    accent: ModuleAccent(primary: Color(hex: 0x2F7CF6), secondary: Color(hex: 0x6BA4FF))
                )
                .tag(SettingsSelection.about)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch navigationModel.selection ?? .general {
                    case .general:
                        GeneralSettingsView(settingsStore: settingsStore)
                    case .module(.cpu):
                        ModuleSettingsView(module: .cpu, settingsStore: settingsStore)
                    case .module(.memory):
                        ModuleSettingsView(module: .memory, settingsStore: settingsStore)
                    case .module(.gpu):
                        GPUSettingsView(store: gpuStore, settingsStore: settingsStore)
                    case .module(.battery):
                        BatterySettingsView(settingsStore: settingsStore)
                    case .module(.time):
                        TimeSettingsView(
                            store: timeStore,
                            settingsStore: settingsStore,
                            requestCalendarAccess: calendarAccessAction
                        )
                    case .module(.combined):
                        CombinedSettingsView(settingsStore: settingsStore)
                    case .module(.weather):
                        WeatherSettingsView(settingsStore: settingsStore)
                    case .module(.network):
                        NetworkSettingsView(store: networkStore, settingsStore: settingsStore)
                    case .module(.disks):
                        DiskSettingsView(store: diskStore, settingsStore: settingsStore)
                    case .module(.sensors):
                        SensorSettingsView(store: sensorStore, settingsStore: settingsStore)
                    case .about:
                        AboutSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if settingsStore.hasPendingMenuBarChanges {
                    PendingMenuBarChangesBar(
                        previewSettings: settingsStore.settingsIncludingPendingMenuBarChanges,
                        applyAction: applyMenuBarChangesAction,
                        discardAction: settingsStore.discardPendingMenuBarChanges
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: settingsStore.hasPendingMenuBarChanges)
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
                LabeledContent("Login item status", value: launchAtLoginStatus)
                if isRunningFromDistributionFolder {
                    Label(
                        "This copy is running from dist. Install Barometer in Applications before enabling login.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                Text(automaticSizingCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Graph opacity")
                    Slider(value: appBinding(\.graphOpacity), in: 0.1...1, step: 0.05)
                    Text(settingsStore.settings.graphOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
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
                    let preset =
                        settings.appearancePreset == .custom
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
        .settingsPane(
            symbolName: "gearshape.fill",
            title: "General",
            subtitle: "Launch behavior, sampling, automatic sizing, and the menu bar palette.",
            accent: ModuleAccent(primary: Color(hex: 0x64748B), secondary: Color(hex: 0x94A3B8)),
            preview: appearancePreview
        )
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
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
            fontSize: settings.effectiveMenuBarFontSize,
            isMonochrome: settings.isMonochrome,
            scale: settings.effectiveMenuBarScale,
            graphOpacity: settings.graphOpacity,
            fontWeight: settings.fontWeight
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

    private var automaticSizingCaption: String {
        let settings = settingsStore.settingsIncludingPendingMenuBarChanges
        return String(
            format: "Barometer uses %.0f pt text and %.0f%% graphics for %d active widgets. "
                + "Visibility changes take effect when you apply them.",
            settings.effectiveMenuBarFontSize,
            settings.effectiveMenuBarScale * 100,
            settings.enabledMenuBarItemCount
        )
    }

    private var launchAtLoginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .requiresApproval: "Needs approval in System Settings"
        case .notFound: "Unavailable for this app copy"
        case .notRegistered: "Disabled"
        @unknown default: "Unknown"
        }
    }

    private var isRunningFromDistributionFolder: Bool {
        Bundle.main.bundleURL.pathComponents.contains("dist")
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

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
    }

    var body: some View {
        let accent = ModuleAccent(primary: Color(hex: 0x2F7CF6), secondary: Color(hex: 0x22D3EE))
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(accent.gradient)
                        .frame(width: 150, height: 150)
                        .blur(radius: 34)
                        .opacity(0.45)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                }
                .padding(.top, 12)
                VStack(spacing: 6) {
                    Text("Barometer")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Chip(text: "Version \(version) (\(build))", color: accent.primary, symbol: "tag.fill")
                }
                Text(
                    "A detailed, customizable system monitor for the macOS menu bar, built to stay stable with "
                        + "menu bar managers on macOS 27."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                HStack(spacing: 10) {
                    if let sourceURL = URL(string: "https://github.com/mackid1993/Barometer") {
                        Link(destination: sourceURL) {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(.glassProminent)
                    }
                    if let weatherURL = URL(string: "https://open-meteo.com/") {
                        Link(destination: weatherURL) {
                            Label("Open-Meteo", systemImage: "cloud.sun.fill")
                        }
                        .buttonStyle(.glass)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Credits")
                        MetricRow(label: "License", value: "MIT", symbol: "doc.text", tint: accent.primary)
                        MetricRow(
                            label: "Weather data", value: "Open-Meteo.com (CC BY 4.0)", symbol: "cloud.sun",
                            tint: accent.secondary)
                        MetricRow(
                            label: "Hardware sources", value: "IOKit, IOReport, SMC (read-only)", symbol: "cpu",
                            tint: accent.primary)
                    }
                }
                .frame(maxWidth: 460)
                Spacer(minLength: 20)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
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

extension ModuleID {
    /// Sidebar and pane title.
    ///
    /// Separate from `displayName`, which is the permanent accessibility label a menu bar manager
    /// pairs with an autosave name and can never change.
    var settingsTitle: String {
        self == .combined ? "Stacks" : displayName
    }

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
