import SystemSources

/// Shared metadata exposed by the core layer.
public enum MenuBarStatsCoreMetadata {
    /// Whether the underlying system-source layer is present.
    public static let systemSourcesAvailable = SystemSourcesAvailability.isAvailable
}
