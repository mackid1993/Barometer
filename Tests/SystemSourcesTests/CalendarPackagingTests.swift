import Foundation
import Testing

@Suite("Calendar permission packaging")
struct CalendarPackagingTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("Calendar permission metadata includes the hardened-runtime entitlement and usage description")
    func permissionMetadata() throws {
        let entitlements = try dictionary(at: "Scripts/Barometer.entitlements")
        #expect(entitlements["com.apple.security.personal-information.calendars"] as? Bool == true)
        // Calendar is the only newly enabled resource; this must not introduce other TCC categories.
        #expect(Set(entitlements.keys) == ["com.apple.security.personal-information.calendars"])
        let info = try dictionary(at: "Scripts/Info.plist")
        let description = try #require(info["NSCalendarsFullAccessUsageDescription"] as? String)
        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(info["CFBundleIdentifier"] as? String == "com.barometer.app")
        let environment = try #require(info["LSEnvironment"] as? [String: String])
        #expect(environment["MallocSpaceEfficient"] == "1")
    }

    @Test("both distribution and development signatures include Calendar resource access")
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
    }

    private func dictionary(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repository.appendingPathComponent(path))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
