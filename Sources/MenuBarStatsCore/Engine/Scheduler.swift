import OSLog

/// Runs one monitor on an independent task with cancellation, pause, and error backoff.
public actor Scheduler<Source: Monitor> {
    /// Samples emitted by the monitor.
    public nonisolated let samples: AsyncStream<Source.Sample>

    private static var logger: Logger {
        Logger(subsystem: "com.barometer.app", category: "scheduler")
    }

    private let monitor: Source
    private let clock: any SampleClock
    private let continuation: AsyncStream<Source.Sample>.Continuation
    private var runTask: Task<Void, Never>?
    private var generation = 0
    private var intervalMultiplier = 1
    private var intervalOverride: Duration?
    private var hasConfirmedAvailability = false

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

    /// Cancels the current wait and samples immediately when the scheduler is running.
    public func refresh() {
        guard runTask != nil else {
            return
        }
        generation += 1
        runTask?.cancel()
        runTask = nil
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

    /// Delay until the next wall-clock multiple of `period`.
    ///
    /// Every scheduler sleeping toward the same boundaries means the one-second CPU, GPU,
    /// and network monitors wake the process once per second together, and the slower
    /// monitors land on those same instants, instead of each loop drifting to its own phase
    /// and waking the process several times per second.
    nonisolated static func alignedDelay(period: Duration, now: Date) -> Duration {
        let periodSeconds = period.seconds
        guard periodSeconds >= 0.25, periodSeconds <= 3_600 else {
            return period
        }
        let elapsed = now.timeIntervalSinceReferenceDate
        var delay = periodSeconds - elapsed.truncatingRemainder(dividingBy: periodSeconds)
        // A boundary that is almost here would double-fire; skip to the next one.
        if delay < periodSeconds * 0.3 {
            delay += periodSeconds
        }
        return .seconds(delay)
    }

    /// Timer tolerance that stays small relative to the period.
    nonisolated static func tolerance(for period: Duration) -> Duration {
        let seconds = min(1, max(0.02, period.seconds * 0.1))
        return .seconds(seconds)
    }

    private func runLoop(generation currentGeneration: Int) async {
        var errorDelaySeconds = 1

        while !Task.isCancelled {
            do {
                if !hasConfirmedAvailability {
                    guard await monitor.isAvailable else {
                        try await clock.sleep(for: .seconds(60))
                        continue
                    }
                    hasConfirmedAvailability = true
                }

                let sample = try await monitor.sample()
                continuation.yield(sample)
                errorDelaySeconds = 1
                let monitorInterval = await monitor.interval
                let period = (intervalOverride ?? monitorInterval) * intervalMultiplier
                try await clock.sleep(
                    for: Self.alignedDelay(period: period, now: Date()),
                    tolerance: Self.tolerance(for: period)
                )
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

extension Duration {
    fileprivate var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
