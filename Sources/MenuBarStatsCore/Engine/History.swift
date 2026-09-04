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

    private var storage: [HistoryEntry<Value>?]
    private var startIndex = 0

    /// Number of entries currently stored.
    public private(set) var count = 0

    /// Creates an empty history with a positive capacity.
    public init(capacity: Int) {
        precondition(capacity > 0, "History capacity must be positive")
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
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
            if let entry = storage[(startIndex + offset) % capacity] {
                result.append(entry)
            }
        }
        return result
    }

    /// Appends a value, replacing the oldest entry when the buffer is full.
    public mutating func append(_ value: Value, at timestamp: Date = Date()) {
        if count < capacity {
            storage[(startIndex + count) % capacity] = HistoryEntry(timestamp: timestamp, value: value)
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

    /// Returns at most `targetCount` chronologically distributed entries, preserving both endpoints.
    public func downsampled(to targetCount: Int) -> [HistoryEntry<Value>] {
        precondition(targetCount > 0, "Downsample target must be positive")
        let orderedEntries = entries
        guard orderedEntries.count > targetCount else {
            return orderedEntries
        }
        guard targetCount > 1 else {
            return [orderedEntries[orderedEntries.count - 1]]
        }

        let lastIndex = orderedEntries.count - 1
        return (0..<targetCount).map { outputIndex in
            let position = Double(outputIndex) * Double(lastIndex) / Double(targetCount - 1)
            return orderedEntries[Int(position.rounded())]
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let value = components
        return TimeInterval(value.seconds) + TimeInterval(value.attoseconds) / 1e18
    }
}
