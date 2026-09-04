import AppKit
import MenuBarStatsCore
import SystemSources

/// Converts Battery samples into compact, stable menu bar content.
@MainActor
public enum BatteryMenuBarPresenter {
    /// Renders the selected Battery presentation mode.
    public static func content(
        sample: BatterySample?,
        moduleSettings: ModuleSettings,
        batterySettings: BatterySettings,
        context: RenderContext
    ) -> StatusItemContent {
        guard let sample else {
            return StatusItemContent(
                image: StackedLabelRenderer(label: "BAT", value: "—", reservedValue: "100%").render(in: context),
                accessibilityValue: "Battery unavailable"
            )
        }
        let renderContext = warningContextIfNeeded(
            sample: sample,
            settings: batterySettings,
            context: context
        )
        let percent = String(format: "%.0f%%", sample.chargePercent)
        let renderer: any MenuBarRenderer
        switch moduleSettings.mode {
        case "icon":
            renderer = SymbolRenderer(
                symbolName: symbolName(for: sample),
                reservedSymbolName: "battery.100percent"
            )
        case "time":
            renderer = StackedLabelRenderer(
                label: sample.isCharging ? "FULL" : "LEFT",
                value: BatteryPresentation.time(minutes: sample.timeRemainingMinutes),
                reservedValue: "99:59"
            )
        case "wattage":
            renderer = StackedLabelRenderer(
                label: sample.isExternalConnected ? "IN" : "USE",
                value: BatteryPresentation.power(watts: sample.wattageWatts),
                reservedValue: "99.9W"
            )
        default:
            renderer = StackedLabelRenderer(label: "BAT", value: percent, reservedValue: "100%")
        }
        let state = stateDescription(sample.state)
        return StatusItemContent(
            image: renderer.render(in: renderContext),
            accessibilityValue: String(format: "Battery %.1f percent, %@", sample.chargePercent, state)
        )
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
            horizontalSpacing: context.horizontalSpacing,
            graphOpacity: context.graphOpacity,
            fontWeight: context.fontWeight,
            usesCompactLayout: context.usesCompactLayout
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
