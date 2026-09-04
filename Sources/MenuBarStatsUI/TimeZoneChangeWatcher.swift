import Foundation

/// Reports system time-zone and clock changes without polling.
@MainActor
final class TimeZoneChangeWatcher {
    var onChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        observers = [
            center.addObserver(
                forName: NSNotification.Name.NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            },
            center.addObserver(
                forName: NSNotification.Name.NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            },
        ]
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
