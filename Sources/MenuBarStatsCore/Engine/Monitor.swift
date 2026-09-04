/// A source of system samples that can be scheduled independently.
public protocol Monitor: Sendable {
    /// The sample type produced by the monitor.
    associatedtype Sample: Sendable

    /// The monitor's normal sampling interval.
    var interval: Duration { get async }

    /// Whether the underlying data source is available on this Mac.
    var isAvailable: Bool { get async }

    /// Collects one sample.
    func sample() async throws -> Sample
}
