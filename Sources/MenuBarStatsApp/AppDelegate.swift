import AppKit
import MenuBarStatsCore
import MenuBarStatsUI
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bundleIdentifier = "net.brustein.MenuBarStats"
    private static let openSettingsNotification = Notification.Name(
        "net.brustein.MenuBarStats.openSettings"
    )
    private static let logger = Logger(subsystem: bundleIdentifier, category: "application")

    private var statusItemRegistry: StatusItemRegistry?
    private var settingsWindowController: SettingsWindowController?
    private var monitoringCoordinator: MonitoringCoordinator?
    private var settingsStore: SettingsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        let registry = StatusItemRegistry(
            settingsAction: { [weak self] in self?.showSettings() },
            quitAction: { NSApp.terminate(nil) }
        )
        let settingsStore = SettingsStore()
        statusItemRegistry = registry
        self.settingsStore = settingsStore
        monitoringCoordinator = MonitoringCoordinator(
            registry: registry,
            settingsStore: settingsStore,
            settingsAction: { [weak self] in self?.showSettings() },
            quitAction: { NSApp.terminate(nil) }
        )
        Self.logger.info("MenuBarStats started")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.logger.info("MenuBarStats will terminate")
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
        Self.logger.notice("Another MenuBarStats instance is already running")
        return false
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    @objc private func openSettingsFromNotification() {
        showSettings()
    }
}
