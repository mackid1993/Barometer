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
///
/// It stays dark in both appearances because every pane renders its preview for a dark menu bar, with those
/// colors baked into the image. Following the appearance instead left a colored preview white on white. What
/// did need fixing is a monochrome preview: it carries no color of its own and would otherwise take the
/// window's tint, which in Light Mode is black on this near-black ground.
struct MenuBarPreviewStrip: View {
    let image: NSImage

    var body: some View {
        let ink = Color.white
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 10) {
            Text("Live preview")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(ink.opacity(0.55))
            // A preview as wide as every weather mark side by side would otherwise stretch the settings window
            // to fit it, so the strip scrolls instead of growing. A scroll view aligns its content to the
            // leading edge and is flexible in both directions, so the content is given the viewport's width to
            // stay centred the way it was, and the strip is given the image's height so nothing is cropped.
            GeometryReader { viewport in
                ScrollView(.horizontal) {
                    // The strip is always dark, whatever the appearance. A template image carries no color
                    // of its own and takes the current tint, which in Light Mode is black, so a monochrome
                    // preview was drawing black ink on a dark strip. Template previews are tinted for the
                    // strip they sit on; a colored one keeps the colors the renderer baked in.
                    Image(nsImage: image)
                        .renderingMode(image.isTemplate ? .template : .original)
                        .foregroundStyle(ink)
                        .padding(.horizontal, 2)
                        .frame(minWidth: viewport.size.width, alignment: .center)
                }
                .scrollIndicators(.never)
            }
            // A preview built before the first sample can have no height yet, and tying the strip to it made
            // the content vanish until one arrived. The menu bar's own thickness is the floor.
            .frame(height: max(image.size.height, NSStatusBar.system.thickness))
            .frame(maxWidth: .infinity)
            Image(systemName: "wifi")
                .foregroundStyle(ink.opacity(0.75))
            Text("9:41")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(ink.opacity(0.85))
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
                shape.strokeBorder(ink.opacity(0.12), lineWidth: 0.75)
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

/// Prominent commit control for status-item visibility changes that require a clean launch geometry.
struct PendingMenuBarChangesBar: View {
    let previewSettings: AppSettings
    let applyAction: @MainActor () -> Void
    let discardAction: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("Menu bar changes are ready")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(sizingSummary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button("Discard", action: discardAction)
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
            Button(action: applyAction) {
                Label("Apply Changes", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Color.accentColor)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: -2)
    }

    private var sizingSummary: String {
        String(
            format: "%d widgets · %.0f pt text · %.0f%% graphics · Barometer will reopen",
            previewSettings.enabledMenuBarItemCount,
            previewSettings.effectiveMenuBarFontSize,
            previewSettings.effectiveMenuBarScale * 100
        )
    }
}

extension View {
    /// Wraps a settings form with the shared pane header for a module.
    func settingsPane(module: ModuleID, settings: AppSettings, preview: NSImage? = nil) -> some View {
        settingsPane(
            symbolName: module.symbolName,
            title: module.settingsTitle,
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
        case .time: "Clock format, calendar events, and macOS notifications."
        case .combined: "Readings from any module inside independently movable items."
        case .focus: "Current Focus and notification controls."
        case .nowPlaying: "Current media and playback controls."
        }
    }
}
