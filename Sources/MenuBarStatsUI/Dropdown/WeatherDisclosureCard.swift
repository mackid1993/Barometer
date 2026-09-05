import MenuBarStatsCore
import SwiftUI

/// Keeps practical weather visible and reserves a disclosure control for advanced daily measurements.
struct WeatherDisclosureCard<Content: View>: View {
    let section: WeatherDetailSection
    let preferences: WeatherDetailSettings
    var tint: Color?
    @ViewBuilder let content: () -> Content
    @State private var isExpanded: Bool

    init(
        section: WeatherDetailSection,
        preferences: WeatherDetailSettings,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.section = section
        self.preferences = preferences
        self.tint = tint
        self.content = content
        _isExpanded = State(initialValue: section.isExpandedByDefault)
    }

    var body: some View {
        if preferences.isVisible(section) {
            GlassCard(tint: tint) {
                VStack(alignment: .leading, spacing: 10) {
                    if section == .atmosphere {
                        Button { isExpanded.toggle() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2.weight(.semibold)).frame(width: 10)
                                Text(section.title).font(.caption.weight(.semibold))
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    } else {
                        Text(section.title).font(.caption.weight(.semibold))
                    }
                    if section != .atmosphere || isExpanded { content() }
                }
            }
        }
    }
}
