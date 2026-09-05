import CryptoKit
import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("Updater")
struct UpdateTests {
    @Test("Numeric versions sort 1.3.10 after 1.3.9")
    func versionComparison() throws {
        let older = try #require(ReleaseVersion("v1.3.9"))
        let newer = try #require(ReleaseVersion("1.3.10-beta.1"))
        #expect(newer > older)
        #expect(ReleaseVersion("2")?.description == "2.0.0")
        #expect(ReleaseVersion("not-a-version") == nil)
    }

    @Test("A newer GitHub release downloads and verifies its exact DMG")
    func completePipeline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Barometer-update-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try service(updateDirectory: directory)

        let outcome = try await service.check()
        let release: UpdateRelease
        switch outcome {
        case .newer(let candidate):
            release = candidate
        case .upToDate:
            Issue.record("The stubbed 1.2.3 release must be newer than 1.0.0")
            return
        }

        #expect(release.asset.name == "Barometer-1.2.3.dmg")
        let downloaded = try await service.download(release)
        #expect(downloaded.deletingLastPathComponent() == directory)
        #expect(try Data(contentsOf: downloaded) == StubUpdateProtocol.dmg)
    }

    @Test("The pipeline rejects a release without GitHub's SHA-256 digest")
    func missingDigest() throws {
        let data = releaseJSON(digest: nil)
        #expect(throws: UpdateError.missingVerifiedDMG) {
            try UpdateService.parseRelease(data)
        }
    }

    @Test("The pipeline rejects a differently named installer")
    func wrongAssetName() throws {
        let data = releaseJSON(name: "Barometer-latest.dmg", digest: StubUpdateProtocol.digest)
        #expect(throws: UpdateError.missingVerifiedDMG) {
            try UpdateService.parseRelease(data)
        }
    }

    @Test("A tampered DMG is discarded")
    func digestMismatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Barometer-update-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try service(updateDirectory: directory)
        let release = UpdateRelease(
            version: try #require(ReleaseVersion("1.2.3")),
            notes: "Notes",
            asset: UpdateAsset(
                name: "Barometer-1.2.3.dmg",
                downloadURL: try #require(URL(string: StubUpdateProtocol.dmgURL)),
                sha256: String(repeating: "0", count: 64)
            )
        )
        await #expect(throws: UpdateError.digestMismatch) {
            try await service.download(release)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Skipped versions stay quiet automatically but remain available manually")
    func skipRule() throws {
        let version = try #require(ReleaseVersion("1.2.3"))
        #expect(!UpdateService.shouldOffer(
            version: version,
            skippedVersion: "1.2.3",
            requestedManually: false
        ))
        #expect(UpdateService.shouldOffer(
            version: version,
            skippedVersion: "1.2.3",
            requestedManually: true
        ))
    }

    @Test("The verified DMG installer replaces Barometer in Applications")
    func diskImageInstallation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Barometer-installer-test-\(UUID().uuidString)", isDirectory: true)
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let mount = root.appendingPathComponent("mount", isDirectory: true)
        let diskImage = root.appendingPathComponent("Barometer-1.2.3.dmg")
        defer { try? FileManager.default.removeItem(at: root) }

        let replacement = payload.appendingPathComponent("Barometer.app", isDirectory: true)
        try makeSignedApplication(at: replacement, marker: "new")
        try makeSignedApplication(
            at: applications.appendingPathComponent("Barometer.app", isDirectory: true),
            marker: "old"
        )
        try run(
            "/usr/bin/hdiutil",
            ["create", "-quiet", "-srcfolder", payload.path, "-volname", "Barometer Update",
             "-format", "UDZO", diskImage.path]
        )

        try UpdateInstaller.verifyDiskImage(diskImage)
        try UpdateInstaller.installForTesting(
            diskImage: diskImage,
            mount: mount,
            applicationsDirectory: applications
        )

        let installed = applications.appendingPathComponent("Barometer.app", isDirectory: true)
        let marker = installed.appendingPathComponent("Contents/Resources/marker.txt")
        #expect(try String(contentsOf: marker, encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(
            atPath: applications.appendingPathComponent(".Barometer.app.backup").path
        ))
        #expect(!FileManager.default.fileExists(atPath: diskImage.path))
    }

    private func service(updateDirectory: URL) throws -> UpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubUpdateProtocol.self]
        return UpdateService(
            session: URLSession(configuration: configuration),
            currentVersion: try #require(ReleaseVersion("1.0.0")),
            updateDirectory: updateDirectory
        )
    }

    private func releaseJSON(
        name: String = "Barometer-1.2.3.dmg",
        digest: String?
    ) -> Data {
        let digestField = digest.map { ", \"digest\": \"sha256:\($0)\"" } ?? ""
        return Data(
            """
            {
              "tag_name": "v1.2.3",
              "body": "## New release\\n\\n- Faster and smaller.",
              "assets": [{
                "name": "\(name)",
                "browser_download_url": "\(StubUpdateProtocol.dmgURL)"\(digestField)
              }]
            }
            """.utf8
        )
    }

    private func makeSignedApplication(at url: URL, marker: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"),
            to: executableDirectory.appendingPathComponent("Barometer")
        )
        try marker.write(
            to: resources.appendingPathComponent("marker.txt"),
            atomically: true,
            encoding: .utf8
        )
        let info: [String: Any] = [
            "CFBundleExecutable": "Barometer",
            "CFBundleIdentifier": "com.barometer.app",
            "CFBundleName": "Barometer",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "1",
        ]
        let plist = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        try run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Unknown command failure"
            Issue.record("\(executable) failed: \(message)")
            throw CocoaError(.executableNotLoadable)
        }
    }
}

private final class StubUpdateProtocol: URLProtocol {
    static let dmg = Data("verified Barometer disk image".utf8)
    static let digest = SHA256.hash(data: dmg).map { String(format: "%02x", $0) }.joined()
    static let dmgURL = "https://github.com/mackid1993/Barometer/releases/download/v1.2.3/Barometer-1.2.3.dmg"

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body: Data
        if url == UpdateService.latestReleaseURL {
            body = Data(
                """
                {
                  "tag_name": "v1.2.3",
                  "body": "## New release\\n\\n- Faster and smaller.",
                  "assets": [{
                    "name": "Barometer-1.2.3.dmg",
                    "browser_download_url": "\(Self.dmgURL)",
                    "digest": "sha256:\(Self.digest)"
                  }]
                }
                """.utf8
            )
        } else if url.absoluteString == Self.dmgURL {
            body = Self.dmg
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(body.count)"]
        )
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
