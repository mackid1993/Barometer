import AppKit
import MenuBarStatsCore
import OSLog

/// Owns every status item created by the application process.
@MainActor
public final class StatusItemRegistry: NSObject {
    private static let identityLogger = Logger(subsystem: "com.barometer.app", category: "identity")

    private var items: [StatusItemIdentity: NSStatusItem] = [:]

    /// Creates an empty registry. Module items are created when first requested.
    public override init() {
        super.init()
        perform(#selector(runIdentitySelfTest), with: nil, afterDelay: 1)
    }

    /// Returns the stable status item for a module, creating it on first use.
    public func item(for module: ModuleID) -> NSStatusItem {
        item(for: StatusItemIdentity(module: module))
    }

    /// Returns the stable status item for a numbered module instance.
    public func item(for module: ModuleID, instance: Int) -> NSStatusItem {
        item(for: StatusItemIdentity(module: module, instance: instance))
    }

    /// Returns a stable status item, creating it once for the process lifetime.
    public func item(for identity: StatusItemIdentity) -> NSStatusItem {
        if let statusItem = items[identity] {
            return statusItem
        }

        let statusItem = makeItem(for: identity)
        items[identity] = statusItem
        return statusItem
    }

    /// Changes a status item's visibility without changing its identity or lifetime.
    public func setVisible(_ isVisible: Bool, for module: ModuleID) {
        let statusItem = item(for: module)
        if statusItem.isVisible != isVisible {
            statusItem.isVisible = isVisible
        }
    }

    private func makeItem(for identity: StatusItemIdentity) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // NSStatusBar creates items visible. Hide synchronously, before identity setup or
        // returning to the run loop, so a menu bar manager cannot catalog a placeholder.
        statusItem.isVisible = false
        statusItem.autosaveName = identity.autosaveName
        statusItem.behavior = []

        guard let button = statusItem.button else {
            preconditionFailure("AppKit did not create a status item button for \(identity.displayName)")
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityIdentifier(identity.autosaveName)
        button.setAccessibilityLabel(identity.displayName)
        return statusItem
    }

    @objc private func runIdentitySelfTest() {
        var records: [StatusItemDiagnosticRecord] = []
        for (identity, statusItem) in items.sorted(by: { $0.key.autosaveName < $1.key.autosaveName }) {
            guard let button = statusItem.button else {
                assertionFailure("Missing status item button for \(identity.displayName)")
                continue
            }

            let windowTitle = button.window?.title ?? ""
            let identifier = button.accessibilityIdentifier()
            let label = button.accessibilityLabel() ?? ""
            let title = button.accessibilityTitle() ?? ""
            let message =
                "autosaveName=\(identity.autosaveName) window.title=\(windowTitle) "
                + "AXIdentifier=\(identifier) AXLabel=\(label) AXTitle=\(title)"
            Self.identityLogger.notice("\(message, privacy: .public)")

            records.append(
                StatusItemDiagnosticRecord(
                    module: identity.displayName,
                    autosaveName: identity.autosaveName,
                    isVisible: statusItem.isVisible,
                    statusItemLength: statusItem.length,
                    windowNumber: button.window?.windowNumber,
                    windowIsVisible: button.window?.isVisible,
                    windowIsOnActiveSpace: button.window?.isOnActiveSpace,
                    windowIsOccluded: button.window?.occlusionState.contains(.visible) == false,
                    windowFrame: button.window.map { DiagnosticRect($0.frame) },
                    buttonFrame: DiagnosticRect(button.frame),
                    imageSize: button.image.map { DiagnosticSize($0.size) },
                    imageIsTemplate: button.image?.isTemplate,
                    imageRepresentationCount: button.image?.representations.count,
                    imageTIFFByteCount: button.image?.tiffRepresentation?.count,
                    windowTitle: windowTitle,
                    accessibilityIdentifier: identifier,
                    accessibilityLabel: label,
                    accessibilityTitle: title,
                    accessibilityValue: button.accessibilityValue() as? String,
                    buttonTitle: button.title
                )
            )

            assert(windowTitle == identity.autosaveName)
            assert(identifier == identity.autosaveName)
            assert(label == identity.displayName)
            assert(title.isEmpty)
            assert(button.title.isEmpty)
        }
        writeIdentityDiagnostics(records)
    }

    private func writeIdentityDiagnostics(_ records: [StatusItemDiagnosticRecord]) {
        let runningApplication = NSRunningApplication.current
        let report = IdentityDiagnosticReport(
            generatedAt: Date(),
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundlePath: Bundle.main.bundleURL.path,
            executablePath: Bundle.main.executableURL?.path,
            runningApplicationBundleIdentifier: runningApplication.bundleIdentifier,
            runningApplicationBundlePath: runningApplication.bundleURL?.path,
            statusItems: records
        )
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Barometer", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("identity.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
            Self.identityLogger.notice("Identity diagnostics written to \(url.path, privacy: .public)")
        } catch {
            Self.identityLogger.error("Unable to write identity diagnostics: \(error, privacy: .public)")
        }
    }
}

private struct IdentityDiagnosticReport: Encodable {
    let generatedAt: Date
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let bundlePath: String
    let executablePath: String?
    let runningApplicationBundleIdentifier: String?
    let runningApplicationBundlePath: String?
    let statusItems: [StatusItemDiagnosticRecord]
}

private struct StatusItemDiagnosticRecord: Encodable {
    let module: String
    let autosaveName: String
    let isVisible: Bool
    let statusItemLength: Double
    let windowNumber: Int?
    let windowIsVisible: Bool?
    let windowIsOnActiveSpace: Bool?
    let windowIsOccluded: Bool
    let windowFrame: DiagnosticRect?
    let buttonFrame: DiagnosticRect
    let imageSize: DiagnosticSize?
    let imageIsTemplate: Bool?
    let imageRepresentationCount: Int?
    let imageTIFFByteCount: Int?
    let windowTitle: String
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityTitle: String
    let accessibilityValue: String?
    let buttonTitle: String
}

private struct DiagnosticRect: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

private struct DiagnosticSize: Encodable {
    let width: Double
    let height: Double

    init(_ size: NSSize) {
        width = size.width
        height = size.height
    }
}
