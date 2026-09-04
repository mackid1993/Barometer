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
                image: renderer(sample: nil, mode: moduleSettings.mode).render(in: context),
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
            image: renderer(sample: sample, mode: moduleSettings.mode).render(in: renderContext),
            accessibilityValue: accessibilityValue(sample: sample, state: state, mode: moduleSettings.mode)
        )
    }

    /// Menu bar text for the estimate that matches the battery's current direction.
    static func timeText(sample: BatterySample?) -> String {
        BatteryTimeFormatter.compact(minutes: sample?.remainingMinutes)
    }

    private static func percentText(_ sample: BatterySample?) -> String {
        sample.map { String(format: "%.0f%%", $0.chargePercent) } ?? "—"
    }

    private static func renderer(sample: BatterySample?, mode: String) -> any MenuBarRenderer {
        switch mode {
        case "labeledPercentage":
            return StackedLabelRenderer(label: "BAT", value: percentText(sample), reservedValue: "100%")
        case "labeledTime":
            return StackedLabelRenderer(
                label: "BAT",
                value: timeText(sample: sample),
                reservedValue: BatteryTimeFormatter.reservedCompact
            )
        case "percentageTime":
            // Both rows carry live values, so this uses the equal-weight two-row renderer rather
            // than the dimmed label-over-value stack.
            return NetworkRateStackRenderer(
                top: percentText(sample),
                bottom: timeText(sample: sample),
                reservedTop: "100%",
                reservedBottom: BatteryTimeFormatter.reservedCompact
            )
        case "glyphTime":
            return IconTextRenderer(
                symbolName: sample.map(symbolName) ?? "battery.0percent",
                text: timeText(sample: sample),
                reservedText: BatteryTimeFormatter.reservedCompact,
                reservedSymbolNames: reservedSymbolNames
            )
        default:
            return BatteryPercentRenderer(percent: sample?.chargePercent)
        }
    }

    /// Every glyph the icon modes can swap to, so the reserved width never changes.
    private static let reservedSymbolNames = [
        "battery.0percent", "battery.25percent", "battery.50percent",
        "battery.75percent", "battery.100percent", "battery.100percent.bolt",
    ]

    private static func accessibilityValue(sample: BatterySample, state: String, mode: String) -> String {
        let charge = String(format: "Battery %.1f percent, %@", sample.chargePercent, state)
        guard mode == "labeledTime" || mode == "percentageTime" || mode == "glyphTime" else {
            return charge
        }
        guard let remaining = BatteryTimeFormatter.long(minutes: sample.remainingMinutes) else {
            return sample.isEstimatingTime ? "\(charge), time remaining calculating" : charge
        }
        return sample.isCharging
            ? "\(charge), \(remaining) until full"
            : "\(charge), \(remaining) remaining"
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
