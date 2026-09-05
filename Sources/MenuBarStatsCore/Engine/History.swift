import Foundation

/// A timestamped value stored in a history buffer.
public struct HistoryEntry<Value: Sendable>: Sendable {
    /// The wall-clock time at which the value was collected.
    public let timestamp: Date

    /// The collected value.
    public let value: Value

    /// Creates a timestamped value.
    public init(timestamp: Date, value: Value) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// A fixed-capacity ring buffer for timestamped samples.
public struct History<Value: Sendable>: Sendable {
    /// Maximum number of entries retained by the buffer.
    public let capacity: Int

    private var storage: [HistoryEntry<Value>]
    private var startIndex = 0
    private var timestampsAreOrdered = true

    // Internal allocation diagnostic for regression tests; an empty history reserves no slots.
    var allocatedCapacity: Int { storage.capacity }

    /// Number of entries currently stored.
    public private(set) var count = 0

    /// Creates an empty history with a positive capacity.
    public init(capacity: Int) {
        precondition(capacity > 0, "History capacity must be positive")
        self.capacity = capacity
        storage = []
    }

    /// Entries in chronological order.
    ///
    /// Materializes the whole buffer, which can hold a day of samples. Prefer `recent(_:)` on any
    /// path that runs per sample.
    public var entries: [HistoryEntry<Value>] {
        recent(count)
    }

    /// The newest `maxCount` entries in chronological order.
    ///
    /// Menu bar graphs are a few dozen points wide and dropdowns show a bounded window, so callers
    /// ask for what they draw. Building the full array instead made every status item update cost
    /// one allocation and copy per retained sample, which grew with uptime until a single CPU item
    /// was copying tens of thousands of samples every second.
    public func recent(_ maxCount: Int) -> [HistoryEntry<Value>] {
        let wanted = min(max(0, maxCount), count)
        guard wanted > 0 else {
            return []
        }
        var result: [HistoryEntry<Value>] = []
        result.reserveCapacity(wanted)
        for offset in (count - wanted)..<count {
            result.append(storage[(startIndex + offset) % count])
        }
        return result
    }

    /// Appends a value, replacing the oldest entry when the buffer is full.
    public mutating func append(_ value: Value, at timestamp: Date = Date()) {
        if count > 0, timestamp < entry(at: count - 1).timestamp {
            timestampsAreOrdered = false
        }
        if count < capacity {
            storage.append(HistoryEntry(timestamp: timestamp, value: value))
            count += 1
        } else {
            storage[startIndex] = HistoryEntry(timestamp: timestamp, value: value)
            startIndex = (startIndex + 1) % capacity
        }
    }

    /// Returns entries no older than the requested duration relative to `now`.
    public func last(_ duration: Duration, now: Date = Date()) -> [HistoryEntry<Value>] {
        let cutoff = now.addingTimeInterval(-duration.timeInterval)
        return entries.filter { $0.timestamp >= cutoff && $0.timestamp <= now }
    }

    /// Returns at most `targetCount` entries in a time window without copying the full history.
    /// Both endpoints are preserved, including when the wall clock has moved backward.
    public func downsampled(to targetCount: Int, since cutoff: Date? = nil) -> [HistoryEntry<Value>] {
        precondition(targetCount > 0, "Downsample target must be positive")
        guard count > 0 else { return [] }
        if let cutoff, !timestampsAreOrdered {
            return downsampleUnordered(to: targetCount, since: cutoff)
        }
        var lower = 0
        if let cutoff {
            var upper = count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if entry(at: middle).timestamp < cutoff {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
        }
        let available = count - lower
        let wanted = min(targetCount, available)
        guard wanted > 0 else { return [] }
        guard wanted > 1 else { return [entry(at: count - 1)] }
        return (0..<wanted).map { index in
            let offset = Int((Double(index) * Double(available - 1) / Double(wanted - 1)).rounded())
            return entry(at: lower + offset)
        }
    }

    // Clock corrections can make timestamps nonmonotonic. Scan twice in that rare case,
    // retaining only output points rather than allocating a full filtered history.
    private func downsampleUnordered(to targetCount: Int, since cutoff: Date) -> [HistoryEntry<Value>] {
        let available = (0..<count).reduce(0) { $0 + (entry(at: $1).timestamp >= cutoff ? 1 : 0) }
        let wanted = min(targetCount, available)
        guard wanted > 0 else { return [] }
        var result: [HistoryEntry<Value>] = []
        result.reserveCapacity(wanted)
        var rank = 0
        for index in 0..<count {
            let candidate = entry(at: index)
            guard candidate.timestamp >= cutoff else { continue }
            let target = wanted == 1 ? available - 1
                : Int((Double(result.count) * Double(available - 1) / Double(wanted - 1)).rounded())
            if rank == target {
                result.append(candidate)
                if result.count == wanted { break }
            }
            rank += 1
        }
        return result
    }

    private func entry(at index: Int) -> HistoryEntry<Value> {
        storage[(startIndex + index) % count]
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let value = components
        return TimeInterval(value.seconds) + TimeInterval(value.attoseconds) / 1e18
    }
}
