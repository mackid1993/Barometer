import AppKit
import MenuBarStatsCore
import ServiceManagement
import SwiftUI

/// Application-wide preferences: launch behavior, appearance, palette, units, and settings import/export.
struct GeneralSettingsView: View {
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

extension NSColor {
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
