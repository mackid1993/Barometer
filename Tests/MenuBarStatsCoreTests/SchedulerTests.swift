import Testing
@testable import MenuBarStatsCore

@Suite("SchedulerTests")
struct SchedulerTests {
    @Test("errors back off exponentially with a fake clock")
    func errorsBackOff() async {
        let monitor = FailingTwiceMonitor()
        let clock = RecordingClock(stopDuration: .seconds(5))
        let scheduler = Scheduler(monitor: monitor, clock: clock)
        var iterator = scheduler.samples.makeAsyncIterator()

        await scheduler.start()
        let sample = await iterator.next()
        await scheduler.stop()

        #expect(sample == 3)
        #expect(await clock.recordedDurations() == [.seconds(1), .seconds(2), .seconds(5)])
    }

    @Test("manual refresh interrupts the current wait and samples immediately")
    func manualRefresh() async {
        let monitor = CountingMonitor()
        let scheduler = Scheduler(monitor: monitor)

        await scheduler.start()
        await waitForSamples(1, from: monitor)
        await scheduler.refresh()
        await waitForSamples(2, from: monitor)
        await scheduler.stop()

        #expect(await monitor.sampleCount() == 2)
        #expect(await monitor.availabilityCheckCount() == 1)
    }

    private func waitForSamples(_ count: Int, from monitor: CountingMonitor) async {
        for _ in 0..<10_000 {
            if await monitor.sampleCount() >= count {
                return
            }
            await Task.yield()
        }
    }
}

private enum ExpectedFailure: Error {
    case unavailable
}

private actor FailingTwiceMonitor: Monitor {
    nonisolated let interval: Duration = .seconds(5)
    nonisolated let isAvailable = true
    private var attempt = 0

    func sample() throws -> Int {
        attempt += 1
        if attempt <= 2 {
            throw ExpectedFailure.unavailable
        }
        return attempt
    }
}

private actor RecordingClock: SampleClock {
    private let stopDuration: Duration
    private var durations: [Duration] = []

    init(stopDuration: Duration) {
        self.stopDuration = stopDuration
    }

    func sleep(for duration: Duration) throws {
        durations.append(duration)
        if duration == stopDuration {
            throw CancellationError()
        }
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

private actor CountingMonitor: Monitor {
    nonisolated let interval: Duration = .seconds(3_600)
    private var count = 0
    private var availabilityChecks = 0

    var isAvailable: Bool {
        availabilityChecks += 1
        return true
    }

    func sample() -> Int {
        count += 1
        return count
    }

    func sampleCount() -> Int {
        count
    }

    func availabilityCheckCount() -> Int {
        availabilityChecks
    }
}
