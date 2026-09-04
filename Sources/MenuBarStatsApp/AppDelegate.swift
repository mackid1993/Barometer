import AppKit
import MenuBarStatsCore
import MenuBarStatsUI
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bundleIdentifier = "com.barometer.app"
    private static let executableName = "Barometer"
    private static let openSettingsNotification = Notification.Name(
        "com.barometer.app.openSettings"
    )
    private static let logger = Logger(subsystem: bundleIdentifier, category: "application")

    private var statusItemRegistry: StatusItemRegistry?
    private var settingsWindowController: SettingsWindowController?
    private var monitoringCoordinator: MonitoringCoordinator?
    private var settingsStore: SettingsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard validateBundleIdentity() else {
            NSApp.terminate(nil)
            return
        }
        guard claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsFromNotification),
            name: Self.openSettingsNotification,
            object: nil
        )

        let registry = StatusItemRegistry()
        let settingsStore = SettingsStore()
        statusItemRegistry = registry
        self.settingsStore = settingsStore
        monitoringCoordinator = MonitoringCoordinator(
            registry: registry,
            settingsStore: settingsStore,
            settingsAction: { [weak self] in self?.showSettings() },
            quitAction: { NSApp.terminate(nil) }
        )
        Self.logger.info("Barometer started")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.logger.info("Barometer will terminate")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitoringCoordinator?.stop()
        settingsStore?.saveNow()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func claimSingleInstance() -> Bool {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard let existingApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleIdentifier)
            .first(where: { $0.processIdentifier != currentProcessIdentifier })
        else {
            return true
        }

        DistributedNotificationCenter.default().postNotificationName(
            Self.openSettingsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        existingApplication.activate()
        Self.logger.notice("Another Barometer instance is already running")
        return false
    }

    private func validateBundleIdentity() -> Bool {
        let bundle = Bundle.main
        let actualIdentifier = bundle.bundleIdentifier ?? "none"
        let actualExecutable = bundle.executableURL?.lastPathComponent ?? "none"
        let isApplicationBundle = bundle.bundleURL.pathExtension == "app"
        guard actualIdentifier == Self.bundleIdentifier,
              actualExecutable == Self.executableName,
              isApplicationBundle
        else {
            let message = "Refusing unbundled launch: bundle=\(actualIdentifier) "
                + "executable=\(actualExecutable) isAppBundle=\(isApplicationBundle)"
            Self.logger.fault("\(message, privacy: .public)")
            return false
        }
        let message = "Validated status-item owner bundle=\(actualIdentifier) executable=\(actualExecutable)"
        Self.logger.info("\(message, privacy: .public)")
        return true
    }

    private func showSettings() {
        if settingsWindowController == nil {
            guard let settingsStore, let monitoringCoordinator else {
                return
            }
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                gpuStore: monitoringCoordinator.gpuStore,
                batteryStore: monitoringCoordinator.batteryStore,
                networkStore: monitoringCoordinator.networkStore,
                diskStore: monitoringCoordinator.diskStore,
                sensorStore: monitoringCoordinator.sensorStore
            )
        }
        settingsWindowController?.show()
    }

    @objc private func openSettingsFromNotification() {
        showSettings()
    }
}
