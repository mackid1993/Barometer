import Foundation
import Testing

@Suite("Privacy permission packaging")
struct CalendarPackagingTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("privacy metadata includes hardened-runtime entitlements and usage descriptions")
    func permissionMetadata() throws {
        let entitlements = try dictionary(at: "Scripts/Barometer.entitlements")
        #expect(entitlements["com.apple.security.personal-information.calendars"] as? Bool == true)
        #expect(entitlements["com.apple.security.personal-information.location"] as? Bool == true)
        #expect(Set(entitlements.keys) == [
            "com.apple.security.personal-information.calendars",
            "com.apple.security.personal-information.location",
        ])
        let info = try dictionary(at: "Scripts/Info.plist")
        let calendarDescription = try #require(info["NSCalendarsFullAccessUsageDescription"] as? String)
        let locationDescription = try #require(info["NSLocationUsageDescription"] as? String)
        #expect(!calendarDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!locationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(info["CFBundleIdentifier"] as? String == "com.barometer.app")
        let environment = try #require(info["LSEnvironment"] as? [String: String])
        #expect(environment["MallocSpaceEfficient"] == "1")
    }

    @Test("both distribution and development signatures include privacy resource access")
    func signingPaths() throws {
        let script = try String(contentsOf: repository.appendingPathComponent("Scripts/make-app.sh"), encoding: .utf8)
        let signingCommands = script.components(separatedBy: "codesign \\\n").dropFirst()
        #expect(signingCommands.count == 2)
        for command in signingCommands {
            let signingCommand = command.components(separatedBy: "\"$application_directory\"").first ?? ""
            #expect(signingCommand.contains("--entitlements Scripts/Barometer.entitlements"))
        }
        // Validate the signed artifact too, so a future packaging change cannot silently discard the key.
        #expect(script.contains("codesign --display --entitlements"))
        #expect(script.contains("Barometer.app is missing its Calendar access entitlement"))
        #expect(script.contains("Barometer.app is missing its Location access entitlement"))
    }

    private func dictionary(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repository.appendingPathComponent(path))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
