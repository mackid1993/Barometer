import CoreFoundation
import SystemConfiguration

/// Reports primary route and DNS configuration changes on the main run loop.
@MainActor
public final class NetworkConfigurationWatcher {
    /// Called after SystemConfiguration reports a relevant network change.
    public var onChange: (@MainActor () -> Void)?

    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?

    /// Starts observing primary IPv4, IPv6, and DNS state keys.
    public init() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(
            nil,
            "com.barometer.app.network-configuration" as CFString,
            { _, _, context in
                guard let context else {
                    return
                }
                let watcher = Unmanaged<NetworkConfigurationWatcher>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    watcher.onChange?()
                }
            },
            &context
        ) else {
            return
        }
        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6",
            "State:/Network/Global/DNS",
        ] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, nil),
              let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        else {
            return
        }
        self.store = store
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    isolated deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }
}
