import MenuBarStatsCore
import SwiftUI

/// Live grouped hardware readings and session energy shown by every Sensors widget.
public struct SensorsDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 620)

    private let store: ModuleStore<SensorSample>
    private let settingsStore: SettingsStore
    private let resetEnergyAction: @MainActor () -> Void

    /// Creates the Sensors dropdown.
    public init(
        store: ModuleStore<SensorSample>,
        settingsStore: SettingsStore,
        resetEnergyAction: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.resetEnergyAction = resetEnergyAction
    }

    public var body: some View {
        let sample = store.latestSample
        let settings = settingsStore.settings.sensors
        let readings =
            sample?.displayReadings(
                hidesDuplicates: settings.hidesDuplicates,
                showsRawNames: settings.showsRawNames
            ) ?? []
        let _ = store.revision
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .sensors)

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "thermometer.medium",
                title: "Sensors",
                subtitle: sample == nil ? "Discovering sensors" : Self.subtitle(readings: readings),
                value: sample?.hottestTemperature.map(formatted) ?? "—",
                accent: accent
            )

            if let sample, !sample.sessionEnergy.isEmpty {
                GlassCard(tint: .yellow) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Session energy") {
                            Button("Reset", action: resetEnergyAction)
                                .buttonStyle(.glass)
                                .controlSize(.mini)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(sample.sessionEnergy) { energy in
                                StatTile(
                                    symbol: "bolt.fill", label: energy.name, value: Self.energy(energy.joules),
                                    tint: .yellow)
                            }
                        }
                        Text("Energy used since Barometer opened")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(SensorKind.allCases, id: \.self) { kind in
                let grouped = Self.ordered(readings.filter { $0.kind == kind }, kind: kind)
                if !grouped.isEmpty {
                    GlassCard(tint: kind.color) {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel(kind.title) {
                                Chip(text: "\(grouped.count)", color: kind.color, symbol: kind.symbol)
                            }
                            ForEach(grouped) { reading in
                                SensorReadingRow(
                                    displayName: displayName(reading),
                                    formattedValue: formatted(reading),
                                    history: history(for: reading),
                                    color: kind.color
                                )
                            }
                        }
                    }
                }
            }

            if readings.isEmpty {
                GlassCard {
                    ContentUnavailableView("No sensor readings yet", systemImage: "thermometer.medium")
                }
            }
        }
    }

    private static func subtitle(readings: [SensorReading]) -> String {
        let counts = SensorKind.allCases.compactMap { kind -> String? in
            let count = readings.filter { $0.kind == kind }.count
            return count > 0 ? "\(count) \(kind.title.lowercased())" : nil
        }
        return counts.isEmpty ? "No readings yet" : counts.joined(separator: "  ·  ")
    }

    /// Hottest temperatures first; other kinds keep their discovery order.
    private static func ordered(_ readings: [SensorReading], kind: SensorKind) -> [SensorReading] {
        guard kind == .temperature else { return readings }
        return readings.sorted { $0.value > $1.value }
    }

    private func displayName(_ reading: SensorReading) -> String {
        guard settingsStore.settings.sensors.showsRawNames,
            reading.name != reading.rawName
        else {
            return reading.name
        }
        return "\(reading.name) (\(reading.rawName))"
    }

    private func formatted(_ reading: SensorReading) -> String {
        SensorValueFormatter.string(
            reading,
            temperatureUnit: settingsStore.settings.sensorTemperatureUnit,
            decimalPlaces: settingsStore.settings.sensors.decimalPlaces
        )
    }

    private func history(for reading: SensorReading) -> [Double] {
        let raw = store.history.recent(60).compactMap { $0.value.reading(id: reading.id) }
        guard let minimum = raw.min(), let maximum = raw.max(), maximum > minimum else {
            return raw.map { _ in 0.5 }
        }
        return raw.map { ($0 - minimum) / (maximum - minimum) }
    }

    static func energy(_ joules: Double) -> String {
        if joules >= 3_600 {
            return String(format: "%.3f watt-hours", joules / 3_600)
        }
        return String(format: "%.1f joules", joules)
    }
}

private struct SensorReadingRow: View {
    let displayName: String
    let formattedValue: String
    let history: [Double]
    let color: Color
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(displayName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Sparkline(values: history, color: color)
                .frame(width: 64, height: 16)
            Text(formattedValue)
                .font(BarometerDesign.valueFont)
                .frame(minWidth: 64, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension SensorKind {
    fileprivate var title: String {
        switch self {
        case .temperature: "Temperatures"
        case .fan: "Fans"
        case .power: "Power"
        case .voltage: "Voltage"
        case .current: "Current"
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .fan: "fan.fill"
        case .power: "bolt.fill"
        case .voltage: "waveform.path"
        case .current: "arrow.right.circle"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .temperature: .orange
        case .fan: .cyan
        case .power: .yellow
        case .voltage: .purple
        case .current: .mint
        }
    }
}
