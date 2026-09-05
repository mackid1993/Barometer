import CryptoKit
import Foundation

/// A numeric release version. Comparison is component-wise, so 1.3.10 follows 1.3.9.
public struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    private let components: [UInt]

    /// Parses a release version, accepting an optional leading `v` and prerelease suffix.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmed.drop(while: { $0 == "v" || $0 == "V" })
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty else { return nil }
        var parsed: [UInt] = []
        for field in fields.prefix(3) {
            let digits = field.prefix(while: \Character.isNumber)
            guard !digits.isEmpty, let value = UInt(digits) else { return nil }
            parsed.append(value)
        }
        while parsed.count < 3 {
            parsed.append(0)
        }
        components = parsed
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// The verified DMG published with a Barometer GitHub release.
public struct UpdateAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let sha256: String

    public init(name: String, downloadURL: URL, sha256: String) {
        self.name = name
        self.downloadURL = downloadURL
        self.sha256 = sha256
    }
}

/// A newer Barometer release that can be downloaded and verified.
public struct UpdateRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let notes: String
    public let asset: UpdateAsset

    public init(version: ReleaseVersion, notes: String, asset: UpdateAsset) {
        self.version = version
        self.notes = notes
        self.asset = asset
    }
}

/// Result of checking GitHub Releases.
public enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate(ReleaseVersion)
    case newer(UpdateRelease)
}

/// Checks, downloads, and verifies Barometer releases without adding an update framework.
public struct UpdateService: Sendable {
    public static let latestReleaseURL: URL = {
        guard let url = URL(string: "https://api.github.com/repos/mackid1993/Barometer/releases/latest") else {
            preconditionFailure("The Barometer releases URL must be valid")
        }
        return url
    }()
    public static let releaseDownloadPrefix = "https://github.com/mackid1993/Barometer/releases/download/"
    public static let maximumReleaseReplyBytes = 1 * 1_024 * 1_024
    public static let maximumDownloadBytes = 32 * 1_024 * 1_024

    private let session: URLSession
    private let currentVersion: ReleaseVersion
    private let updateDirectory: URL

    /// Creates the live GitHub updater using the packaged app version.
    public static func live(bundle: Bundle = .main) -> UpdateService {
        let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard let version = ReleaseVersion(text) ?? ReleaseVersion("0.0.0") else {
            preconditionFailure("The fallback Barometer version must be valid")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return UpdateService(
            session: URLSession(configuration: configuration, delegate: TrustedUpdateRedirects(), delegateQueue: nil),
            currentVersion: version,
            updateDirectory: defaultUpdateDirectory
        )
    }

    /// Creates an updater with injectable dependencies for deterministic tests.
    public init(
        session: URLSession,
        currentVersion: ReleaseVersion,
        updateDirectory: URL? = nil
    ) {
        self.session = session
        self.currentVersion = currentVersion
        self.updateDirectory = updateDirectory ?? Self.defaultUpdateDirectory
    }

    /// Queries the latest published release and requires its exact, digested DMG asset.
    public func check() async throws -> UpdateCheckOutcome {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("Barometer/\(currentVersion) (+https://github.com/mackid1993/Barometer)",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, maximumBytes: Self.maximumReleaseReplyBytes)
        guard data.count <= Self.maximumReleaseReplyBytes else {
            throw UpdateError.releaseReplyTooLarge
        }
        let release = try Self.parseRelease(data)
        return release.version > currentVersion ? .newer(release) : .upToDate(currentVersion)
    }

    /// Downloads a release to a private temporary directory and verifies its GitHub digest.
    public func download(_ release: UpdateRelease) async throws -> URL {
        guard Self.isTrustedReleaseDownload(release.asset.downloadURL),
              Self.isSafeAssetName(release.asset.name)
        else {
            throw UpdateError.untrustedAsset
        }
        var request = URLRequest(url: release.asset.downloadURL)
        request.setValue("Barometer/\(currentVersion) (+https://github.com/mackid1993/Barometer)",
                         forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        try Self.validate(response: response, maximumBytes: Self.maximumDownloadBytes)
        let fileManager = FileManager.default
        let size = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber
        guard let size, size.intValue <= Self.maximumDownloadBytes else {
            try? fileManager.removeItem(at: temporaryURL)
            throw UpdateError.downloadTooLarge
        }
        guard try Self.sha256(of: temporaryURL) == release.asset.sha256.lowercased() else {
            try? fileManager.removeItem(at: temporaryURL)
            throw UpdateError.digestMismatch
        }

        Self.sweep(directory: updateDirectory, fileManager: fileManager)
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        let destination = updateDirectory.appendingPathComponent("Barometer-update-\(release.asset.name)")
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    /// Removes only stale DMGs created by this updater.
    public static func sweep(fileManager: FileManager = .default) {
        sweep(directory: defaultUpdateDirectory, fileManager: fileManager)
    }

    static func sweep(directory: URL, fileManager: FileManager = .default) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("Barometer-update-")
            && entry.pathExtension.lowercased() == "dmg" {
            try? fileManager.removeItem(at: entry)
        }
        try? fileManager.removeItem(at: directory)
    }

    /// Clicker's offer rule: skipped versions stay quiet automatically, while manual checks always report them.
    public static func shouldOffer(version: ReleaseVersion, skippedVersion: String?, requestedManually: Bool) -> Bool {
        requestedManually || skippedVersion != version.description
    }

    /// Parses GitHub's release JSON and selects the exact `Barometer-X.Y.Z.dmg` asset with a SHA-256 digest.
    public static func parseRelease(_ data: Data) throws -> UpdateRelease {
        let response: ReleaseResponse
        do {
            response = try JSONDecoder().decode(ReleaseResponse.self, from: data)
        } catch {
            throw UpdateError.unreadableRelease
        }
        guard let version = ReleaseVersion(response.tagName) else {
            throw UpdateError.unreadableRelease
        }
        let expectedName = "Barometer-\(version).dmg"
        guard let responseAsset = response.assets.first(where: { $0.name == expectedName }),
              let url = URL(string: responseAsset.downloadURL),
              let digest = responseAsset.digest?.lowercased().removingPrefix("sha256:"),
              digest.count == 64,
              digest.allSatisfy(\Character.isHexDigit),
              isTrustedReleaseDownload(url)
        else {
            throw UpdateError.missingVerifiedDMG
        }
        let rawNotes = response.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = rawNotes.isEmpty
            ? "No release notes were provided."
            : String(rawNotes.prefix(16_000))
        return UpdateRelease(
            version: version,
            notes: notes,
            asset: UpdateAsset(name: expectedName, downloadURL: url, sha256: digest)
        )
    }

    /// Verifies bytes against the release digest.
    public static func verifyDigest(_ data: Data, expected: String) -> Bool {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual.caseInsensitiveCompare(expected) == .orderedSame
    }

    static func isTrustedReleaseDownload(_ url: URL) -> Bool {
        url.absoluteString.hasPrefix(releaseDownloadPrefix)
    }

    static func isSafeAssetName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 128
            && name.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0)
            }
    }

    public static var defaultUpdateDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Barometer-update", isDirectory: true)
    }

    private static func validate(response: URLResponse, maximumBytes: Int) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw UpdateError.httpStatus(status)
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            throw maximumBytes == maximumReleaseReplyBytes
                ? UpdateError.releaseReplyTooLarge
                : UpdateError.downloadTooLarge
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Errors written for people rather than URLSession internals.
public enum UpdateError: LocalizedError, Equatable {
    case httpStatus(Int?)
    case releaseReplyTooLarge
    case unreadableRelease
    case missingVerifiedDMG
    case untrustedAsset
    case downloadTooLarge
    case digestMismatch

    public var errorDescription: String? {
        switch self {
        case .httpStatus(403), .httpStatus(429):
            "GitHub is rate limiting this Mac. Try again in a little while."
        case .httpStatus(let status):
            status.map { "GitHub answered \($0)." } ?? "GitHub did not return a web response."
        case .releaseReplyTooLarge:
            "GitHub's release reply was unexpectedly large."
        case .unreadableRelease:
            "GitHub answered, but its reply did not name a readable Barometer release."
        case .missingVerifiedDMG:
            "The latest Barometer release has no verified DMG."
        case .untrustedAsset:
            "That release's DMG is not a safe Barometer GitHub Release download."
        case .downloadTooLarge:
            "The update was far larger than a Barometer DMG."
        case .digestMismatch:
            "The update failed GitHub's SHA-256 integrity check and was discarded."
        }
    }
}

private struct ReleaseResponse: Decodable {
    let tagName: String
    let body: String?
    let assets: [ReleaseAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct ReleaseAssetResponse: Decodable {
    let name: String
    let downloadURL: String
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }
}

private final class TrustedUpdateRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // Foundation may call this immutable delegate from its own queue. It has no mutable state.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let trustedHosts = [
            "github.com",
            "objects.githubusercontent.com",
            "release-assets.githubusercontent.com",
            "github-releases.githubusercontent.com",
        ]
        let url = request.url
        completionHandler(url?.scheme == "https" && trustedHosts.contains(url?.host ?? "") ? request : nil)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
