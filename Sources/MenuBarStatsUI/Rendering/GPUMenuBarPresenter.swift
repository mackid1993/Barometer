import MenuBarStatsCore

/// Converts GPU samples into labeled, stable menu bar content.
@MainActor
public enum GPUMenuBarPresenter {
    /// Renders the selected GPU presentation mode.
    public static func content(
        sample: GPUSample?,
        history: [HistoryEntry<GPUSample.GraphValue>],
        cpuPercent: Double?,
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let percentage = sample.map { String(format: "%.0f%%", $0.deviceUtilizationPercent) } ?? "—"
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "graph":
            renderer = GraphRenderer(
                values: history.suffix(90).map { $0.value.deviceUtilizationPercent / 100 },
                style: settings.graphStyle
            )
        case "combinedCPU":
            let cpu = cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—"
            renderer = SensorStackRenderer(values: [
                SensorStackValue(label: "CPU", value: cpu, reservedValue: "100%"),
                SensorStackValue(label: "GPU", value: percentage, reservedValue: "100%"),
            ])
        default:
            renderer = StackedLabelRenderer(label: "GPU", value: percentage, reservedValue: "100%")
        }
        guard let sample else {
            return StatusItemContent(
                image: renderer.render(in: context),
                accessibilityValue: "GPU unavailable"
            )
        }
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: String(format: "GPU %.1f percent", sample.deviceUtilizationPercent)
        )
    }
}
