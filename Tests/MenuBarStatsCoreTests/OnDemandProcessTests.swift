import Testing
@testable import MenuBarStatsCore

@Suite("On-demand process detail")
struct OnDemandProcessTests {
    @Test("CPU headlines update with no process scan until details are requested")
    func cpuDetails() async throws {
        let monitor = CPUMonitor(collectsProcessDetails: false)
        let closed = try await monitor.sample()
        #expect(closed.topProcesses.isEmpty)
        #expect(closed.processCount == 0)
        #expect(!closed.perCore.isEmpty)
        await monitor.setProcessDetailsEnabled(true)
        let open = try await monitor.sample()
        #expect(open.processCount > 0)
        #expect(!open.topProcesses.isEmpty)
        await monitor.setProcessDetailsEnabled(false)
        let closedAgain = try await monitor.sample()
        #expect(closedAgain.topProcesses.map(\.processIdentifier) == open.topProcesses.map(\.processIdentifier))
        #expect(closedAgain.timestamp > open.timestamp)
    }

    @Test("Memory headlines update while process details are deferred")
    func memoryDetails() async throws {
        let monitor = MemoryMonitor(collectsProcessDetails: false)
        let closed = try await monitor.sample()
        #expect(closed.topProcesses.isEmpty)
        #expect(closed.total > 0)
        await monitor.setProcessDetailsEnabled(true)
        let open = try await monitor.sample()
        #expect(!open.topProcesses.isEmpty)
        await monitor.setProcessDetailsEnabled(false)
        let closedAgain = try await monitor.sample()
        #expect(closedAgain.topProcesses.map(\.physicalFootprint) == open.topProcesses.map(\.physicalFootprint))
        #expect(closedAgain.total == open.total)
    }

    @Test("Network counters remain available without per-process accounting")
    func networkDetails() async throws {
        let monitor = NetworkMonitor(collectsProcessDetails: false)
        let sample = try await monitor.sample()
        #expect(!sample.interfaces.isEmpty)
        #expect(sample.topProcesses.isEmpty)
        #expect(!sample.isProcessActivityAvailable)
    }
}
