import Foundation
import Observation

/// Main-actor observable state for one module's latest sample and history.
@MainActor
@Observable
public final class ModuleStore<Sample: HistoryProjecting> {
    /// The most recently received sample.
    public private(set) var latestSample: Sample?

    /// The module's bounded, compact graph history; full details live only in latestSample.
    public private(set) var history: History<Sample.GraphValue>

    /// A revision advanced by menu tracking timers so hosted views keep refreshing.
    public private(set) var revision = 0

    /// Creates an empty module store.
    public init(historyCapacity: Int) {
        history = History(capacity: historyCapacity)
    }

    /// Records a new sample.
    public func receive(_ sample: Sample, at timestamp: Date = Date()) {
        latestSample = sample
        history.append(sample.graphValue, at: timestamp)
    }

    /// Restores previously collected graph entries without replacing the latest live sample.
    public func restoreHistory(
        _ entries: [HistoryEntry<Sample.GraphValue>],
        since cutoff: Date,
        through end: Date = Date()
    ) {
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp })
        where entry.timestamp >= cutoff && entry.timestamp <= end {
            history.append(entry.value, at: entry.timestamp)
        }
        revision &+= 1
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
