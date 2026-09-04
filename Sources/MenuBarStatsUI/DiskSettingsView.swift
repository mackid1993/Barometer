import AppKit
import MenuBarStatsCore
import SwiftUI

/// Disk-specific menu bar, volume, filtering, and unit preferences.
struct DiskSettingsView: View {
    let store: ModuleStore<DiskSample>
    let settingsStore: SettingsStore

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.disks] ?? ModuleSettings(mode: "activityGraph")
    }

    private var diskSettings: DiskSettings {
        settingsStore.settings.disks
    }

    var body: some View {
        let _ = store.revision
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
                    Text("Read and write activity").tag("activityGraph")
                    Text("Free percentage").tag("freePercentage")
                    Text("Free space").tag("freeBytes")
                    Text("Read and write rates").tag("rates")
                }
                Toggle("Keep item width fixed", isOn: moduleBinding(\.usesFixedWidth))
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

            Section("Volumes") {
                Picker("Free-space volume", selection: diskBinding(\.selectedVolumeID)) {
                    Text("Automatic (\(automaticVolumeName))").tag(String?.none)
                    ForEach(availableVolumes, id: \.id) { volume in
                        Text(volume.name).tag(Optional(volume.id))
                    }
                }
                Toggle("Hide system volumes", isOn: diskBinding(\.hidesSystemVolumes))
                if !configurableVolumes.isEmpty {
                    DisclosureGroup("Volumes shown in Barometer") {
                        ForEach(configurableVolumes, id: \.id) { volume in
                            Toggle(isOn: volumeVisibilityBinding(volume.id)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(volume.name)
                                    Text(volume.mountPoint)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Picker("Units", selection: diskBinding(\.unitSystem)) {
                    Text("Binary (GiB, MiB)").tag(DiskUnitSystem.binary)
                    Text("Decimal (GB, MB)").tag(DiskUnitSystem.decimal)
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
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Disks")
    }

    private var availableVolumes: [DiskVolumeSample] {
        store.latestSample?.visibleVolumes(settings: diskSettings) ?? []
    }

    private var configurableVolumes: [DiskVolumeSample] {
        store.latestSample?.volumes.filter { volume in
            guard volume.totalBytes > 0 else {
                return false
            }
            return !diskSettings.hidesSystemVolumes
                || volume.mountPoint == "/"
                || !volume.mountPoint.hasPrefix("/System/Volumes/")
        } ?? []
    }

    private var automaticVolumeName: String {
        availableVolumes.first(where: { $0.mountPoint == "/" })?.name ?? "startup disk"
    }

    private var previewImage: NSImage {
        let appSettings = settingsStore.settings
        let color = NSColor(hex: appSettings.darkColor(for: moduleSettings)) ?? .controlAccentColor
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            fontSize: min(14, max(9, appSettings.fontSize)),
            isMonochrome: appSettings.isMonochrome,
            scale: appSettings.menuBarScale,
            horizontalSpacing: appSettings.menuBarSpacing
        )
        let renderer: any MenuBarRenderer
        switch moduleSettings.mode {
        case "freePercentage":
            renderer = TextRenderer(text: "35%", reservedText: moduleSettings.usesFixedWidth ? "100%" : nil)
        case "freeBytes":
            renderer = TextRenderer(text: diskSettings.unitSystem == .binary ? "321GiB" : "345GB")
        case "rates":
            renderer = NetworkRateStackRenderer(
                download: diskSettings.unitSystem == .binary ? "1.2MiB/s" : "1.2MB/s",
                upload: diskSettings.unitSystem == .binary ? "82KiB/s" : "82KB/s",
                reservedValue: diskSettings.unitSystem == .binary ? "999GiB/s" : "999GB/s"
            )
        default:
            renderer = DiskActivityGraphRenderer(
                reads: [0.1, 0.7, 0.25, 0.85, 0.2, 0.55],
                writes: [0.05, 0.2, 0.8, 0.15, 0.65, 0.3],
                style: moduleSettings.graphStyle
            )
        }
        return renderer.render(in: context)
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { moduleSettings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.disks] ?? ModuleSettings(mode: "activityGraph")
                settings[keyPath: keyPath] = value
                appSettings.modules[.disks] = settings
                settingsStore.settings = appSettings
            }
        )
    }

    private func diskBinding<Value>(_ keyPath: WritableKeyPath<DiskSettings, Value>) -> Binding<Value> {
        Binding(
            get: { diskSettings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                appSettings.disks[keyPath: keyPath] = value
                settingsStore.settings = appSettings
            }
        )
    }

    private func volumeVisibilityBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !diskSettings.hiddenVolumeIDs.contains(id) },
            set: { isVisible in
                var appSettings = settingsStore.settings
                if isVisible {
                    appSettings.disks.hiddenVolumeIDs.remove(id)
                } else {
                    appSettings.disks.hiddenVolumeIDs.insert(id)
                }
                settingsStore.settings = appSettings
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor) },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else {
                    return
                }
                let hex = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.disks] ?? ModuleSettings(mode: "activityGraph")
                settings[keyPath: keyPath] = hex
                appSettings.modules[.disks] = settings
                settingsStore.settings = appSettings
            }
        )
    }
}
