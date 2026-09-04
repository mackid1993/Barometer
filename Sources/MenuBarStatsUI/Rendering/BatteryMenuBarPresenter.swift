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
                image: image(sample: nil, mode: moduleSettings.mode, context: context),
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
            image: image(sample: sample, mode: moduleSettings.mode, context: renderContext),
            accessibilityValue: accessibilityValue(sample: sample, state: state, mode: moduleSettings.mode)
        )
    }

    /// Every Battery presentation shares one canvas.
    ///
    /// A status item keeps a single length for the life of the process, so a presentation that drew
    /// a different width would squeeze its image until the next launch and then move the item. Each
    /// mode is instead drawn centered on the widest canvas any mode can need, and switching styles
    /// changes only what the item shows.
    private static func image(sample: BatterySample?, mode: String, context: RenderContext) -> NSImage {
        let drawn = renderer(sample: sample, mode: mode).render(in: context)
        let width = sharedWidth(context: context)
        guard width - drawn.size.width > 0.01 else {
            return drawn
        }
        // Centered, not flush left. `StatusItemRendering.image(_:framedTo:)` pins its content to the
        // leading edge, which is correct where it frames to a latched item length but would leave a
        // narrower presentation hanging off center inside this shared canvas.
        let centered = NSImage(size: NSSize(width: width, height: drawn.size.height), flipped: false) { rect in
            drawn.draw(
                in: NSRect(
                    origin: NSPoint(x: ((rect.width - drawn.size.width) / 2).rounded(), y: 0),
                    size: drawn.size
                )
            )
            return true
        }
        centered.isTemplate = drawn.isTemplate
        return centered
    }

    /// Widest canvas any presentation needs, measured from the reserved placeholders alone.
    private static func sharedWidth(context: RenderContext) -> CGFloat {
        let placeholder = BatterySample(
            snapshot: BatterySnapshot(
                name: "Internal Battery",
                chargePercent: 100,
                state: .discharging,
                isExternalConnected: false,
                isCharging: false,
                isFullyCharged: false,
                healthPercent: nil,
                cycleCount: nil,
                temperatureCelsius: nil,
                voltageVolts: nil,
                amperageAmps: nil,
                wattageWatts: nil,
                condition: nil,
                adapter: nil,
                isLowPowerModeEnabled: false,
                timeToEmptyMinutes: nil,
                timeToFullMinutes: nil
            )
        )
        return modes.reduce(CGFloat(0)) { widest, mode in
            max(widest, renderer(sample: placeholder, mode: mode).render(in: context).size.width)
        }
    }

    /// Every supported presentation identifier.
    static let modes = ["glyphPercentage", "labeledPercentage", "percentageTime", "labeledTime"]

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
        default:
            return BatteryPercentRenderer(percent: sample?.chargePercent)
        }
    }

    /// Every glyph the icon modes can swap to, so the reserved width never changes.
    private static let reservedSymbolNames = [
        "battery.0percent", "battery.25percent", "battery.50percent",
        "battery.75percent", "battery.100percent", "battery.100percent.bolt",
    ]

    /// Whether every glyph the Battery modes can show resolves on this system.
    ///
    /// A missing symbol renders nothing and collapses the icon gap, so the item would change width.
    static var everyReservedSymbolResolves: Bool {
        reservedSymbolNames.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    }

    private static func accessibilityValue(sample: BatterySample, state: String, mode: String) -> String {
        let charge = String(format: "Battery %.1f percent, %@", sample.chargePercent, state)
        guard mode == "labeledTime" || mode == "percentageTime" else {
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
        // SF Symbols publishes a bolt overlay only for the full glyph; `battery.25percent.bolt` and
        // friends do not exist, and asking for one yields no image at all.
        return sample.isCharging ? "battery.100percent.bolt" : "battery.\(level)percent"
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
