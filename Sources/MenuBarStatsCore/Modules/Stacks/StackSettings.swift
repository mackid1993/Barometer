import Foundation

/// How a stack arranges its metrics inside one status item.
public enum StackLayout: String, Codable, CaseIterable, Sendable {
    /// Two metrics per column, expanding horizontally. Matches the Sensors compact stack.
    case columns

    /// Every metric on one line.
    case singleRow
}

/// Persisted configuration for one independently movable stack status item.
///
/// `id` is permanent and maps to a fixed autosave name. Ids are handed out from a saved high-water
/// mark rather than from the largest id in use, so deleting a stack is safe: the freed id is never
/// handed out again and a new stack can never inherit a deleted stack's saved menu bar position.
public struct StackSettings: Codable, Equatable, Identifiable, Sendable {
    /// Stable one-based instance used by the status item's numbered identity.
    public let id: Int

    /// Whether this status item is visible.
    public var isEnabled: Bool

    /// User-facing name.
    ///
    /// Settings only. The status item's accessibility label stays permanent, so renaming a stack
    /// never changes the identity a menu bar manager sees.
    public var name: String

    /// Arrangement used inside the item.
    public var layout: StackLayout

    /// Readings shown from left to right, in user-selected order.
    public var metrics: [StackMetric]

    /// Whether the individual status items of the modules in this stack are hidden.
    public var hidesSourceItems: Bool

    /// Creates one stack configuration.
    public init(
        id: Int,
        isEnabled: Bool = true,
        name: String = "",
        layout: StackLayout = .columns,
        metrics: [StackMetric] = [],
        hidesSourceItems: Bool = false
    ) {
        self.id = max(1, id)
        self.isEnabled = isEnabled
        self.name = name
        self.layout = layout
        self.metrics = metrics
        self.hidesSourceItems = hidesSourceItems
    }

    /// The name to show for this stack.
    ///
    /// Stacks are named by the person who creates them. Nothing here invents a name: a generated
    /// one would either follow the permanent instance number, which only moves upward and would
    /// reach "Stack 47", or follow the list position, which would silently rename every stack below
    /// a deleted one. The fallback exists only for a record that predates the naming prompt.
    public var displayName: String {
        name.isEmpty ? "Untitled" : name
    }

    /// Modules whose schedulers this stack needs running.
    public var sourceModules: Set<ModuleID> {
        Set(metrics.map(\.module))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case name
        case layout
        case metrics
        case hidesSourceItems
    }

    /// Decodes older stack records while preserving a valid permanent identity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = max(1, try container.decodeIfPresent(Int.self, forKey: .id) ?? 1)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        layout = try container.decodeIfPresent(StackLayout.self, forKey: .layout) ?? .columns
        // An unknown metric from a newer build is dropped rather than failing the whole decode.
        metrics = (try container.decodeIfPresent([String].self, forKey: .metrics) ?? [])
            .compactMap(StackMetric.init(rawValue:))
        hidesSourceItems = try container.decodeIfPresent(Bool.self, forKey: .hidesSourceItems) ?? false
    }

    /// Encodes metrics as raw strings so an older build can still read the rest of the record.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(name, forKey: .name)
        try container.encode(layout, forKey: .layout)
        try container.encode(metrics.map(\.rawValue), forKey: .metrics)
        try container.encode(hidesSourceItems, forKey: .hidesSourceItems)
    }
}

/// Stacks the user has created, in display order.
///
/// There is no cap. Every enabled stack is one more independently movable item counted by
/// `AppSettings.enabledMenuBarItemCount`, which shrinks the automatic font size and scale as items
/// are added, so a large number of stacks costs legibility rather than correctness.
public struct StacksSettings: Codable, Equatable, Sendable {
    /// Stacks in permanent identity order.
    public var stacks: [StackSettings]

    /// Smallest instance number that has never been handed out.
    ///
    /// Persisted rather than derived from the stacks in use. Deleting a stack must not release its
    /// autosave name for reuse: a later stack given the same name would inherit the deleted item's
    /// saved menu bar position.
    public private(set) var nextID: Int

    /// Creates stack settings.
    public init(stacks: [StackSettings] = [], nextID: Int = 1) {
        self.stacks = Self.normalized(stacks)
        self.nextID = max(nextID, (self.stacks.map(\.id).max() ?? 0) + 1)
    }

    /// Returns a stack by its permanent instance number.
    public func stack(id: Int) -> StackSettings? {
        stacks.first { $0.id == id }
    }

    /// Reserves the next never-used instance number.
    public mutating func allocateID() -> Int {
        let id = max(nextID, (stacks.map(\.id).max() ?? 0) + 1)
        nextID = id + 1
        return id
    }

    /// Deletes one stack. Its instance number stays spent.
    public mutating func remove(id: Int) {
        stacks.removeAll { $0.id == id }
    }

    /// Whether a source update can change any enabled stack's readings.
    public func needsSample(from module: ModuleID) -> Bool {
        stacks.contains { $0.isEnabled && $0.metrics.contains { $0.module == module } }
    }

    /// Modules that at least one enabled stack needs sampled.
    public var activeSourceModules: Set<ModuleID> {
        stacks.filter(\.isEnabled).reduce(into: Set<ModuleID>()) { result, stack in
            result.formUnion(stack.sourceModules)
        }
    }

    /// Modules whose individual status items an enabled stack hides.
    public var hiddenSourceModules: Set<ModuleID> {
        stacks.filter { $0.isEnabled && $0.hidesSourceItems }.reduce(into: Set<ModuleID>()) { result, stack in
            result.formUnion(stack.sourceModules)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case stacks
        case nextID
    }

    /// Decodes stacks while supplying defaults added after the feature shipped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stacks = Self.normalized(try container.decodeIfPresent([StackSettings].self, forKey: .stacks) ?? [])
        // A record written before the counter existed falls back to the highest id it contains,
        // which is correct because that build could not delete a stack.
        nextID = max(
            try container.decodeIfPresent(Int.self, forKey: .nextID) ?? 1,
            (stacks.map(\.id).max() ?? 0) + 1
        )
    }

    /// Builds the first stack from an older Combined membership.
    ///
    /// Combined composed whole module presentations, so each member contributes its primary reading
    /// and an upgrading user keeps an item showing the same modules in the same order. A user who
    /// never turned Combined on starts with no stacks at all rather than a prefilled one.
    public static func migrating(from combined: CombinedSettings, isCombinedEnabled: Bool) -> StacksSettings {
        let metrics = combined.members.compactMap(StackMetric.primary(for:))
        guard isCombinedEnabled, !metrics.isEmpty else {
            return StacksSettings()
        }
        return StacksSettings(stacks: [
            StackSettings(
                id: 1,
                isEnabled: true,
                // Keeps the name the item already had in the menu bar.
                name: "Combined",
                metrics: metrics,
                hidesSourceItems: combined.hidesIndividualMembers
            )
        ])
    }

    /// Removes duplicate identities and keeps stacks in permanent identity order.
    private static func normalized(_ stacks: [StackSettings]) -> [StackSettings] {
        var seen: Set<Int> = []
        return stacks.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
    }
}
