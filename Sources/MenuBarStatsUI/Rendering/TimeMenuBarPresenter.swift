import Foundation
import MenuBarStatsCore

/// Converts wall-clock samples into stable custom menu bar text.
@MainActor
public enum TimeMenuBarPresenter {
    /// Renders the configured time template.
    public static func content(
        sample: TimeSample?,
        settings: ModuleSettings,
        timeSettings: TimeSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let context = timeSettings.menuBarFontSize.map { context.withFontSize(CGFloat($0)) } ?? context
        guard let sample,
              let timeZone = TimeZone(identifier: sample.systemTimeZoneIdentifier)
        else {
            return StatusItemContent(
                image: TextRenderer(
                    text: "—",
                    reservedText: TimeFormatEngine.menuBarPlaceholder(
                        template: timeSettings.menuBarTemplate,
                        showsSeconds: timeSettings.showsSeconds
                    )
                ).render(in: context),
                accessibilityValue: "Time unavailable"
            )
        }
        let text = TimeFormatEngine.render(
            date: sample.timestamp,
            timeZone: timeZone,
            template: timeSettings.menuBarTemplate,
            showsSeconds: timeSettings.showsSeconds
        )
        return StatusItemContent(
            image: TextRenderer(
                text: text,
                reservedText: settings.usesFixedWidth
                    ? TimeFormatEngine.menuBarPlaceholder(
                        template: timeSettings.menuBarTemplate,
                        showsSeconds: timeSettings.showsSeconds
                    )
                    : nil
            ).render(in: context),
            accessibilityValue: "Time \(text)"
        )
    }
}
