/// A clock abstraction used by schedulers and deterministic tests.
public protocol SampleClock: Sendable {
    /// Suspends for the requested duration.
    func sleep(for duration: Duration) async throws

    /// Suspends for the requested duration, letting the system fire the timer up to
    /// `tolerance` late so nearby wakeups can be coalesced.
    func sleep(for duration: Duration, tolerance: Duration?) async throws
}

extension SampleClock {
    public func sleep(for duration: Duration, tolerance: Duration?) async throws {
        try await sleep(for: duration)
    }
}

/// The production sampling clock backed by Swift's continuous clock.
public struct ContinuousSampleClock: SampleClock {
    /// Creates a continuous sample clock.
    public init() {}

    /// Suspends for the requested duration.
    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }

    /// Suspends with a timer tolerance so the kernel can batch Barometer's wakeups.
    public func sleep(for duration: Duration, tolerance: Duration?) async throws {
        try await ContinuousClock().sleep(for: duration, tolerance: tolerance)
    }
}
