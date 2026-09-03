import MenuBarStatsCore

/// Shared metadata exposed by the UI layer.
public enum MenuBarStatsUIMetadata {
    /// Whether the core and system-source layers are present.
    public static let isAvailable = MenuBarStatsCoreMetadata.systemSourcesAvailable
}
