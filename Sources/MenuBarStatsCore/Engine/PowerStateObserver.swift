import SystemSources

/// App-facing external-power state without exposing system-source implementation details.
public enum PowerState: Equatable, Sendable {
    case acPower
    case batteryPower
    case unavailable
}

/// Bridges IOKit power-source notifications into the core layer.
@MainActor
public final class PowerStateObserver {
    /// Called whenever the providing power source changes.
    public var onChange: (@MainActor (PowerState) -> Void)?

    /// Current external-power state.
    public var currentState: PowerState {
        Self.convert(PowerSourceWatcher.currentState)
    }

    private let watcher: PowerSourceWatcher

    /// Starts observing external-power changes.
    public init() {
        let watcher = PowerSourceWatcher()
        self.watcher = watcher
        watcher.onChange = { [weak self] state in
            self?.onChange?(Self.convert(state))
        }
    }

    private static func convert(_ state: PowerSourceState) -> PowerState {
        switch state {
        case .acPower: .acPower
        case .batteryPower: .batteryPower
        case .unavailable: .unavailable
        }
    }
}
