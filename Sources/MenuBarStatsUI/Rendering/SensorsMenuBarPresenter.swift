import MenuBarStatsCore

/// Converts Sensors samples and per-widget settings into stable menu bar content.
@MainActor
public enum SensorsMenuBarPresenter {
    /// Produces one independently movable Sensors widget.
    public static func content(
        sample: SensorSample?,
        history: [HistoryEntry<SensorSample>],
        moduleSettings: ModuleSettings,
        sensorSettings: SensorSettings,
        widget: SensorWidgetSettings,
        temperatureUnit: TemperatureUnit,
        context: RenderContext
    ) -> StatusItemContent {
        let readings = sample.map { selectedReadings(sample: $0, settings: sensorSettings, widget: widget) } ?? []
        let placeholders = placeholderValues(
            widget: widget,
            temperatureUnit: temperatureUnit,
            decimalPlaces: sensorSettings.decimalPlaces
        )
        let renderer: any MenuBarRenderer
        switch widget.mode {
        case .compactStack:
            renderer = SensorStackRenderer(
                values: readings.isEmpty ? placeholders : readings.map { reading in
                    SensorStackValue(
                        label: reading.shortName,
                        value: SensorValueFormatter.string(
                            reading,
                            temperatureUnit: temperatureUnit,
                            decimalPlaces: sensorSettings.decimalPlaces,
                            compact: true
                        ),
                        reservedValue: SensorValueFormatter.placeholder(
                            for: reading,
                            temperatureUnit: temperatureUnit,
                            decimalPlaces: sensorSettings.decimalPlaces
                        )
                    )
                }
            )
        case .text:
            let text = readings.isEmpty
                ? placeholders.map { "\($0.label) —" }.joined(separator: "  ")
                : readings.map { reading in
                    let value = SensorValueFormatter.string(
                        reading,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: sensorSettings.decimalPlaces,
                        compact: true
                    )
                    return "\(reading.shortName) \(value)"
                }.joined(separator: "  ")
            let reservedText = readings.isEmpty ? placeholders.map {
                "\($0.label) \($0.reservedValue)"
            }.joined(separator: "  ") : readings.map { reading in
                let placeholder = SensorValueFormatter.placeholder(
                    for: reading,
                    temperatureUnit: temperatureUnit,
                    decimalPlaces: sensorSettings.decimalPlaces
                )
                return "\(reading.shortName) \(placeholder)"
            }.joined(separator: "  ")
            renderer = TextRenderer(
                text: text,
                reservedText: reservedText
            )
        case .graph:
            let primary = readings.first
            let values = primary.map { reading in
                history.suffix(90).compactMap { entry in
                    entry.value.reading(id: reading.id).map { normalized($0) }
                }
            } ?? []
            renderer = GraphRenderer(values: values, style: moduleSettings.graphStyle)
        case .fan:
            let fan = readings.first { $0.kind == .fan }
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

        let spoken = sample == nil || readings.isEmpty
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

    private static func placeholderValues(
        widget: SensorWidgetSettings,
        temperatureUnit: TemperatureUnit,
        decimalPlaces: Int
    ) -> [SensorStackValue] {
        let ids = widget.sensorIDs.isEmpty ? ["sensor"] : widget.sensorIDs
        return ids.map { id in
            let lowercased = id.lowercased()
            if lowercased.contains("fan") || lowercased.contains(":f0") {
                return SensorStackValue(label: "FAN99", value: "—", reservedValue: "9999r")
            }
            let fraction = decimalPlaces == 0 ? "" : "." + String(repeating: "9", count: decimalPlaces)
            let maximum = temperatureUnit == .celsius ? "125" : "257"
            return SensorStackValue(
                label: "SENS",
                value: "—",
                reservedValue: "\(maximum)\(fraction)\(temperatureUnit.symbol)"
            )
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

    private static func normalized(_ reading: SensorReading) -> Double {
        switch reading.kind {
        case .temperature: min(1, max(0, reading.value / 125))
        case .fan: min(1, max(0, reading.value / 6_000))
        case .power: min(1, max(0, reading.value / 150))
        case .voltage: min(1, max(0, reading.value / 20))
        case .current: min(1, max(0, abs(reading.value) / 20))
        }
    }
}
