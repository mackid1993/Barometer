import Foundation
import Testing

@testable import MenuBarStatsCore

@Suite("GPUTests")
struct GPUTests {
    @Test("GPU enrichment is cached between fast utilization samples")
    func throttlesEnrichment() {
        let start = Date(timeIntervalSince1970: 100)

        #expect(GPUMonitor.shouldRefreshDetails(lastRefresh: nil, now: start))
        #expect(!GPUMonitor.shouldRefreshDetails(lastRefresh: start, now: start.addingTimeInterval(9.9)))
        #expect(GPUMonitor.shouldRefreshDetails(lastRefresh: start, now: start.addingTimeInterval(10)))
    }
}
