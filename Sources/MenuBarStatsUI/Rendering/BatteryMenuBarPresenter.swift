import AppKit
import MenuBarStatsCore
import SystemSources

/// Converts Battery samples into compact, stable menu bar content.
@MainActor
public enum BatteryMenuBarPresenter {
    /// Renders the Battery percentage inside a compact battery glyph.
    public static func content(
        sample: BatterySample?,
        moduleSettings: ModuleSettings,
        batterySettings: BatterySettings,
        context: RenderContext
    ) -> StatusItemContent {
        guard let sample else {
            return StatusItemContent(
                image: renderer(percent: nil, mode: moduleSettings.mode).render(in: context),
                accessibilityValue: "Battery unavailable"
            )
        }
        let renderContext = warningContextIfNeeded(
            sample: sample,
            settings: batterySettings,
            context: context
        )
        let state = stateDescription(sample.state)
        return StatusItemContent(
            image: renderer(percent: sample.chargePercent, mode: moduleSettings.mode).render(in: renderContext),
            accessibilityValue: String(format: "Battery %.1f percent, %@", sample.chargePercent, state)
        )
    }

    private static func renderer(percent: Double?, mode: String) -> any MenuBarRenderer {
        guard mode == "labeledPercentage" else {
            return BatteryPercentRenderer(percent: percent)
        }
        let value = percent.map { String(format: "%.0f%%", $0) } ?? "—"
        return StackedLabelRenderer(label: "BAT", value: value, reservedValue: "100%")
    }

    static func symbolName(for sample: BatterySample) -> String {
        let level: String
        switch sample.chargePercent {
        case 88...: level = "100"
        case 63...: level = "75"
        case 38...: level = "50"
        case 13...: level = "25"
        default: level = "0"
        }
        let base = "battery.\(level)percent"
        return sample.isCharging ? "\(base).bolt" : base
    }

    private static func warningContextIfNeeded(
        sample: BatterySample,
        settings: BatterySettings,
        context: RenderContext
    ) -> RenderContext {
        guard !sample.isExternalConnected,
            sample.chargePercent <= Double(settings.lowBatteryThresholdPercent)
        else {
            return context
        }
        return RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: MenuBarPalette(light: context.warningColor, dark: context.warningColor),
            graphPalette: context.graphPalette,
            fillPalette: context.fillPalette,
            warningPalette: context.warningPalette,
            criticalPalette: context.criticalPalette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: context.scale,
            backingScaleFactor: context.backingScaleFactor,
            graphOpacity: context.graphOpacity,
            fontWeight: context.fontWeight
        )
    }

    private static func stateDescription(_ state: BatteryChargeState) -> String {
        switch state {
        case .charging: "charging"
        case .discharging: "discharging"
        case .full: "fully charged"
        case .onAC: "connected to power"
        }
    }
}
