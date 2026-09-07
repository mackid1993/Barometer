import Foundation
import SystemSources
import Testing
@testable import MenuBarStatsUI

@Suite("NotificationRouterTests")
@MainActor
struct NotificationRouterTests {
    @Test("a download notification reveals the finished file; anything else activates the app")
    func routes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerRouter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Barometer-1.0.7.dmg")
        try Data().write(to: file)

        let download = DeliveredNotification(
            id: "1", applicationIdentifier: "com.vivaldi.Vivaldi", title: "Download Complete",
            subtitle: "Vivaldi", body: "barometer-1.0.7.DMG", date: Date())
        #expect(NotificationRouter.destination(for: download, folders: [folder]) == .revealFile(file))

        let message = DeliveredNotification(
            id: "2", applicationIdentifier: "com.apple.MobileSMS", title: "Sam", subtitle: nil,
            body: "On my way", date: Date())
        #expect(NotificationRouter.destination(for: message, folders: [folder])
            == .activateApplication("com.apple.MobileSMS"))

        let traversal = DeliveredNotification(
            id: "3", applicationIdentifier: "com.example", title: "../Barometer-1.0.7.dmg", subtitle: nil,
            body: nil, date: Date())
        #expect(NotificationRouter.destination(for: traversal, folders: [folder])
            == .activateApplication("com.example"))
    }
}
