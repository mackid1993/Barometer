import MenuBarStatsCore
import SwiftUI

/// Displays each enabled weather section directly, without expansion controls.
struct WeatherDetailCard<Content: View>: View {
    let section: WeatherDetailSection
    let preferences: WeatherDetailSettings
    var tint: Color?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if preferences.isVisible(section) {
            GlassCard(tint: tint) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title).font(.caption.weight(.semibold))
                    content()
                }
            }
        }
    }
}
