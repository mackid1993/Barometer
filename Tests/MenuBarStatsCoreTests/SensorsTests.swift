import Foundation
import Testing

@testable import MenuBarStatsCore

@Suite("SensorsTests")
struct SensorsTests {
    private func reading(
        id: String = "derived:temperature:cpu",
        name: String = "CPU Temperature",
        rawName: String = "test",
        value: Double = 52.25,
        unit: SensorUnit = .celsius,
        source: SensorSourceKind = .derived
    ) -> SensorReading {
        SensorReading(
            id: id,
            name: name,
            shortName: "CPU",
            rawName: rawName,
            kind: unit == .celsius ? .temperature : .power,
            source: source,
            value: value,
            unit: unit
        )
    }

    @Test("recognized GPU temperatures do not require advanced firmware sensors")
    func gpuTemperatureIsFriendly() {
        let gpu = reading(
            id: "smc:temperature:Tg0a",
            name: "GPU Temperature",
            rawName: "Tg0a",
            value: 53.4,
            source: .smc
        )
        let unknown = reading(
            id: "smc:temperature:ZZZZ",
            name: "ZZZZ",
            rawName: "ZZZZ",
            value: 41,
            source: .smc
        )
        let sample = SensorSample(timestamp: .now, readings: [gpu, unknown], sessionEnergy: [])

        #expect(sample.displayReadings(hidesDuplicates: false).map(\.id) == [gpu.id])
        #expect(sample.displayReadings(hidesDuplicates: false, showsRawNames: true).count == 2)
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
        #expect(
            !SensorsMonitor.shouldRefresh(
                lastRefresh: start,
                now: start.addingTimeInterval(9.9),
                interval: 10
            ))
        #expect(
            SensorsMonitor.shouldRefresh(
                lastRefresh: start,
                now: start.addingTimeInterval(10),
                interval: 10
            ))
    }

    @Test("closed sensor sampling requests only readings used by visible items")
    func selectedSamplingPlan() {
        let plan = SensorSamplingPlan(
            sensorIDs: [
                "derived:temperature:cpu",
                "derived:temperature:gpu",
                "hid:temperature:NAND CH0 temp",
                "smc:power:PSTR",
                "smc:fan:1",
            ],
            includesFullInventory: false
        )

        #expect(plan.needsCPU)
        #expect(plan.needsGPU)
        #expect(!plan.needsAllTemperatures)
        #expect(plan.hidRawNames == ["NAND CH0 temp"])
        #expect(plan.smcKeys == ["PSTR"])
        #expect(plan.fanIDs == [1])
        #expect(!plan.needsIOReport)
    }

    @Test("active sensor IDs exclude disabled widgets and include enabled stacks")
    func activeMenuBarSensorIDs() {
        var settings = AppSettings()
        settings.modules[.sensors]?.isEnabled = true
        settings.sensors = SensorSettings(widgets: [
            SensorWidgetSettings(
                id: 1,
                isEnabled: true,
                sensorIDs: ["derived:temperature:cpu", "derived:temperature:gpu"]
            ),
            SensorWidgetSettings(id: 2, isEnabled: false, sensorIDs: ["derived:temperature:hottest"]),
        ])
        settings.stacks = StacksSettings(stacks: [
            StackSettings(id: 1, isEnabled: true, metrics: [.sensorsFan]),
            StackSettings(id: 2, isEnabled: false, metrics: [.sensorsHottest]),
        ])

        #expect(settings.activeMenuBarSensorIDs == [
            "derived:temperature:cpu",
            "derived:temperature:gpu",
            "smc:fan:0",
        ])
    }
}

@Suite("DerivedTemperatureTests")
struct DerivedTemperatureTests {
    private func reading(name: String, rawName: String, value: Double, source: SensorSourceKind) -> SensorReading {
        SensorReading(
            id: "\(source.rawValue):\(rawName)",
            name: name,
            shortName: String(name.prefix(3)).uppercased(),
            rawName: rawName,
            kind: .temperature,
            source: source,
            value: value,
            unit: .celsius
        )
    }

    @Test("CPU temperature comes from the die sensors, not the hottest Tp key")
    func cpuUsesDieSensors() {
        let readings = [
            reading(name: "SoC die 1", rawName: "PMU tdie1", value: 46.2, source: .hid),
            reading(name: "SoC die 2", rawName: "PMU tdie2", value: 49.9, source: .hid),
            reading(name: "CPU Tp29", rawName: "Tp29", value: 76.3, source: .smc),
            reading(name: "CPU TPD0", rawName: "TPD0", value: 47.7, source: .smc),
            reading(name: "GPU Tg0a", rawName: "Tg0a", value: 53.4, source: .smc),
        ]
        let derived = SensorsMonitor.addDerivedTemperatures(to: readings)
        #expect(derived.first { $0.id == "derived:temperature:cpu" }?.value == 49.9)
        #expect(derived.first { $0.id == "derived:temperature:gpu" }?.value == 53.4)
        #expect(derived.first { $0.id == "derived:temperature:hottest" }?.value == 76.3)
    }

    @Test("CPU temperature falls back to SMC die keys, then the broad CPU family")
    func cpuFallbacks() {
        let packageOnly = [
            reading(name: "CPU Tp29", rawName: "Tp29", value: 76.3, source: .smc),
            reading(name: "CPU TPD0", rawName: "TPD0", value: 47.7, source: .smc),
            reading(name: "CPU TPD1", rawName: "TPD1", value: 45.1, source: .smc),
        ]
        #expect(
            SensorsMonitor.addDerivedTemperatures(to: packageOnly)
                .first { $0.id == "derived:temperature:cpu" }?.value == 47.7)

        let broadOnly = [
            reading(name: "CPU Tp29", rawName: "Tp29", value: 76.3, source: .smc),
            reading(name: "CPU Te06", rawName: "Te06", value: 56.9, source: .smc),
        ]
        #expect(
            SensorsMonitor.addDerivedTemperatures(to: broadOnly)
                .first { $0.id == "derived:temperature:cpu" }?.value == 76.3)
    }
}
