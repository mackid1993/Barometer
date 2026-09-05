import MenuBarStatsCore
import SwiftUI

/// Persisted section selection, grouped with the same labels as the day fly-out.
struct WeatherDetailSettingsSection: View {
    @Binding var preferences: WeatherDetailSettings

    var body: some View {
        Section("Day Forecast Details") {
            Picker("Show", selection: $preferences.showsAll) {
                Text("All details").tag(true)
                Text("Custom").tag(false)
            }
            .pickerStyle(.segmented)
            Text("Hover over a forecast day, then scroll through its details. Choose which sections appear.")
                .font(.caption).foregroundStyle(.secondary)
            if !preferences.showsAll {
                ForEach(WeatherDetailSection.allCases.filter { !$0.isHourlyGroup }, id: \.rawValue) { section in
                    Toggle(section.title, isOn: selection(section))
                }
                DisclosureGroup("Within each hour") {
                    ForEach(WeatherDetailSection.allCases.filter(\.isHourlyGroup), id: \.rawValue) { section in
                        Toggle(section.title, isOn: selection(section))
                    }
                }
                .disabled(!preferences.isSelected(.hourly))
                Text("The overview always stays visible. Switching to All details preserves your custom choices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func selection(_ section: WeatherDetailSection) -> Binding<Bool> {
        Binding(get: { preferences.isSelected(section) }, set: { preferences.setSelected($0, for: section) })
    }
}
