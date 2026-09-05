import MenuBarStatsCore

/// Converts Sensors samples and per-widget settings into stable menu bar content.
@MainActor
public enum SensorsMenuBarPresenter {
    /// Produces one independently movable Sensors widget.
    public static func content(
        sample: SensorSample?,
        history: [HistoryEntry<SensorSample.GraphValue>],
        moduleSettings: ModuleSettings,
        sensorSettings: SensorSettings,
        widget: SensorWidgetSettings,
        temperatureUnit: TemperatureUnit,
        context: RenderContext
    ) -> StatusItemContent {
        let readings = sample.map { selectedReadings(sample: $0, settings: sensorSettings, widget: widget) } ?? []
        let fields = stableFields(
            sample: sample,
            settings: sensorSettings,
            widget: widget,
            temperatureUnit: temperatureUnit,
            decimalPlaces: sensorSettings.decimalPlaces
        )
        let renderer: any MenuBarRenderer
        switch widget.mode {
        case .compactStack:
            renderer = SensorStackRenderer(values: fields)
        case .text:
            renderer = TextRenderer(
                text: fields.map { "\($0.label) \($0.value)" }.joined(separator: "  "),
                reservedText: fields.map { "\($0.reservedLabel ?? $0.label) \($0.reservedValue)" }.joined(
                    separator: "  ")
            )
        case .graph:
            let primary = readings.first
            let values =
                primary.map { reading in
                    history.suffix(90).compactMap { entry in
                        entry.value.reading(id: reading.id).map { normalized($0, kind: reading.kind) }
                    }
                } ?? []
            renderer = GraphRenderer(values: values, style: moduleSettings.graphStyle)
        case .fan:
            let fan =
                readings.first { $0.kind == .fan }
                ?? sample?.readings.first { $0.kind == .fan }
            renderer = StackedLabelRenderer(
                label: fan?.shortName ?? "FAN",
                value: fan.map {
                    SensorValueFormatter.string(
                        $0,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: sensorSettings.decimalPlaces,
                        compact: true
                    )
                } ?? "—",
                reservedLabel: "FAN99",
                reservedValue: fan.map {
                    SensorValueFormatter.placeholder(
                        for: $0,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: sensorSettings.decimalPlaces
                    )
                } ?? "9999r"
            )
        }

        let spoken =
            sample == nil || readings.isEmpty
            ? "Sensors unavailable"
            : readings.map { reading in
                let value = SensorValueFormatter.string(
                    reading,
                    temperatureUnit: temperatureUnit,
                    decimalPlaces: sensorSettings.decimalPlaces
                )
                return "\(reading.name) \(value)"
            }.joined(separator: ", ")
        return StatusItemContent(image: renderer.render(in: context), accessibilityValue: spoken)
    }

    /// One field per configured sensor, present or not, so the canvas never changes between
    /// the unavailable, partially discovered, and live states.
    ///
    /// Every field reserves the widest label it can show (`SENS`, or `FAN99` for fans) and the
    /// widest value for its unit, and a missing reading renders as a dash inside that same
    /// reservation. A menu bar manager therefore sees one width for the item's whole life.
    static func stableFields(
        sample: SensorSample?,
        settings: SensorSettings,
        widget: SensorWidgetSettings,
        temperatureUnit: TemperatureUnit,
        decimalPlaces: Int
    ) -> [SensorStackValue] {
        let visibleIDs =
            sample.map { current in
                Set(
                    current.displayReadings(
                        hidesDuplicates: settings.hidesDuplicates, showsRawNames: settings.showsRawNames
                    ).map(\.id))
            } ?? []
        let ids = widget.sensorIDs.isEmpty ? fallbackIDs(sample: sample) : widget.sensorIDs
        return ids.map { id in
            let reading = visibleIDs.contains(id) ? sample?.reading(id: id) : nil
            let lowercased = id.lowercased()
            let isFan = reading?.kind == .fan || lowercased.contains("fan") || lowercased.contains(":f0")
            let fraction = decimalPlaces == 0 ? "" : "." + String(repeating: "9", count: decimalPlaces)
            let maximum = temperatureUnit == .celsius ? "125" : "257"
            let reservedValue =
                reading.map {
                    SensorValueFormatter.placeholder(
                        for: $0, temperatureUnit: temperatureUnit, decimalPlaces: decimalPlaces)
                } ?? (isFan ? "9999r" : "\(maximum)\(fraction)\(temperatureUnit.symbol)")
            return SensorStackValue(
                label: reading?.shortName ?? fallbackLabel(id: id),
                value: reading.map {
                    SensorValueFormatter.string(
                        $0,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: decimalPlaces,
                        compact: true
                    )
                } ?? "—",
                reservedValue: reservedValue,
                reservedLabel: isFan ? "FAN99" : "SENS"
            )
        }
    }

    private static func fallbackIDs(sample: SensorSample?) -> [String] {
        var ids = ["derived:temperature:hottest"]
        if let fan = sample?.readings.first(where: { $0.kind == .fan }) {
            ids.append(fan.id)
        }
        return ids
    }

    /// Short label for a configured sensor that has not been discovered yet.
    static func fallbackLabel(id: String) -> String {
        let lowercased = id.lowercased()
        if let range = lowercased.range(of: "smc:fan:"), let index = Int(lowercased[range.upperBound...]) {
            return "FAN\(index + 1)"
        }
        switch lowercased.split(separator: ":").last.map(String.init) ?? lowercased {
        case "cpu": return "CPU"
        case "gpu": return "GPU"
        case "hottest": return "HOT"
        default: return "SENS"
        }
    }

    private static func selectedReadings(
        sample: SensorSample,
        settings: SensorSettings,
        widget: SensorWidgetSettings
    ) -> [SensorReading] {
        let visibleIDs = Set(
            sample.displayReadings(
                hidesDuplicates: settings.hidesDuplicates,
                showsRawNames: settings.showsRawNames
            ).map(\.id)
        )
        let selected = widget.sensorIDs.compactMap { id in
            visibleIDs.contains(id) ? sample.reading(id: id) : nil
        }
        if !selected.isEmpty {
            return selected
        }
        return [sample.reading(id: "derived:temperature:hottest"), sample.readings.first { $0.kind == .fan }]
            .compactMap { $0 }
    }

    private static func normalized(_ value: Double, kind: SensorKind) -> Double {
        switch kind {
        case .temperature: min(1, max(0, value / 125))
        case .fan: min(1, max(0, value / 6_000))
        case .power: min(1, max(0, value / 150))
        case .voltage: min(1, max(0, value / 20))
        case .current: min(1, max(0, abs(value) / 20))
        }
    }
}
