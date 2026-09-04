import OSLog

/// Runs one monitor on an independent task with cancellation, pause, and error backoff.
public actor Scheduler<Source: Monitor> {
    /// Samples emitted by the monitor.
    public nonisolated let samples: AsyncStream<Source.Sample>

    private static var logger: Logger {
        Logger(subsystem: "net.brustein.MenuBarStats", category: "scheduler")
    }

    private let monitor: Source
    private let clock: any SampleClock
    private let continuation: AsyncStream<Source.Sample>.Continuation
    private var runTask: Task<Void, Never>?
    private var generation = 0
    private var intervalMultiplier = 1
    private var intervalOverride: Duration?

    /// Creates a scheduler for one monitor.
    public init(monitor: Source, clock: any SampleClock = ContinuousSampleClock()) {
        self.monitor = monitor
        self.clock = clock
        let stream = AsyncStream<Source.Sample>.makeStream(bufferingPolicy: .bufferingNewest(2))
        samples = stream.stream
        continuation = stream.continuation
    }

    deinit {
        runTask?.cancel()
        continuation.finish()
    }

    /// Starts sampling if the scheduler is not already running.
    public func start() {
        guard runTask == nil else {
            return
        }
        generation += 1
        let currentGeneration = generation
        runTask = Task { [weak self] in
            await self?.runLoop(generation: currentGeneration)
        }
    }

    /// Pauses sampling without finishing the sample stream.
    public func pause() {
        generation += 1
        runTask?.cancel()
        runTask = nil
    }

    /// Resumes sampling after a pause.
    public func resume() {
        start()
    }

    /// Stops sampling permanently and finishes the sample stream.
    public func stop() {
        pause()
        continuation.finish()
    }

    /// Applies an integer multiplier to the normal monitor interval.
    public func setIntervalMultiplier(_ multiplier: Int) {
        intervalMultiplier = max(1, multiplier)
    }

    /// Overrides the monitor's normal interval, or restores it when passed `nil`.
    public func setInterval(_ interval: Duration?) {
        intervalOverride = interval
    }

    private func runLoop(generation currentGeneration: Int) async {
        var errorDelaySeconds = 1

        while !Task.isCancelled {
            do {
                guard await monitor.isAvailable else {
                    try await clock.sleep(for: .seconds(60))
                    continue
                }

                let sample = try await monitor.sample()
                continuation.yield(sample)
                errorDelaySeconds = 1
                let monitorInterval = await monitor.interval
                let interval = intervalOverride ?? monitorInterval
                try await clock.sleep(for: interval * intervalMultiplier)
            } catch is CancellationError {
                break
            } catch {
                let delay = errorDelaySeconds
                let message = "Sampling failed; retrying in \(delay) seconds: \(String(describing: error))"
                Self.logger.error("\(message, privacy: .public)")
                do {
                    try await clock.sleep(for: .seconds(delay))
                } catch {
                    break
                }
                errorDelaySeconds = min(delay * 2, 60)
            }
        }

        if generation == currentGeneration {
            runTask = nil
        }
    }
}
