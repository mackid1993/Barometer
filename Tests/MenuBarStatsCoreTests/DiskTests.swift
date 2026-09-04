import Foundation
@testable import MenuBarStatsCore
import Testing

@Suite("DiskTests")
struct DiskTests {
    @Test("disk rates use elapsed time and reject counter resets")
    func calculatesRates() {
        #expect(DiskMonitor.rate(from: 100, to: 300, elapsed: 2) == 100)
        #expect(DiskMonitor.rate(from: nil, to: 300, elapsed: 2) == 0)
        #expect(DiskMonitor.rate(from: 300, to: 10, elapsed: 2) == 0)
        #expect(DiskMonitor.rate(from: 100, to: 300, elapsed: 0) == 0)
    }
}
