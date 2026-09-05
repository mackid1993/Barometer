import Foundation
import MenuBarStatsCore

/// Converts Memory samples into labeled, stable menu bar content.
@MainActor
enum MemoryMenuBarPresenter {
    /// Renders the selected Memory presentation mode.
    static func content(
        sample: MemorySample?,
        history: [HistoryEntry<MemorySample.GraphValue>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let usedPercent = sample.map { $0.total > 0 ? Double($0.used) / Double($0.total) * 100 : 0 } ?? 0
        let usedText = sample.map { _ in String(format: "%.0f%%", usedPercent) } ?? "—"
        let pressureText = sample.map { String(format: "%.0f%%", $0.pressurePercent) } ?? "—"
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "pressurePercentage":
            renderer = TextRenderer(
                text: pressureText,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        case "graph":
            renderer = GraphRenderer(
                values: history.map { value in
                    value.value.usedFraction
                },
                style: settings.graphStyle
            )
        case "bar":
            renderer = GraphRenderer(values: [usedPercent / 100], style: .bars, width: 14)
        case "stacked":
            renderer = StackedLabelRenderer(label: "MEM", value: usedText, reservedValue: "100%")
        default:
            renderer = TextRenderer(
                text: usedText,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        }
        guard let sample else {
            return StatusItemContent(image: renderer.render(in: context), accessibilityValue: "Memory unavailable")
        }
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: String(
                format: "Memory %.1f percent used, pressure %.1f percent",
                usedPercent,
                sample.pressurePercent
            )
        )
    }
}
