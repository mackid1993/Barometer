import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("SensorsTests")
struct SensorsTests {
    private func reading(
        id: String = "derived:temperature:cpu",
        name: String = "CPU Temperature",
        value: Double = 52.25,
        unit: SensorUnit = .celsius,
        source: SensorSourceKind = .derived
    ) -> SensorReading {
        SensorReading(
            id: id,
            name: name,
            shortName: "CPU",
            rawName: "test",
            kind: unit == .celsius ? .temperature : .power,
            source: source,
            value: value,
            unit: unit
        )
    }

    @Test("temperature formatting supports both systems and fixed precision")
    func temperatureFormatting() {
        let temperature = reading()

        #expect(
            SensorValueFormatter.string(
                temperature,
                temperatureUnit: .celsius,
                decimalPlaces: 1,
                compact: true
            ) == "52.2°C"
        )
        #expect(
            SensorValueFormatter.string(
                temperature,
                temperatureUnit: .fahrenheit,
                decimalPlaces: 2,
                compact: true
            ) == "126.05°F"
        )
        #expect(
            SensorValueFormatter.placeholder(
                for: temperature,
                temperatureUnit: .fahrenheit,
                decimalPlaces: 2
            ) == "257.99°F"
        )
    }

    @Test("duplicate display readings favor summaries and preserve distinct raw readings")
    func hidesEquivalentReadings() {
        let summary = reading()
        let raw = reading(
            id: "smc:temperature:Tp01",
            value: 51,
            source: .smc
        )
        let distinct = reading(
            id: "hid:temperature:ssd",
            name: "SSD",
            value: 40,
            source: .hid
        )
        let sample = SensorSample(timestamp: .now, readings: [raw, distinct, summary], sessionEnergy: [])

        #expect(sample.displayReadings(hidesDuplicates: true).map(\.id) == [summary.id, distinct.id])
        #expect(sample.displayReadings(hidesDuplicates: false).count == 2)
        #expect(sample.displayReadings(hidesDuplicates: false, showsRawNames: true).count == 3)
    }

    @Test("widget identities are normalized and never reused")
    func widgetIdentityNormalization() throws {
        let data = Data(
            #"{"decimalPlaces":8,"widgets":[{"id":0},{"id":1},{"id":3},{"id":3}]}"#.utf8
        )
        let settings = try JSONDecoder().decode(SensorSettings.self, from: data)

        #expect(settings.decimalPlaces == 2)
        #expect(settings.widgets.map(\.id) == [1, 3])
        #expect(settings.nextWidgetID == 4)
    }

    @Test("energy integration rejects stale samples and uses the trapezoid rule")
    func energyIntegration() {
        var accumulator = SensorEnergyAccumulator()
        accumulator.addPowerSample(id: "ioreport:gpu", watts: 4, elapsedSeconds: 2)
        accumulator.addPowerSample(id: "ioreport:gpu", watts: 100, elapsedSeconds: 11)
        accumulator.addSystemPowerSample(watts: 10, timestamp: Date(timeIntervalSince1970: 100))
        accumulator.addSystemPowerSample(watts: 14, timestamp: Date(timeIntervalSince1970: 102))

        #expect(accumulator.joules["ioreport:gpu"] == 8)
        #expect(accumulator.joules["smc:system"] == 24)

        accumulator.reset()
        #expect(accumulator.joules.isEmpty)
    }

    @Test("expensive sensor sources use their configured refresh cadence")
    func throttlesExpensiveSources() {
        let start = Date(timeIntervalSince1970: 100)

        #expect(SensorsMonitor.shouldRefresh(lastRefresh: nil, now: start, interval: 10))
        #expect(!SensorsMonitor.shouldRefresh(
            lastRefresh: start,
            now: start.addingTimeInterval(9.9),
            interval: 10
        ))
        #expect(SensorsMonitor.shouldRefresh(
            lastRefresh: start,
            now: start.addingTimeInterval(10),
            interval: 10
        ))
    }
}
