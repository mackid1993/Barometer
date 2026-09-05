import Foundation
import Testing

@testable import MenuBarStatsCore

@Suite("MemoryHistoryTests")
struct MemoryHistoryTests {
    @Test("large empty histories allocate storage only when samples arrive")
    func emptyHistory() {
        let history = History<Int>(capacity: 86_400)
        #expect(history.count == 0)
        #expect(history.allocatedCapacity == 0)
        #expect(history.recent(10).isEmpty)
        #expect(history.downsampled(to: 300).isEmpty)
    }

    @Test("ring-buffer copies preserve their values after wrapping")
    func copyOnWrite() {
        var history = History<Int>(capacity: 3)
        for value in 0..<3 { history.append(value) }
        let saved = history
        for value in 3..<8 { history.append(value) }
        #expect(saved.entries.map(\.value) == [0, 1, 2])
        #expect(history.entries.map(\.value) == [5, 6, 7])
        #expect(history.recent(2).map(\.value) == [6, 7])
        #expect(history.recent(0).isEmpty)
        #expect(history.recent(-1).isEmpty)
    }

    @Test("a full day renders at most 300 points and preserves both endpoints")
    func fullDayGraph() {
        var history = History<Double>(capacity: 86_400)
        for second in 0..<86_400 {
            history.append(Double(second), at: Date(timeIntervalSince1970: Double(second)))
        }
        let points = history.downsampled(to: 300)
        #expect(points.count == 300)
        #expect(points.first?.value == 0)
        #expect(points.last?.value == 86_399)
        let recent = history.downsampled(to: 300, since: Date(timeIntervalSince1970: 86_390))
        #expect(recent.map(\.value) == (86_390..<86_400).map(Double.init))
        #expect(history.downsampled(to: 300, since: Date(timeIntervalSince1970: 90_000)).isEmpty)
        #expect(history.downsampled(to: 1).first?.value == 86_399)
    }

    @Test("windowed downsampling still works after the ring wraps")
    func wrappedWindow() {
        var history = History<Int>(capacity: 10)
        for second in 0..<25 {
            history.append(second, at: Date(timeIntervalSince1970: Double(second)))
        }
        #expect(history.downsampled(to: 3, since: Date(timeIntervalSince1970: 20)).map(\.value) == [20, 22, 24])
        #expect(history.downsampled(to: 20).map(\.value) == Array(15..<25))
    }

    @Test("window filtering survives a backward wall-clock correction")
    func clockCorrection() {
        var history = History<Int>(capacity: 5)
        for second in [100, 120, 90, 110, 130, 140] {
            history.append(second, at: Date(timeIntervalSince1970: Double(second)))
        }
        #expect(
            history.downsampled(to: 10, since: Date(timeIntervalSince1970: 110)).map(\.value)
                == [120, 110, 130, 140])
        #expect(history.downsampled(to: 2, since: Date(timeIntervalSince1970: 110)).map(\.value) == [120, 140])
        #expect(history.downsampled(to: 1, since: Date(timeIntervalSince1970: 110)).map(\.value) == [140])
    }

    @Test("stores keep full current details but release older sample payloads")
    @MainActor
    func releasesOldPayload() {
        let store = ModuleStore<PayloadSample>(historyCapacity: 10)
        var payload: Payload? = Payload()
        weak let observed = payload
        if let payload { store.receive(PayloadSample(payload: payload)) }
        payload = nil
        #expect(observed != nil)
        store.receive(PayloadSample(payload: Payload()))
        #expect(observed == nil)
        #expect(store.history.count == 2)
        store.reset()
        #expect(store.latestSample == nil)
        #expect(store.history.count == 0)
        #expect(store.history.allocatedCapacity == 0)
    }

    @Test("sensor graphs retain old numeric values without inventing missing readings")
    @MainActor
    func sensorValues() {
        let store = ModuleStore<SensorSample>(historyCapacity: 2)
        let first = SensorSample(timestamp: .now, readings: [reading(id: "cpu", value: 42)], sessionEnergy: [])
        store.receive(first)
        store.receive(SensorSample(timestamp: .now, readings: [reading(id: "fan", value: 900)], sessionEnergy: []))
        #expect(store.history.entries.first?.value.reading(id: "cpu") == 42)
        #expect(store.history.entries.last?.value.reading(id: "cpu") == nil)
        #expect(store.latestSample?.readings.first?.name == "Descriptive sensor name")
        store.receive(first)
        #expect(store.history.count == 2)
        #expect(store.history.entries.first?.value.reading(id: "fan") == 900)
    }

    private func reading(id: String, value: Double) -> SensorReading {
        SensorReading(
            id: id, name: "Descriptive sensor name", shortName: "S", rawName: "raw",
            kind: .temperature, source: .hid, value: value, unit: .celsius)
    }
}

private final class Payload: Sendable {}

private struct PayloadSample: HistoryProjecting {
    let payload: Payload
    var graphValue: Double { 1 }
}
