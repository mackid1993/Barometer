/// Compact presentation state for an independent system-control menu bar pill.
public struct SystemControlSample: Equatable, HistoryProjecting {
    /// SF Symbol shown inside the pill's fixed canvas.
    public let symbolName: String
    /// Current state exposed as the status item's Accessibility value.
    public let accessibilityValue: String
    /// Whether the system feature is currently active.
    public let isActive: Bool

    /// Creates the latest control state without retaining media or notification payloads in history.
    public init(symbolName: String, accessibilityValue: String, isActive: Bool) {
        self.symbolName = symbolName
        self.accessibilityValue = accessibilityValue
        self.isActive = isActive
    }

    /// Only the activity bit is retained in the one-entry history.
    public var graphValue: Bool { isActive }
}
