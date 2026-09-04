import CSystemSources
import Foundation
import IOKit
import os

/// Metadata returned by AppleSMC for one four-character key.
public struct SMCKeyMetadata: Equatable, Sendable {
    public let dataSize: Int
    public let dataType: String
    public let attributes: UInt8
}

/// Raw bytes and decoded forms for one read-only SMC value.
public struct SMCValue: Equatable, Sendable {
    public let key: String
    public let metadata: SMCKeyMetadata
    public let bytes: [UInt8]

    /// Numeric representation for supported integer, floating-point, and fixed-point types.
    public var numericValue: Double? {
        SMCClient.decodeNumeric(bytes: bytes, dataType: metadata.dataType)
    }

    /// String representation for supported character and fan-description types.
    public var stringValue: String? {
        SMCClient.decodeString(bytes: bytes, dataType: metadata.dataType)
    }
}

/// Current read-only fan information discovered from the SMC key count.
public struct SMCFanReading: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let currentRPM: Double
    public let minimumRPM: Double?
    public let maximumRPM: Double?
}

/// Errors reported while opening or reading AppleSMC.
public enum SMCClientError: Error, Sendable {
    case serviceUnavailable
    case openFailed(kern_return_t)
    case invalidKey(String)
    case callFailed(key: String, command: UInt8, result: kern_return_t)
    case invalidResponseSize(key: String, command: UInt8, size: Int)
    case firmwareRejected(key: String, command: UInt8, result: UInt8)
    case invalidDataSize(key: String, size: Int)
    case keyCountUnavailable
}

/// Actor-isolated, read-only AppleSMC client with cached key metadata.
public actor SMCClient {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "sensors.smc")

    private let connection: io_connect_t
    private var metadataCache: [UInt32: SMCKeyMetadata] = [:]
    private var keyCache: [String]?
    private var sensorKeyCache: [String]?

    /// Opens the AppleSMC user client without requesting privileges.
    public init() throws {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCClientError.serviceUnavailable
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            throw SMCClientError.serviceUnavailable
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            Self.logger.error("Unable to open AppleSMC: \(result, privacy: .public)")
            throw SMCClientError.openFailed(result)
        }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    /// Whether AppleSMC can be opened by the current process.
    public nonisolated static var isAvailable: Bool {
        (try? SMCClient()) != nil
    }

    /// Reads one four-character key using only the SMC read commands.
    public func read(_ key: String) throws -> SMCValue {
        guard let code = Self.code(for: key) else {
            throw SMCClientError.invalidKey(key)
        }
        let metadata = try metadata(for: code, key: key)
        guard (0...32).contains(metadata.dataSize) else {
            throw SMCClientError.invalidDataSize(key: key, size: metadata.dataSize)
        }
        var input = MBSSMCKeyData()
        input.key = code
        input.keyInfo.dataSize = UInt32(metadata.dataSize)
        input.data8 = UInt8(MBS_SMC_COMMAND_READ_BYTES)
        let output = try call(input, key: key, command: input.data8)
        let bytes = withUnsafeBytes(of: output.bytes) { rawBuffer in
            Array(rawBuffer.prefix(metadata.dataSize))
        }
        return SMCValue(key: key, metadata: metadata, bytes: bytes)
    }

    /// Enumerates all SMC keys once and caches the result for the connection lifetime.
    public func allKeys() throws -> [String] {
        if let keyCache {
            return keyCache
        }
        guard let count = try read("#KEY").numericValue else {
            throw SMCClientError.keyCountUnavailable
        }
        let keyCount = min(max(0, Int(count)), 100_000)
        var keys: [String] = []
        keys.reserveCapacity(keyCount)
        for index in 0..<keyCount {
            var input = MBSSMCKeyData()
            input.data8 = UInt8(MBS_SMC_COMMAND_READ_INDEX)
            input.data32 = UInt32(index)
            guard let output = try? call(input, key: "index \(index)", command: input.data8) else {
                continue
            }
            let key = Self.key(from: output.key)
            if key.utf8.count == 4 {
                keys.append(key)
            }
        }
        keyCache = keys
        return keys
    }

    /// Discovers numeric temperature, power, current, and voltage keys that answer on this Mac.
    public func availableSensorKeys() throws -> [String] {
        if let sensorKeyCache {
            return sensorKeyCache
        }
        let candidates = try allKeys().filter { key in
            guard let prefix = key.first else {
                return false
            }
            return ["T", "P", "I", "V"].contains(prefix)
        }
        let available = candidates.filter { key in
            guard let value = try? read(key).numericValue else {
                return false
            }
            return value.isFinite
        }
        sensorKeyCache = available
        return available
    }

    /// Reads every runtime-curated numeric sensor key that remains available.
    public func sensorValues() throws -> [SMCValue] {
        try availableSensorKeys().compactMap { try? read($0) }
    }

    /// Reads all fans discovered through `FNum`; fanless Macs return an empty array.
    public func fans() throws -> [SMCFanReading] {
        guard let count = try? read("FNum").numericValue else {
            return []
        }
        return (0..<max(0, Int(count))).compactMap { id in
            guard let current = try? read("F\(id)Ac").numericValue,
                  current.isFinite,
                  current >= 0
            else {
                return nil
            }
            let identifier = (try? read("F\(id)ID").stringValue) ?? "Fan \(id + 1)"
            let minimum = try? read("F\(id)Mn").numericValue
            let maximum = try? read("F\(id)Mx").numericValue
            return SMCFanReading(
                id: id,
                name: identifier,
                currentRPM: current,
                minimumRPM: minimum,
                maximumRPM: maximum
            )
        }
    }

    static func decodeNumeric(bytes: [UInt8], dataType: String) -> Double? {
        let normalizedType = dataType.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        switch normalizedType {
        case "ui8":
            return bytes.first.map { Double($0) }
        case "ui16":
            return unsignedInteger(bytes: bytes, count: 2).map { Double($0) }
        case "ui32":
            return unsignedInteger(bytes: bytes, count: 4).map { Double($0) }
        case "si8":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "si16":
            guard let raw = unsignedInteger(bytes: bytes, count: 2) else {
                return nil
            }
            return Double(Int16(bitPattern: UInt16(raw)))
        case "si32":
            guard let raw = unsignedInteger(bytes: bytes, count: 4) else {
                return nil
            }
            return Double(Int32(bitPattern: UInt32(raw)))
        case "hex_":
            return unsignedInteger(bytes: bytes, count: min(4, bytes.count)).map { Double($0) }
        case "flt", "iof":
            guard bytes.count >= 4 else {
                return nil
            }
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ioft":
            guard bytes.count >= 8 else {
                return nil
            }
            let bits = bytes.prefix(8).enumerated().reduce(UInt64(0)) { partialResult, element in
                partialResult | UInt64(element.element) << UInt64(element.offset * 8)
            }
            return Double(Int64(bitPattern: bits)) / 65_536
        case "fpe2":
            guard let raw = unsignedInteger(bytes: bytes, count: 2) else {
                return nil
            }
            return Double(raw) / 4
        default:
            break
        }
        guard normalizedType.count == 4,
              let fractionCharacter = normalizedType.last,
              let fractionBits = Int(String(fractionCharacter), radix: 16),
              bytes.count >= 2
        else {
            return nil
        }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        if normalizedType.hasPrefix("sp") {
            return Double(Int16(bitPattern: raw)) / pow(2, Double(fractionBits))
        }
        if normalizedType.hasPrefix("fp") {
            return Double(raw) / pow(2, Double(fractionBits))
        }
        return nil
    }

    static func decodeString(bytes: [UInt8], dataType: String) -> String? {
        let payload: ArraySlice<UInt8>
        if dataType == "{fds" {
            guard bytes.count > 4 else {
                return nil
            }
            payload = bytes.dropFirst(4)
        } else if dataType.hasPrefix("ch8") {
            payload = bytes[...]
        } else {
            return nil
        }
        let content = payload.prefix { $0 != 0 }
        let string = String(decoding: content, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    static func code(for key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else {
            return nil
        }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    static func key(from code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    private func metadata(for code: UInt32, key: String) throws -> SMCKeyMetadata {
        if let cached = metadataCache[code] {
            return cached
        }
        var input = MBSSMCKeyData()
        input.key = code
        input.data8 = UInt8(MBS_SMC_COMMAND_READ_KEY_INFO)
        let output = try call(input, key: key, command: input.data8)
        let metadata = SMCKeyMetadata(
            dataSize: Int(output.keyInfo.dataSize),
            dataType: Self.key(from: output.keyInfo.dataType),
            attributes: output.keyInfo.dataAttributes
        )
        metadataCache[code] = metadata
        return metadata
    }

    private func call(_ originalInput: MBSSMCKeyData, key: String, command: UInt8) throws -> MBSSMCKeyData {
        var input = originalInput
        var output = MBSSMCKeyData()
        var outputSize = MemoryLayout<MBSSMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(MBS_SMC_SELECTOR),
            &input,
            MemoryLayout<MBSSMCKeyData>.stride,
            &output,
            &outputSize
        )
        guard result == KERN_SUCCESS else {
            throw SMCClientError.callFailed(key: key, command: command, result: result)
        }
        guard outputSize >= MemoryLayout<MBSSMCKeyData>.stride else {
            throw SMCClientError.invalidResponseSize(key: key, command: command, size: outputSize)
        }
        guard output.result == 0 else {
            throw SMCClientError.firmwareRejected(key: key, command: command, result: output.result)
        }
        return output
    }

    private static func unsignedInteger(bytes: [UInt8], count: Int) -> UInt64? {
        guard bytes.count >= count else {
            return nil
        }
        return bytes.prefix(count).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
