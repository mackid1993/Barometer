import AppKit
import MenuBarStatsCore
import SwiftUI

/// GPU menu bar, graph, sampling, and color preferences.
struct GPUSettingsView: View {
    let store: ModuleStore<GPUSample>
    let settingsStore: SettingsStore

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.gpu] ?? ModuleSettings(mode: "percentage")
    }

    var body: some View {
        let _ = store.revision
        Form {
            Section {
                Toggle("Show in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: .gpu))
                LabeledContent(
                    "Live utilization",
                    value: store.latestSample.map {
                        String(format: "%.1f%%", $0.deviceUtilizationPercent)
                    } ?? "Discovering…"
                )
            }
            Section("Menu Bar") {
                Picker("Display", selection: moduleBinding(\.mode)) {
                    Text("GPU label and percentage").tag("percentage")
                    Text("History graph").tag("graph")
                    Text("CPU and GPU rows").tag("combinedCPU")
                }
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
                    Text(String(format: "%.1f s", moduleSettings.interval))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                SamplingIntervalNote()
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .gpu, settings: settingsStore.settings, preview: previewImage)
    }

    /// The GPU item exactly as the menu bar draws it, in whichever mode is selected.
    ///
    /// The presenter behind the real status item renders the preview too, from a sample carrying
    /// plausible readings, so switching modes here shows the shape the menu bar will take rather
    /// than an approximation of it.
    private var previewImage: NSImage {
        let appSettings = settingsStore.settings
        let color = NSColor(hex: appSettings.darkColor(for: moduleSettings)) ?? .controlAccentColor
        let graphColor = NSColor(hex: appSettings.graphDarkColor(for: moduleSettings)) ?? color
        let fillColor = NSColor(hex: appSettings.fillDarkColor(for: moduleSettings)) ?? graphColor
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            graphPalette: MenuBarPalette(light: graphColor, dark: graphColor),
            fillPalette: MenuBarPalette(light: fillColor, dark: fillColor),
            fontSize: appSettings.effectiveMenuBarFontSize,
            isMonochrome: appSettings.isMonochrome,
            scale: appSettings.effectiveMenuBarScale,
            graphOpacity: appSettings.graphOpacity,
            fontWeight: appSettings.fontWeight
        )
        // The history graph needs a run of readings rather than one, so the samples that feed it
        // also supply the latest value the other two modes print.
        let samples = [18.0, 32.0, 26.0, 71.0, 44.0, 58.0, 37.0].enumerated().map { index, percent in
            GPUSample(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                name: "Preview GPU",
                deviceUtilizationPercent: percent
            )
        }
        return GPUMenuBarPresenter.content(
            sample: samples.last,
            history: samples.map { HistoryEntry(timestamp: $0.timestamp, value: $0.graphValue) },
            cpuPercent: 42,
            settings: moduleSettings,
            context: context
        ).image
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { moduleSettings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.gpu] ?? ModuleSettings(mode: "percentage")
                settings[keyPath: keyPath] = value
                appSettings.modules[.gpu] = settings
                settingsStore.settings = appSettings
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor) },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                let hex = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.gpu] ?? ModuleSettings(mode: "percentage")
                settings[keyPath: keyPath] = hex
                appSettings.modules[.gpu] = settings
                settingsStore.settings = appSettings
            }
        )
    }
}
