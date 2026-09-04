import AppKit
import MenuBarStatsCore

/// One resolved reading plus everything needed to draw it at a stable width.
struct ResolvedStackMetric {
    let metric: StackMetric
    let value: SensorStackValue
}

/// Converts a stack's chosen metrics into one independently movable status item.
///
/// Stacks compose readings rather than whole module presentations, so this resolves each metric
/// against the live stores and hands the result to the same matched-column renderer the Sensors
/// compact stack uses. Every metric reserves the widest value it can ever show, so adding a stack
/// never makes a status item change width while it runs.
@MainActor
enum StackMenuBarPresenter {
    /// Produces the status item content for one stack.
    static func content(
        stack: StackSettings,
        values: [ResolvedStackMetric],
        context: RenderContext
    ) -> StatusItemContent {
        guard !values.isEmpty else {
            return StatusItemContent(
                image: TextRenderer(text: "—").render(in: context),
                accessibilityValue: "\(stack.defaultName) has no readings"
            )
        }
        let renderer: any MenuBarRenderer
        switch stack.layout {
        case .columns:
            renderer = SensorStackRenderer(values: values.map(\.value))
        case .singleRow:
            renderer = TextRenderer(
                text: values.map { "\($0.value.label) \($0.value.value)" }.joined(separator: "  "),
                reservedText: values.map { "\($0.value.reservedLabel ?? $0.value.label) \($0.value.reservedValue)" }
                    .joined(separator: "  ")
            )
        }
        let spoken = values.map { "\($0.metric.displayName) \($0.value.value)" }.joined(separator: ", ")
        return StatusItemContent(image: renderer.render(in: context), accessibilityValue: spoken)
    }
}
