import AppKit
import MenuBarStatsCore
import SwiftUI

/// Network-specific menu bar, interface, unit, privacy, and graph preferences.
struct NetworkSettingsView: View {
    let store: ModuleStore<NetworkSample>
    let settingsStore: SettingsStore

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.network] ?? ModuleSettings(mode: "twoLine")
    }

    private var networkSettings: NetworkSettings {
        settingsStore.settings.network
    }

    var body: some View {
        let _ = store.revision
        Form {
            Section {
                Toggle("Show in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: .network))
            }

            Section("Menu Bar") {
                Picker("Display", selection: moduleBinding(\.mode)) {
                    Text("Download and upload rows").tag("twoLine")
                    Text("Arrows and rates").tag("arrows")
                    Text("NET label and download").tag("stacked")
                    Text("Activity graph").tag("graph")
                }
                Picker("Rate order", selection: networkBinding(\.rateOrder)) {
                    Text("Upload then download").tag(NetworkRateOrder.uploadThenDownload)
                    Text("Download then upload").tag(NetworkRateOrder.downloadThenUpload)
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

            Section("Connection") {
                Picker("Interface", selection: networkBinding(\.selectedInterfaceName)) {
                    Text("Automatic").tag(String?.none)
                    ForEach(availableInterfaces, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                Picker("Rate unit", selection: networkBinding(\.rateUnit)) {
                    Text("Bytes per second").tag(NetworkRateUnit.bytes)
                    Text("Bits per second").tag(NetworkRateUnit.bits)
                }
                Stepper(value: networkBinding(\.decimalPlaces), in: 0...2) {
                    LabeledContent("Decimal places", value: "\(networkSettings.decimalPlaces)")
                }
                Toggle("Show public IP addresses", isOn: networkBinding(\.showsPublicIP))
                Text("Public IP lookup contacts ipify.org only when this option is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Graph Scale") {
                Picker("Scale", selection: networkBinding(\.graphScale)) {
                    Text("Automatic").tag(NetworkGraphScale.automatic)
                    Text("Fixed").tag(NetworkGraphScale.fixed)
                }
                if networkSettings.graphScale == .fixed {
                    HStack {
                        Text("Maximum")
                        Slider(value: fixedMaximumMegabytesBinding, in: 1...1_000, step: 1)
                        Text("\(Int(fixedMaximumMegabytesBinding.wrappedValue)) MB/s")
                            .monospacedDigit()
                            .frame(width: 82, alignment: .trailing)
                    }
                }
            }

            Section("Dropdown") {
                Toggle("Show top network activity", isOn: moduleBinding(\.showsProcesses))
                Stepper(value: moduleBinding(\.processCount), in: 1...10) {
                    Text("Process count: \(moduleSettings.processCount)")
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
        .settingsPane(module: .network, settings: settingsStore.settings, preview: previewImage)
    }

    private var availableInterfaces: [String] {
        store.latestSample?.interfaces
            .filter { $0.isUp && !$0.isLoopback }
            .map(\.name)
            .sorted(using: .localizedStandard) ?? []
    }

    private var previewImage: NSImage {
        let appSettings = settingsStore.settings
        let color = NSColor(networkHexString: appSettings.darkColor(for: moduleSettings)) ?? .controlAccentColor
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            fontSize: appSettings.effectiveMenuBarFontSize,
            isMonochrome: appSettings.isMonochrome,
            scale: appSettings.effectiveMenuBarScale
        )
        let renderer: any MenuBarRenderer
        let download = NetworkRateFormatter.compactString(
            bytesPerSecond: 1_200_000,
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let upload = NetworkRateFormatter.compactString(
            bytesPerSecond: 82_000,
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let placeholder = NetworkRateFormatter.compactPlaceholder(
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        switch moduleSettings.mode {
        case "arrows":
            let text =
                networkSettings.rateOrder == .uploadThenDownload
                ? "↑\(upload) ↓\(download)"
                : "↓\(download) ↑\(upload)"
            let reserved =
                networkSettings.rateOrder == .uploadThenDownload
                ? "↑\(placeholder) ↓\(placeholder)"
                : "↓\(placeholder) ↑\(placeholder)"
            renderer = TextRenderer(
                text: text,
                reservedText: moduleSettings.usesFixedWidth ? reserved : nil
            )
        case "stacked":
            renderer = StackedLabelRenderer(label: "NET", value: download, reservedValue: placeholder)
        case "graph":
            renderer = GraphRenderer(values: [0.1, 0.35, 0.22, 0.8, 0.55, 0.7], style: moduleSettings.graphStyle)
        default:
            let uploadFirst = networkSettings.rateOrder == .uploadThenDownload
            renderer =
                uploadFirst
                ? NetworkRateStackRenderer(
                    top: "↑\(upload)",
                    bottom: "↓\(download)",
                    reservedTop: "↑\(placeholder)",
                    reservedBottom: "↓\(placeholder)"
                )
                : NetworkRateStackRenderer(download: download, upload: upload, reservedValue: placeholder)
        }
        return renderer.render(in: context)
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { moduleSettings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.network] ?? ModuleSettings(mode: "twoLine")
                settings[keyPath: keyPath] = value
                appSettings.modules[.network] = settings
                settingsStore.settings = appSettings
            }
        )
    }

    private func networkBinding<Value>(_ keyPath: WritableKeyPath<NetworkSettings, Value>) -> Binding<Value> {
        Binding(
            get: { networkSettings[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                appSettings.network[keyPath: keyPath] = value
                settingsStore.settings = appSettings
            }
        )
    }

    private var fixedMaximumMegabytesBinding: Binding<Double> {
        Binding(
            get: { networkSettings.fixedGraphMaximumBytesPerSecond / 1_000_000 },
            set: { value in
                var appSettings = settingsStore.settings
                appSettings.network.fixedGraphMaximumBytesPerSecond = value * 1_000_000
                settingsStore.settings = appSettings
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(networkHexString: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor)
            },
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
                var settings = appSettings.modules[.network] ?? ModuleSettings(mode: "twoLine")
                settings[keyPath: keyPath] = hex
                appSettings.modules[.network] = settings
                settingsStore.settings = appSettings
            }
        )
    }
}

extension NSColor {
    fileprivate convenience init?(networkHexString: String) {
        let value = networkHexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let integer = UInt64(value, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((integer >> 16) & 0xFF) / 255,
            green: CGFloat((integer >> 8) & 0xFF) / 255,
            blue: CGFloat(integer & 0xFF) / 255,
            alpha: 1
        )
    }
}
