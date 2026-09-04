/// A clock abstraction used by schedulers and deterministic tests.
public protocol SampleClock: Sendable {
    /// Suspends for the requested duration.
    func sleep(for duration: Duration) async throws
}

/// The production sampling clock backed by Swift's continuous clock.
public struct ContinuousSampleClock: SampleClock {
    /// Creates a continuous sample clock.
    public init() {}

    /// Suspends for the requested duration.
    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
