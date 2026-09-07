import Foundation
import SystemSources
import Testing
@testable import MenuBarStatsUI

@Suite("NotificationRouterTests")
@MainActor
struct NotificationRouterTests {
    private func notification(
        app: String, title: String, body: String? = nil, deepLink: URL? = nil, category: String? = nil,
        hints: [String] = []
    ) -> DeliveredNotification {
        DeliveredNotification(
            id: UUID().uuidString, applicationIdentifier: app, title: title, subtitle: nil, body: body,
            date: Date(), deepLink: deepLink, category: category, hints: hints)
    }

    @Test("the notification's own deep link wins over everything else")
    func deepLinkFirst() throws {
        let link = try #require(URL(string: "messages://open?chat=123"))
        let message = notification(app: "com.apple.MobileSMS", title: "Sam", body: "On my way", deepLink: link,
                                   hints: ["https://example.com"])
        #expect(NotificationRouter.destination(for: message, folders: []) == .open(link))
    }

    @Test("a download notification reveals the finished file with its on-disk spelling")
    func downloads() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerRouter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Barometer-1.0.7.dmg")
        try Data().write(to: file)

        let download = notification(app: "com.vivaldi.Vivaldi", title: "Download Complete", body: "barometer-1.0.7.DMG")
        #expect(NotificationRouter.destination(for: download, folders: [folder]) == .revealFile(file))

        let traversal = notification(app: "com.example", title: "../Barometer-1.0.7.dmg")
        #expect(NotificationRouter.destination(for: traversal, folders: [folder]) == .activateApplication("com.example"))
    }

    @Test("user-data hints open an existing path or a web link, and skip the rest")
    func hints() throws {
        let existing = notification(app: "com.example", title: "Export finished", hints: ["/tmp/report.pdf"])
        #expect(NotificationRouter.destination(for: existing, folders: [], fileExists: { $0 == "/tmp/report.pdf" })
            == .revealFile(URL(fileURLWithPath: "/tmp/report.pdf")))
        let missing = notification(app: "com.example", title: "Export finished",
                                   hints: ["/tmp/gone.pdf", "https://example.com/build/42"])
        #expect(NotificationRouter.destination(for: missing, folders: [], fileExists: { _ in false })
            == .open(try #require(URL(string: "https://example.com/build/42"))))
        let extensionOnly = notification(app: "com.example", title: "Ping", hints: ["ftp://example.com"])
        #expect(NotificationRouter.destination(for: extensionOnly, folders: [], fileExists: { _ in false })
            == .activateApplication("com.example"))
    }

    @Test("system notifications open their System Settings pane or application")
    func systemPanes() throws {
        let updates = notification(app: "com.apple.AppStore", title: "Updates Available",
                                   category: "asd-category-updates-available")
        #expect(NotificationRouter.destination(for: updates, folders: [])
            == .open(try #require(URL(string: "macappstore://showUpdatesPage"))))
        let backup = notification(app: "_SYSTEM_CENTER_:com.apple.TMHelperAgent", title: "Backup Completed")
        #expect(NotificationRouter.destination(for: backup, folders: [])
            == .open(try #require(URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"))))
        let lowBattery = notification(app: "com.apple.controlcenter.notifications.low-battery", title: "Low Battery")
        #expect(NotificationRouter.destination(for: lowBattery, folders: [])
            == .open(try #require(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings"))))
        let passwords = notification(app: "com.apple.Passwords", title: "Compromised password")
        #expect(NotificationRouter.destination(for: passwords, folders: [])
            == .activateApplication("com.apple.Passwords"))
        #expect(NotificationApplicationResolver.applicationBundleIdentifier("_SYSTEM_CENTER_:com.apple.sharingd")
            == "com.apple.sharingd")
    }
}
