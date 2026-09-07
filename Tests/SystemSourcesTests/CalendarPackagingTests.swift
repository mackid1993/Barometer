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

        let workflow = try String(
            contentsOf: repository.appendingPathComponent(".github/workflows/macos.yml"),
            encoding: .utf8
        )
        let distributionSigning = try #require(
            workflow.components(separatedBy: "- name: Sign app and build DMG").last?
                .components(separatedBy: "- name: Store notarization credentials").first
        )
        #expect(distributionSigning.contains("--entitlements Scripts/Barometer.entitlements"))
        #expect(distributionSigning.contains("codesign --display --entitlements"))
        #expect(distributionSigning.contains("calendars location"))
    }

    @Test("the C bridge keeps Apple's security diagnostics in local and CI builds")
    func cSecurityDiagnostics() throws {
        let package = try String(contentsOf: repository.appendingPathComponent("Package.swift"), encoding: .utf8)
        for flag in [
            "-ftrivial-auto-var-init=zero",
            "-Werror=return-type",
            "-Wuninitialized",
            "-Wconditional-uninitialized",
            "-Wimplicit-fallthrough",
            "-Wshorten-64-to-32",
            "-Werror=implicit-function-declaration",
            "-Wshadow",
            "-Wempty-body",
            "-Warray-bounds",
            "-Wreturn-stack-address",
            "-Wconversion",
            "-Wassign-enum",
            "-Wsign-compare",
        ] {
            #expect(package.contains("\"\(flag)\""))
        }

        let analyzer = try String(
            contentsOf: repository.appendingPathComponent("Scripts/audit-c-security.sh"),
            encoding: .utf8
        )
        #expect(analyzer.contains("security.FloatLoopCounter"))
        #expect(analyzer.contains("security.insecureAPI.rand"))
        #expect(analyzer.contains("security.insecureAPI.strcpy"))

        let workflow = try String(
            contentsOf: repository.appendingPathComponent(".github/workflows/tests.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("make security-audit"))
    }

    @Test("Swift 6.4 stays pinned across the package and every GitHub build")
    func swiftToolchain() throws {
        let package = try String(contentsOf: repository.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(package.hasPrefix("// swift-tools-version: 6.4"))

        let makefile = try String(contentsOf: repository.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(makefile.contains("/Applications/Xcode-beta.app/Contents/Developer"))

        for path in [
            ".github/workflows/check.yml",
            ".github/workflows/macos.yml",
            ".github/workflows/tests.yml",
        ] {
            let workflow = try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
            #expect(workflow.contains("runs-on: xcode-27"))
            #expect(workflow.contains("DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer"))
            #expect(!workflow.contains("Xcode_26.2"))
        }
    }

    @Test("CI stamps and verifies the requested release version")
    func releaseVersionStamping() throws {
        let appScript = try String(
            contentsOf: repository.appendingPathComponent("Scripts/make-app.sh"),
            encoding: .utf8
        )
        let diskImageScript = try String(
            contentsOf: repository.appendingPathComponent("Scripts/create-dmg.sh"),
            encoding: .utf8
        )
        let workflow = try String(
            contentsOf: repository.appendingPathComponent(".github/workflows/macos.yml"),
            encoding: .utf8
        )

        #expect(appScript.contains("BAROMETER_VERSION"))
        #expect(appScript.contains("bundle_version"))
        #expect(diskImageScript.contains("BAROMETER_VERSION"))
        #expect(diskImageScript.contains("Refusing to package"))
        #expect(workflow.contains("BAROMETER_VERSION=$VERSION"))
        #expect(workflow.contains("STAMPED_VERSION"))
        #expect(!workflow.contains("printf '%s\\n' \"$VERSION\" > VERSION"))
    }

    private func dictionary(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repository.appendingPathComponent(path))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
