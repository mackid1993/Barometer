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
        guard let sample else {
            return StatusItemContent(
                image: SensorStackRenderer(
                    values: [SensorStackValue(label: "SENS", value: "—", reservedValue: "999.9°C")]
                ).render(in: context),
                accessibilityValue: "Sensors unavailable"
            )
        }

        let readings = selectedReadings(sample: sample, widget: widget)
        let renderer: any MenuBarRenderer
        switch widget.mode {
        case .compactStack:
            renderer = SensorStackRenderer(
                values: readings.map { reading in
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
            let text = readings.map { reading in
                    let value = SensorValueFormatter.string(
                        reading,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: sensorSettings.decimalPlaces,
                        compact: true
                    )
                    return "\(reading.shortName) \(value)"
                }.joined(separator: "  ")
            let reservedText = readings.map { reading in
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
                ?? sample.readings.first { $0.kind == .fan }
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
                reservedValue: fan.map {
                    SensorValueFormatter.placeholder(
                        for: $0,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: sensorSettings.decimalPlaces
                    )
                } ?? "9999r"
            )
        }

        let spoken = readings.isEmpty
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

    private static func selectedReadings(
        sample: SensorSample,
        widget: SensorWidgetSettings
    ) -> [SensorReading] {
        let selected = widget.sensorIDs.compactMap(sample.reading(id:))
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
