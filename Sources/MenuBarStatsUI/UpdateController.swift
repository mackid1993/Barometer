import AppKit
import MenuBarStatsCore
import Observation
import OSLog

/// Runs Clicker-style quiet and manual update checks, then opens a verified Barometer DMG.
@MainActor
@Observable
public final class UpdateController {
    /// Text shown beside the manual update control in About.
    public private(set) var statusMessage = "Checks automatically after launch"

    /// Whether a GitHub release check is in progress.
    public private(set) var isChecking = false

    /// Whether a selected update is being downloaded and verified.
    public private(set) var isDownloading = false

    /// Whether Barometer may make its delayed startup check.
    public private(set) var automaticChecksEnabled: Bool

    private static let skippedVersionKey = "Barometer.skippedUpdateVersion"
    private static let automaticChecksKey = "Barometer.automaticallyChecksForUpdates"
    private let service: UpdateService
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.barometer.app", category: "updates")
    private var checkGeneration = 0
    private var isPresentingOffer = false
    private var offerWindowController: UpdateOfferWindowController?

    /// Creates the updater. Tests can supply a private defaults suite and service.
    public init(
        service: UpdateService = .live(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        automaticChecksEnabled = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        statusMessage = automaticChecksEnabled ? "Checks automatically after launch" : "Automatic checks are off"
    }

    /// Starts Clicker's delayed, quiet startup check.
    public func startAutomaticCheck() {
        UpdateService.sweep()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.automaticChecksEnabled else { return }
            await self.check(requestedManually: false)
        }
    }

    /// Runs a check that always reports its result.
    public func checkManually() {
        Task { [weak self] in
            await self?.check(requestedManually: true)
        }
    }

    /// Enables or disables the quiet startup check without affecting manual checks.
    public func toggleAutomaticChecks() {
        automaticChecksEnabled.toggle()
        defaults.set(automaticChecksEnabled, forKey: Self.automaticChecksKey)
        statusMessage = automaticChecksEnabled ? "Checks automatically after launch" : "Automatic checks are off"
    }

    /// The label for the automatic-update preference button.
    public var automaticChecksButtonTitle: String {
        automaticChecksEnabled ? "Disable Automatic Checks" : "Enable Automatic Checks"
    }

    /// The manual button label follows the current updater phase.
    public var buttonTitle: String {
        if isDownloading { return "Downloading Update…" }
        if isChecking { return "Checking…" }
        return "Check for Updates…"
    }

    private func check(requestedManually: Bool) async {
        guard !isDownloading else {
            if requestedManually {
                announce(title: "Update in Progress", message: "Barometer is already downloading an update.")
            }
            return
        }
        checkGeneration += 1
        let generation = checkGeneration
        isChecking = true
        statusMessage = "Checking GitHub Releases…"
        do {
            let outcome = try await service.check()
            guard generation == checkGeneration else { return }
            isChecking = false
            switch outcome {
            case .upToDate(let version):
                statusMessage = "Barometer \(version) is up to date"
                if requestedManually {
                    announce(
                        title: "Barometer Is Up to Date",
                        message: "You are running the latest version, \(version)."
                    )
                }
            case .newer(let release):
                statusMessage = "Barometer \(release.version) is available"
                let skipped = defaults.string(forKey: Self.skippedVersionKey)
                if UpdateService.shouldOffer(
                    version: release.version,
                    skippedVersion: skipped,
                    requestedManually: requestedManually
                ) {
                    presentOffer(release)
                }
            }
        } catch {
            guard generation == checkGeneration else { return }
            isChecking = false
            let message = Self.message(for: error)
            statusMessage = message
            logger.error("Update check failed: \(message, privacy: .public)")
            if requestedManually {
                announce(title: "Unable to Check for Updates", message: message, style: .warning)
            }
        }
    }

    private func presentOffer(_ release: UpdateRelease) {
        guard !isPresentingOffer else { return }
        isPresentingOffer = true
        NSApp.activate()
        let controller = UpdateOfferWindowController(release: release) { [weak self] choice in
            guard let self else { return }
            self.isPresentingOffer = false
            self.offerWindowController = nil
            switch choice {
            case .install:
                self.download(release)
            case .skip:
                self.defaults.set(release.version.description, forKey: Self.skippedVersionKey)
                self.statusMessage = "Skipped Barometer \(release.version)"
            case .later:
                break
            }
        }
        offerWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func download(_ release: UpdateRelease) {
        guard !isDownloading else { return }
        isDownloading = true
        statusMessage = "Downloading Barometer \(release.version)…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await service.download(release)
                isDownloading = false
                statusMessage = "Verifying Barometer \(release.version)…"
                try await Task.detached {
                    try UpdateInstaller.verifyDiskImage(url)
                }.value
                try UpdateInstaller.scheduleInstallation(diskImage: url)
                statusMessage = "Installing Barometer \(release.version)…"
                NSApp.terminate(nil)
            } catch {
                isDownloading = false
                let message = Self.message(for: error)
                statusMessage = message
                logger.error("Update download failed: \(message, privacy: .public)")
                announce(title: "Unable to Download Update", message: message, style: .warning)
            }
        }
    }

    private func announce(title: String, message: String, style: NSAlert.Style = .informational) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "Barometer could not reach GitHub. Check the network and try again: \(error.localizedDescription)"
    }
}
