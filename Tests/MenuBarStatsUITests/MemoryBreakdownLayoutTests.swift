import CoreGraphics
import Testing
@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@Suite("Memory breakdown bar geometry")
struct MemoryBreakdownLayoutTests {
    private static let gigabyte: Double = 1_073_741_824

    private static func sample(
        totalGB: Double,
        appGB: Double,
        wiredGB: Double,
        compressedGB: Double,
        cachedGB: Double
    ) -> MemorySample {
        let total = UInt64(totalGB * gigabyte)
        let used = UInt64((appGB + wiredGB + compressedGB) * gigabyte)
        return MemorySample(
            timestamp: .init(timeIntervalSince1970: 0),
            total: total,
            used: used,
            app: UInt64(appGB * gigabyte),
            wired: UInt64(wiredGB * gigabyte),
            compressed: UInt64(compressedGB * gigabyte),
            cached: UInt64(cachedGB * gigabyte),
            free: total > used ? total - used : 0,
            pressurePercent: 50,
            pressureLevel: .normal,
            swapUsed: 0,
            swapTotal: 0,
            topProcesses: []
        )
    }

    /// The reading from the reported screenshot: the cached bytes sit inside free, and drawing both ran the
    /// bar a fifth past the card. The segments and their gaps now come to the track width exactly.
    @Test("The reported 16 GB reading fills the track and never exceeds it")
    func reportedReadingFits() {
        let width: CGFloat = 320
        let layout = MemoryBreakdownLayout(
            sample: Self.sample(totalGB: 16, appGB: 3.95, wiredGB: 2.93, compressedGB: 5.35, cachedGB: 3.17),
            width: width
        )
        let gaps = MemoryBreakdownLayout.spacing * 4
        #expect(abs(layout.widths.reduce(0, +) + gaps - width) < 0.001)
        // 16 - (3.95 + 2.93 + 5.35 + 3.17) is free beyond the file cache, not the 3.76 GB that is unused.
        #expect(abs(layout.unused - (width - gaps) * CGFloat(0.60 / 16)) < 0.5)
        #expect(layout.cached > layout.unused)
    }

    @Test("No reading overflows the track")
    func nothingOverflows() {
        let width: CGFloat = 320
        let readings = [
            Self.sample(totalGB: 16, appGB: 3.95, wiredGB: 2.93, compressedGB: 5.35, cachedGB: 3.17),
            Self.sample(totalGB: 8, appGB: 0, wiredGB: 0, compressedGB: 0, cachedGB: 0),
            Self.sample(totalGB: 8, appGB: 4, wiredGB: 2, compressedGB: 1, cachedGB: 1),
            // A reading that claims more than is installed still fits, scaled down.
            Self.sample(totalGB: 8, appGB: 6, wiredGB: 3, compressedGB: 2, cachedGB: 4),
            Self.sample(totalGB: 64, appGB: 10, wiredGB: 6, compressedGB: 2, cachedGB: 40),
        ]
        for reading in readings {
            let layout = MemoryBreakdownLayout(sample: reading, width: width)
            #expect(layout.widths.allSatisfy { $0 >= 0 && $0.isFinite })
            #expect(layout.widths.reduce(0, +) + MemoryBreakdownLayout.spacing * 4 <= width + 0.001)
        }
    }

    @Test("A machine reporting no memory draws nothing rather than dividing by zero")
    func emptyReading() {
        let layout = MemoryBreakdownLayout(
            sample: Self.sample(totalGB: 0, appGB: 0, wiredGB: 0, compressedGB: 0, cachedGB: 0),
            width: 320
        )
        #expect(layout.widths.allSatisfy { $0 == 0 })
    }

    @Test("A track narrower than its gaps stays at zero")
    func narrowTrack() {
        let layout = MemoryBreakdownLayout(
            sample: Self.sample(totalGB: 16, appGB: 4, wiredGB: 3, compressedGB: 5, cachedGB: 3),
            width: 2
        )
        #expect(layout.widths.allSatisfy { $0 >= 0 && $0.isFinite })
    }
}
