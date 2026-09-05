import Foundation
import MenuBarStatsCore

/// Converts CPU samples into labeled, stable menu bar content.
@MainActor
enum CPUMenuBarPresenter {
    /// Renders the selected CPU presentation mode.
    static func content(
        sample: CPUSample?,
        history: [HistoryEntry<CPUSample.GraphValue>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let percentage = sample.map { String(format: "%.0f%%", $0.totalPercent) } ?? "—"
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "graph":
            renderer = GraphRenderer(
                values: history.map { $0.value.totalPercent / 100 },
                style: settings.graphStyle
            )
        case "perCore":
            let coreValues =
                sample?.perCore.map { $0.usagePercent / 100 }
                ?? Array(repeating: 0, count: ProcessInfo.processInfo.activeProcessorCount)
            renderer = GraphRenderer(
                values: coreValues,
                style: .bars,
                width: max(32, CGFloat(coreValues.count) * 3)
            )
        case "stacked":
            renderer = StackedLabelRenderer(label: "CPU", value: percentage, reservedValue: "100%")
        case "iconText":
            renderer = IconTextRenderer(symbolName: "cpu", text: percentage, reservedText: "100%")
        default:
            renderer = TextRenderer(
                text: percentage,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        }
        guard let sample else {
            return StatusItemContent(image: renderer.render(in: context), accessibilityValue: "CPU unavailable")
        }
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: String(format: "CPU %.1f percent", sample.totalPercent)
        )
    }
}
