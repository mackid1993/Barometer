import Foundation
import IOKit.ps

/// The Mac's current external-power state.
public enum PowerSourceState: Equatable, Sendable {
    case acPower
    case batteryPower
    case unavailable
}

/// Reports IOKit power-source changes on the main run loop.
@MainActor
public final class PowerSourceWatcher {
    /// Called whenever the providing power source changes.
    public var onChange: (@MainActor (PowerSourceState) -> Void)?

    /// Whether IOKit currently reports at least one power source.
    public var isAvailable: Bool {
        Self.currentState != .unavailable
    }

    /// The currently providing power source.
    public static var currentState: PowerSourceState {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return .unavailable
        }
        return (type as String) == (kIOPSBatteryPowerValue as String) ? .batteryPower : .acPower
    }

    private var runLoopSource: CFRunLoopSource?

    /// Starts observing power-source notifications.
    public init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else {
                    return
                }
                let watcher = Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    watcher.handleChange()
                }
            },
            context
        )?.takeRetainedValue() else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    isolated deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    private func handleChange() {
        onChange?(Self.currentState)
    }
}
