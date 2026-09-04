import AppKit
import MenuBarStatsCore
import SwiftUI

/// Header shown above every settings pane: icon tile, title, subtitle, and optional live preview.
struct SettingsPaneHeader: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let accent: ModuleAccent
    var preview: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                IconTile(symbolName: symbolName, accent: accent, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            if let preview {
                MenuBarPreviewStrip(image: preview)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

/// Dark, glassy strip that mimics the menu bar so previews read in context.
struct MenuBarPreviewStrip: View {
    let image: NSImage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 10) {
            Text("Live preview")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Image(nsImage: image)
            Spacer()
            Image(systemName: "wifi")
                .foregroundStyle(.white.opacity(0.75))
            Text("9:41")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            ZStack {
                shape.fill(Color(hex: 0x0B0F19).opacity(0.92))
                shape.fill(
                    LinearGradient(
                        colors: [Color(hex: 0x1E293B).opacity(0.7), Color(hex: 0x0F172A).opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
            }
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .animation(.snappy(duration: 0.3), value: image.size.width)
    }
}

/// Sidebar row with a small gradient icon tile, in the style of System Settings.
struct SettingsSidebarRow: View {
    let symbolName: String
    let title: String
    let accent: ModuleAccent

    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbolName: symbolName, accent: accent, size: 22)
                .shadow(color: .clear, radius: 0)
            Text(title)
        }
        .padding(.vertical, 1)
    }
}

extension View {
    /// Wraps a settings form with the shared pane header for a module.
    func settingsPane(module: ModuleID, settings: AppSettings, preview: NSImage? = nil) -> some View {
        settingsPane(
            symbolName: module.symbolName,
            title: module.displayName,
            subtitle: module.settingsSubtitle,
            accent: ModuleAccent.resolve(settings, module: module),
            preview: preview
        )
    }

    /// Wraps a settings form with the shared pane header.
    func settingsPane(
        symbolName: String,
        title: String,
        subtitle: String,
        accent: ModuleAccent,
        preview: NSImage? = nil
    ) -> some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                symbolName: symbolName, title: title, subtitle: subtitle, accent: accent, preview: preview)
            self
        }
        .navigationTitle(title)
    }
}

extension ModuleID {
    /// One-line description shown under the module name in Settings.
    var settingsSubtitle: String {
        switch self {
        case .cpu: "Utilization, per-core load, and top processes."
        case .gpu: "Graphics utilization, memory, frequency, and power."
        case .memory: "Usage breakdown, pressure, swap, and top processes."
        case .disks: "Volume capacity and physical disk activity."
        case .network: "Throughput, interfaces, addresses, and Wi-Fi."
        case .sensors: "Temperatures, fans, and power from the hardware."
        case .battery: "Charge, health, adapter, and Bluetooth batteries."
        case .weather: "Conditions and forecasts from Open-Meteo."
        case .time: "Clock format, world clocks, and calendar events."
        case .combined: "Several modules inside one movable menu bar item."
        }
    }
}
