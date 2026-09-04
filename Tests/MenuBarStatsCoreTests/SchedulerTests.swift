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
