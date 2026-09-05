import Foundation
import Testing

@testable import MenuBarStatsCore

@Suite("HistoryTests")
struct HistoryTests {
    @Test("ring buffer replaces its oldest entry")
    func ringBufferWraps() {
        var history = History<Int>(capacity: 3)
        let start = Date(timeIntervalSince1970: 1_000)
        for value in 0..<5 {
            history.append(value, at: start.addingTimeInterval(Double(value)))
        }

        #expect(history.count == 3)
        #expect(history.entries.map(\.value) == [2, 3, 4])
    }

    @Test("last duration filters chronologically")
    func lastDurationFilters() {
        var history = History<Int>(capacity: 5)
        let start = Date(timeIntervalSince1970: 1_000)
        for value in 0..<5 {
            history.append(value, at: start.addingTimeInterval(Double(value)))
        }

        #expect(history.last(.seconds(2), now: start.addingTimeInterval(4)).map(\.value) == [2, 3, 4])
    }

    @Test("downsampling preserves endpoints")
    func downsamplingPreservesEndpoints() {
        var history = History<Int>(capacity: 10)
        for value in 0..<10 {
            history.append(value, at: Date(timeIntervalSince1970: Double(value)))
        }

        let values = history.downsampled(to: 4).map(\.value)
        #expect(values == [0, 3, 6, 9])
    }
}
