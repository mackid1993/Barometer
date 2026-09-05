import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("Graph history persistence")
struct GraphHistoryPersistenceTests {
    @Test("CPU and GPU history survives a binary property-list round trip")
    func archiveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerGraphHistoryTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("graph-history.plist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let archive = GraphHistoryArchive(
            cpu: [HistoryEntry(timestamp: timestamp, value: CPUHistoryValue(totalPercent: 42))],
            gpu: [HistoryEntry(
                timestamp: timestamp.addingTimeInterval(1),
                value: GPUHistoryValue(deviceUtilizationPercent: 24)
            )]
        )

        try GraphHistoryPersistence.save(archive, to: url)
        let restored = try GraphHistoryPersistence.load(from: url)

        #expect(restored.cpu.count == 1)
        #expect(restored.cpu.first?.timestamp == timestamp)
        #expect(restored.cpu.first?.value.totalPercent == 42)
        #expect(restored.gpu.count == 1)
        #expect(restored.gpu.first?.value.deviceUtilizationPercent == 24)
    }

    @Test("restoring history excludes stale and future entries")
    @MainActor
    func restoreWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = ModuleStore<CPUSample>(historyCapacity: 10)
        store.restoreHistory(
            [
                HistoryEntry(timestamp: now.addingTimeInterval(-101), value: CPUHistoryValue(totalPercent: 1)),
                HistoryEntry(timestamp: now.addingTimeInterval(-50), value: CPUHistoryValue(totalPercent: 2)),
                HistoryEntry(timestamp: now.addingTimeInterval(1), value: CPUHistoryValue(totalPercent: 3)),
            ],
            since: now.addingTimeInterval(-100),
            through: now
        )

        #expect(store.history.entries.count == 1)
        #expect(store.history.entries.first?.value.totalPercent == 2)
    }
}
