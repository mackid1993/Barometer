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

        // Clear legacy Barometer-only overrides and let AppKit own inter-item spacing.
        StatusItemSpacingPolicy.restoreSystemDefault()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsFromNotification),
            name: Self.openSettingsNotification,
            object: nil
        )

        let settingsStore = SettingsStore()
        // Register the complete launch-visible child set before any controller shows it.
        // Hidden AppKit slots have no AX counterpart and make managers pair an inactive
        // autosave name with a different visible Barometer item.
        let registry = StatusItemRegistry(settings: settingsStore.settings)
        statusItemRegistry = registry
        self.settingsStore = settingsStore
        monitoringCoordinator = MonitoringCoordinator(
            registry: registry,
            settingsStore: settingsStore,
            settingsAction: { [weak self] module in self?.showSettings(module: module) },
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
        guard
            let existingApplication =
                NSRunningApplication
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
            let message =
                "Refusing unbundled launch: bundle=\(actualIdentifier) "
                + "executable=\(actualExecutable) isAppBundle=\(isApplicationBundle)"
            Self.logger.fault("\(message, privacy: .public)")
            return false
        }
        let message = "Validated status-item owner bundle=\(actualIdentifier) executable=\(actualExecutable)"
        Self.logger.info("\(message, privacy: .public)")
        return true
    }

    private func showSettings(module: ModuleID? = nil) {
        if settingsWindowController == nil {
            guard let settingsStore, let monitoringCoordinator else {
                return
            }
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                gpuStore: monitoringCoordinator.gpuStore,
                batteryStore: monitoringCoordinator.batteryStore,
                timeStore: monitoringCoordinator.timeStore,
                networkStore: monitoringCoordinator.networkStore,
                diskStore: monitoringCoordinator.diskStore,
                sensorStore: monitoringCoordinator.sensorStore,
                calendarAccessAction: { [weak monitoringCoordinator] in
                    monitoringCoordinator?.requestCalendarAccess()
                },
                applyMenuBarChangesAction: { [weak self] in
                    self?.applyMenuBarChangesAndReopen()
                }
            )
        }
        settingsWindowController?.show(module: module)
    }

    @objc private func openSettingsFromNotification() {
        showSettings()
    }

    private func applyMenuBarChangesAndReopen() {
        guard let settingsStore, settingsStore.hasPendingMenuBarChanges else { return }

        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "sleep 0.75; /usr/bin/open \"$1\"",
            "barometer-relaunch",
            Bundle.main.bundleURL.path,
        ]
        relauncher.standardOutput = FileHandle.nullDevice
        relauncher.standardError = FileHandle.nullDevice

        do {
            try relauncher.run()
        } catch {
            let message = "Unable to schedule Barometer reopen: \(String(describing: error))"
            Self.logger.error("\(message, privacy: .public)")
            return
        }

        settingsStore.applyPendingMenuBarChanges()
        Self.logger.info("Applied menu bar visibility changes; reopening with new launch geometry")
        NSApp.terminate(nil)
    }
}
