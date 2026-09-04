import MenuBarStatsCore
import SwiftUI

/// Live grouped hardware readings and session energy shown by every Sensors widget.
public struct SensorsDropdownView: View {
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
        let readings = sample?.displayReadings(hidesDuplicates: settings.hidesDuplicates) ?? []
        let _ = store.revision

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sensors").font(.headline)
                    Spacer()
                    if let hottest = sample?.hottestTemperature {
                        Text("Hottest  " + formatted(hottest))
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                }

                if let sample, !sample.sessionEnergy.isEmpty {
                    HStack {
                        Text("SESSION ENERGY").sensorSectionLabel()
                        Spacer()
                        Button("Reset", action: resetEnergyAction).buttonStyle(.plain)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 7) {
                        ForEach(sample.sessionEnergy) { energy in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(energy.name).font(.caption2).foregroundStyle(.secondary)
                                Text(Self.energy(energy.joules))
                                    .font(.caption.monospacedDigit().weight(.medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                ForEach(SensorKind.allCases, id: \.self) { kind in
                    let grouped = readings.filter { $0.kind == kind }
                    if !grouped.isEmpty {
                        Text(kind.title.uppercased()).sensorSectionLabel()
                        ForEach(grouped) { reading in
                            SensorReadingRow(
                                reading: reading,
                                displayName: displayName(reading),
                                formattedValue: formatted(reading),
                                history: history(for: reading)
                            )
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 420, height: 600)
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
        let raw = store.history.entries.suffix(60).compactMap { $0.value.reading(id: reading.id)?.value }
        guard let minimum = raw.min(), let maximum = raw.max(), maximum > minimum else {
            return raw.map { _ in 0.5 }
        }
        return raw.map { ($0 - minimum) / (maximum - minimum) }
    }

    private static func energy(_ joules: Double) -> String {
        if joules >= 3_600 {
            return String(format: "%.3f Wh", joules / 3_600)
        }
        return String(format: "%.1f J", joules)
    }
}

private struct SensorReadingRow: View {
    let reading: SensorReading
    let displayName: String
    let formattedValue: String
    let history: [Double]

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName).lineLimit(1)
                Text(reading.source.title).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            SensorSparkline(values: history, kind: reading.kind)
                .frame(width: 72, height: 20)
            Text(formattedValue)
                .monospacedDigit()
                .frame(minWidth: 68, alignment: .trailing)
        }
        .font(.caption)
    }
}

private struct SensorSparkline: View {
    let values: [Double]
    let kind: SensorKind

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, raw) in values.enumerated() {
                let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
                let y = (1 - CGFloat(min(1, max(0, raw)))) * size.height
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(kind.color), lineWidth: 1.25)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
    }
}

private extension SensorKind {
    var title: String {
        switch self {
        case .temperature: "Temperatures"
        case .fan: "Fans"
        case .power: "Power"
        case .voltage: "Voltage"
        case .current: "Current"
        }
    }

    var color: Color {
        switch self {
        case .temperature: .orange
        case .fan: .cyan
        case .power: .yellow
        case .voltage: .purple
        case .current: .mint
        }
    }
}

private extension SensorSourceKind {
    var title: String {
        switch self {
        case .derived: "Summary"
        case .hid: "IOHID"
        case .smc: "SMC"
        case .ioReport: "IOReport"
        }
    }
}

private extension View {
    func sensorSectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
