import AppKit
import SwiftUI

/// Version, credits, and project links for Barometer.
struct AboutSettingsView: View {
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
