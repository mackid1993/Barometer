import Foundation
import Testing
@testable import MenuBarStatsUI

@Test("Aligned source samples produce one stack redraw with the newest timestamp")
func combinedUpdateCoalescing() {
    var coalescer = CombinedUpdateCoalescer()
    let first = Date(timeIntervalSinceReferenceDate: 100)
    let second = first.addingTimeInterval(0.01)
    let third = first.addingTimeInterval(0.02)

    #expect(coalescer.request(first) == true)
    #expect(coalescer.request(second) == false)
    #expect(coalescer.request(third) == false)
    #expect(coalescer.takeTimestamp() == third)
    #expect(coalescer.takeTimestamp() == nil)
    #expect(coalescer.request(third.addingTimeInterval(1)) == true)
}
