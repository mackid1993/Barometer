import AppKit
import MenuBarStatsCore
import SwiftUI

/// Resolves customizable semantic colors for SwiftUI detail views.
@MainActor
enum AppearanceColorResolver {
    static func graph(_ settings: AppSettings, module: ModuleID) -> Color {
        dynamic(
            light: settings.graphLightColor(for: settings.modules[module] ?? ModuleSettings()),
            dark: settings.graphDarkColor(for: settings.modules[module] ?? ModuleSettings()),
            fallback: .controlAccentColor
        )
    }

    static func fill(_ settings: AppSettings, module: ModuleID) -> Color {
        dynamic(
            light: settings.fillLightColor(for: settings.modules[module] ?? ModuleSettings()),
            dark: settings.fillDarkColor(for: settings.modules[module] ?? ModuleSettings()),
            fallback: .controlAccentColor
        )
    }

    static func warning(_ settings: AppSettings, module: ModuleID) -> Color {
        dynamic(
            light: settings.warningLightColor(for: settings.modules[module] ?? ModuleSettings()),
            dark: settings.warningDarkColor(for: settings.modules[module] ?? ModuleSettings()),
            fallback: .systemOrange
        )
    }

    static func critical(_ settings: AppSettings, module: ModuleID) -> Color {
        dynamic(
            light: settings.criticalLightColor(for: settings.modules[module] ?? ModuleSettings()),
            dark: settings.criticalDarkColor(for: settings.modules[module] ?? ModuleSettings()),
            fallback: .systemRed
        )
    }

    private static func dynamic(light: String, dark: String, fallback: NSColor) -> Color {
        let lightColor = NSColor(hex: light) ?? fallback
        let darkColor = NSColor(hex: dark) ?? fallback
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}
