import SystemSources

/// Main-actor bridge for primary-route and DNS changes.
@MainActor
public final class NetworkChangeObserver {
    /// Called when SystemConfiguration reports a relevant change.
    public var onChange: (@MainActor () -> Void)?

    private let watcher: NetworkConfigurationWatcher

    /// Starts observing network configuration changes.
    public init() {
        let watcher = NetworkConfigurationWatcher()
        self.watcher = watcher
        watcher.onChange = { [weak self] in
            self?.onChange?()
        }
    }
}
