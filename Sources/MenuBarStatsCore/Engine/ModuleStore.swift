import Foundation
import Observation

/// Main-actor observable state for one module's latest sample and history.
@MainActor
@Observable
public final class ModuleStore<Sample: Sendable> {
    /// The most recently received sample.
    public private(set) var latestSample: Sample?

    /// The module's bounded sample history.
    public private(set) var history: History<Sample>

    /// A revision advanced by menu tracking timers so hosted views keep refreshing.
    public private(set) var revision = 0

    /// Creates an empty module store.
    public init(historyCapacity: Int) {
        history = History(capacity: historyCapacity)
    }

    /// Records a new sample.
    public func receive(_ sample: Sample, at timestamp: Date = Date()) {
        latestSample = sample
        history.append(sample, at: timestamp)
    }

    /// Advances the view revision while a dropdown is tracking.
    public func tick() {
        revision &+= 1
    }

    /// Clears the latest sample and history while preserving the configured capacity.
    public func reset() {
        latestSample = nil
        history = History(capacity: history.capacity)
        revision &+= 1
    }
}
