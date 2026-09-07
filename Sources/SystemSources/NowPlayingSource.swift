import Darwin
import Dispatch
import Foundation
import ImageIO
import OSLog

/// Playback state for the system's current Now Playing application.
public enum NowPlayingPlaybackState: Equatable, Sendable {
    case playing
    case paused
}

/// A bounded snapshot of the item macOS currently reports as Now Playing.
public struct NowPlayingSnapshot: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let applicationBundleIdentifier: String?
    public let playbackState: NowPlayingPlaybackState
    public let duration: TimeInterval?
    public let elapsedTime: TimeInterval?
    public let artworkData: Data?

    /// Creates a Now Playing snapshot.
    public init(
        title: String,
        artist: String?,
        album: String?,
        applicationBundleIdentifier: String?,
        playbackState: NowPlayingPlaybackState,
        duration: TimeInterval?,
        elapsedTime: TimeInterval?,
        artworkData: Data?
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.playbackState = playbackState
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.artworkData = artworkData
    }
}

/// Transport commands supported by macOS's system Now Playing controls.
public enum NowPlayingCommand: Equatable, Sendable {
    case previous
    case togglePlayPause
    case next
}

/// Result of sending a system Now Playing transport command.
public enum NowPlayingCommandResult: Equatable, Sendable {
    case accepted
    case unavailable
    case failed
}

/// Result of asking MediaRemote for the current item.
public enum NowPlayingReadResult: Equatable, Sendable {
    case current(NowPlayingSnapshot)
    case idle
    case unavailable
}

/// Reads and controls the system's current Now Playing application through MediaRemote.
///
/// MediaRemote is private and can change between macOS releases. This type is its only caller in
/// Barometer. Every symbol is loaded at runtime, so macOS 26 and later degrade to unavailable when
/// the framework or a required function is absent. No entitlement, permission, or media session is
/// claimed by Barometer.
public actor NowPlayingSource {
    /// Largest artwork payload retained in one snapshot.
    public static let maximumArtworkBytes = 256 * 1_024
    private static let maximumArtworkDimension = 512

    private typealias DictionaryCallback = @convention(block) (CFDictionary?) -> Void
    private typealias StringCallback = @convention(block) (CFString?) -> Void
    private typealias GetNowPlayingInfoFunction =
        @convention(c) (DispatchQueue, @escaping DictionaryCallback) -> Void
    private typealias GetApplicationIdentifierFunction =
        @convention(c) (DispatchQueue, @escaping StringCallback) -> Void
    private typealias SendCommandFunction = @convention(c) (Int, CFDictionary?) -> Bool

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    private static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    private static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    private static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    private static let durationKey = "kMRMediaRemoteNowPlayingInfoDuration"
    private static let elapsedTimeKey = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    private static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"
    private static let callbackTimeout: DispatchTimeInterval = .milliseconds(750)
    private static let adapterTimeout: TimeInterval = 2.5
    private static let maximumAdapterOutputBytes = 512 * 1_024

    private let library: UnsafeMutableRawPointer?
    private let injectedRead: (@Sendable () async -> NowPlayingReadResult)?
    private let injectedCommand: (@Sendable (NowPlayingCommand) async -> NowPlayingCommandResult)?
    private let logger = Logger(subsystem: "com.barometer.app", category: "now-playing")

    /// Creates a source backed by the installed MediaRemote framework.
    public init() {
        library = dlopen(Self.frameworkPath, RTLD_NOW | RTLD_LOCAL)
        injectedRead = nil
        injectedCommand = nil
    }

    /// Creates a deterministic source for tests without loading or controlling MediaRemote.
    init(
        read: @escaping @Sendable () async -> NowPlayingReadResult,
        command: @escaping @Sendable (NowPlayingCommand) async -> NowPlayingCommandResult
    ) {
        library = nil
        injectedRead = read
        injectedCommand = command
    }

    /// Whether the installed framework contains all functions required for reading and control.
    ///
    /// Symbol availability does not prove that macOS permits the current process to read playback
    /// information. Call `read()` to determine whether MediaRemote actually supplies usable data.
    public var isAvailable: Bool {
        if injectedRead != nil, injectedCommand != nil { return true }
        return symbol("MRMediaRemoteGetNowPlayingInfo") != nil
            && symbol("MRMediaRemoteGetNowPlayingApplicationDisplayID") != nil
            && symbol("MRMediaRemoteSendCommand") != nil
    }

    /// Reads the system's current Now Playing item while preserving unavailable versus idle.
    public func read() async -> NowPlayingReadResult {
        if let injectedRead { return await injectedRead() }
        if let adapterResult = await readWithAdapter() { return adapterResult }
        guard let infoFunction = function(
            "MRMediaRemoteGetNowPlayingInfo",
            as: GetNowPlayingInfoFunction.self
        ) else {
            return .unavailable
        }
        let applicationIdentifier = await applicationIdentifier()
        let result: MediaRemoteCallbackResult<NowPlayingReadResult> = await withCheckedContinuation { continuation in
            let gate = MediaRemoteCallbackGate(continuation)
            infoFunction(DispatchQueue.global(qos: .userInitiated)) { dictionary in
                let information = dictionary as? [String: Any]
                gate.resume(.value(Self.readResult(
                    for: information,
                    applicationIdentifier: applicationIdentifier
                )))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.callbackTimeout) {
                gate.resume(.timedOut)
            }
        }
        switch result {
        case let .value(readResult):
            return readResult
        case .timedOut:
            logger.error("MediaRemote Now Playing read timed out")
            return .unavailable
        }
    }

    /// Convenience view of `read()` for callers that do not need unavailable versus idle.
    public func current() async -> NowPlayingSnapshot? {
        guard case let .current(snapshot) = await read() else { return nil }
        return snapshot
    }

    /// Sends a transport command to the current system Now Playing application.
    public func send(_ command: NowPlayingCommand) async -> NowPlayingCommandResult {
        if let injectedCommand { return await injectedCommand(command) }
        guard let function = function("MRMediaRemoteSendCommand", as: SendCommandFunction.self) else {
            return .unavailable
        }
        let accepted = function(Self.commandValue(command), nil)
        if !accepted {
            logger.error("MediaRemote rejected command \(String(describing: command), privacy: .public)")
        }
        return accepted ? .accepted : .failed
    }

    /// Decodes only the metadata needed by the compact UI and bounds artwork before retaining it.
    static func decode(
        _ information: [String: Any],
        applicationIdentifier: String?
    ) -> NowPlayingSnapshot? {
        let title = trimmed(information[titleKey])
        let artist = trimmed(information[artistKey])
        let album = trimmed(information[albumKey])
        guard let displayTitle = title ?? artist ?? album else { return nil }
        let playbackRate = number(information[playbackRateKey]) ?? 0
        let duration = nonnegativeNumber(information[durationKey])
        let elapsedTime = nonnegativeNumber(information[elapsedTimeKey]).map { elapsed in
            duration.map { min(elapsed, $0) } ?? elapsed
        }
        let artwork = information[artworkDataKey] as? Data
        let boundedArtwork = boundedArtwork(artwork)
        return NowPlayingSnapshot(
            title: displayTitle,
            artist: title == nil ? nil : artist,
            album: album,
            applicationBundleIdentifier: trimmed(applicationIdentifier),
            playbackState: playbackRate > 0 ? .playing : .paused,
            duration: duration,
            elapsedTime: elapsedTime,
            artworkData: boundedArtwork
        )
    }

    /// Classifies a MediaRemote callback without treating a denied or empty response as idle.
    static func readResult(
        for information: [String: Any]?,
        applicationIdentifier: String?
    ) -> NowPlayingReadResult {
        guard let information,
              !information.isEmpty,
              let snapshot = decode(information, applicationIdentifier: applicationIdentifier)
        else {
            return .unavailable
        }
        return .current(snapshot)
    }

    private func applicationIdentifier() async -> String? {
        guard let function = function(
            "MRMediaRemoteGetNowPlayingApplicationDisplayID",
            as: GetApplicationIdentifierFunction.self
        ) else {
            return nil
        }
        let result: MediaRemoteCallbackResult<String?> = await withCheckedContinuation { continuation in
            let gate = MediaRemoteCallbackGate(continuation)
            function(DispatchQueue.global(qos: .userInitiated)) { identifier in
                gate.resume(.value(identifier as String?))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.callbackTimeout) {
                gate.resume(.timedOut)
            }
        }
        guard case let .value(identifier) = result else { return nil }
        return identifier
    }

    private func readWithAdapter() async -> NowPlayingReadResult? {
        guard let scriptURL = Bundle.module.url(forResource: "now-playing-reader", withExtension: "pl"),
              let resourcesURL = Bundle.main.resourceURL
        else { return nil }
        let bridgeURL = resourcesURL.appendingPathComponent("libBarometerNowPlayingBridge.dylib")
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"),
              FileManager.default.fileExists(atPath: bridgeURL.path)
        else { return nil }

        let worker = Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, bridgeURL.path]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil as Data? }
            try? output.fileHandleForWriting.close()
            let descriptor = output.fileHandleForReading.fileDescriptor
            let currentFlags = fcntl(descriptor, F_GETFL)
            guard currentFlags >= 0, fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0 else {
                Self.terminateAndReap(process)
                return nil
            }
            var data = Data()
            var exceededLimit = false
            var reachedEnd = false
            var buffer = [UInt8](repeating: 0, count: 8_192)
            func drainAvailable() {
                while !reachedEnd && !exceededLimit {
                    let count = buffer.withUnsafeMutableBytes { bytes in
                        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                    }
                    if count > 0 {
                        guard data.count + count <= Self.maximumAdapterOutputBytes else {
                            exceededLimit = true
                            return
                        }
                        data.append(contentsOf: buffer.prefix(count))
                    } else if count == 0 {
                        reachedEnd = true
                    } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                        reachedEnd = true
                    } else {
                        return
                    }
                }
            }
            let deadline = Date().addingTimeInterval(Self.adapterTimeout)
            while process.isRunning, Date() < deadline, !Task.isCancelled, !exceededLimit {
                drainAvailable()
                usleep(10_000)
            }
            if process.isRunning { Self.terminateAndReap(process) }
            else { process.waitUntilExit() }
            drainAvailable()
            guard !Task.isCancelled, !exceededLimit, process.terminationStatus == 0 else { return nil }
            return data
        }
        let data = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard let data,
              let payload = try? JSONDecoder().decode(AdapterPayload.self, from: data)
        else { return nil }
        guard payload.available else { return .unavailable }
        if payload.idle { return .idle }
        guard let title = Self.trimmed(payload.title) else { return .unavailable }
        let duration = payload.duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let elapsed = payload.elapsedTime.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let artwork = payload.artworkData.flatMap { Data(base64Encoded: $0) }
        return .current(NowPlayingSnapshot(
            title: title,
            artist: Self.trimmed(payload.artist),
            album: Self.trimmed(payload.album),
            applicationBundleIdentifier: Self.trimmed(payload.bundleIdentifier),
            playbackState: payload.playing ? .playing : .paused,
            duration: duration,
            elapsedTime: elapsed.map { elapsedValue in
                duration.map { min(elapsedValue, $0) } ?? elapsedValue
            },
            artworkData: Self.boundedArtwork(artwork)
        ))
    }

    private nonisolated static func terminateAndReap(_ process: Process) {
        guard process.isRunning else { process.waitUntilExit(); return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.3)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let library else { return nil }
        return dlsym(library, name)
    }

    private func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = symbol(name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static func commandValue(_ command: NowPlayingCommand) -> Int {
        switch command {
        case .togglePlayPause: 2
        case .next: 4
        case .previous: 5
        }
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return trimmed(value)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func nonnegativeNumber(_ value: Any?) -> Double? {
        guard let number = number(value), number >= 0 else { return nil }
        return number
    }

    /// Rejects compressed payloads that could expand into an unbounded image in the popup.
    private static func boundedArtwork(_ data: Data?) -> Data? {
        guard let data,
              data.count <= maximumArtworkBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0,
              height.intValue > 0,
              width.intValue <= maximumArtworkDimension,
              height.intValue <= maximumArtworkDimension
        else {
            return nil
        }
        return data
    }
}

private struct AdapterPayload: Decodable, Sendable {
    let available: Bool
    let idle: Bool
    let title: String?
    let artist: String?
    let album: String?
    let bundleIdentifier: String?
    let playing: Bool
    let duration: Double?
    let elapsedTime: Double?
    let artworkData: String?

    private enum CodingKeys: String, CodingKey {
        case available, idle, title, artist, album, bundleIdentifier, playing, duration, elapsedTime, artworkData
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        available = try values.decodeIfPresent(Bool.self, forKey: .available) ?? false
        idle = try values.decodeIfPresent(Bool.self, forKey: .idle) ?? false
        title = try values.decodeIfPresent(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        playing = try values.decodeIfPresent(Bool.self, forKey: .playing) ?? false
        duration = try values.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try values.decodeIfPresent(Double.self, forKey: .elapsedTime)
        artworkData = try values.decodeIfPresent(String.self, forKey: .artworkData)
    }
}

private enum MediaRemoteCallbackResult<Value: Sendable>: Sendable {
    case value(Value)
    case timedOut
}

/// MediaRemote callbacks are not guaranteed to arrive. The lock protects the one continuation
/// shared by its callback and timeout, so this reference type is safe to pass to both queues.
private final class MediaRemoteCallbackGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
