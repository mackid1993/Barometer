import Foundation

/// Persisted composition choices for the Combined status item.
public struct CombinedSettings: Codable, Equatable, Sendable {
    /// Module presentations shown from left to right.
    public var members: [ModuleID]

    /// Whether included modules are hidden as individual status items.
    public var hidesIndividualMembers: Bool

    /// Whether subtle separators are drawn between members.
    public var showsSeparators: Bool

    /// Creates Combined settings.
    public init(
        members: [ModuleID] = [.cpu, .memory],
        hidesIndividualMembers: Bool = false,
        showsSeparators: Bool = true
    ) {
        self.members = members
        self.hidesIndividualMembers = hidesIndividualMembers
        self.showsSeparators = showsSeparators
        normalize()
    }

    /// Removes recursive and duplicate membership while preserving display order.
    public mutating func normalize() {
        var seen: Set<ModuleID> = []
        members = members.filter { module in
            module != .combined && seen.insert(module).inserted
        }
    }
}

/// Revision sample used to redraw Combined whenever a member changes.
public struct CombinedSample: Equatable, Sendable {
    public let timestamp: Date

    /// Creates a redraw sample.
    public init(timestamp: Date = Date()) {
        self.timestamp = timestamp
    }
}
