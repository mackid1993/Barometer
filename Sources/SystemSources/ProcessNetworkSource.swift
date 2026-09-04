import Foundation

/// Cumulative external-network counters reported for one process.
public struct ProcessNetworkCounter: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let fallbackName: String
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    /// Creates one cumulative process-network observation.
    public init(
        processIdentifier: pid_t,
        fallbackName: String,
        receivedBytes: UInt64,
        sentBytes: UInt64
    ) {
        self.processIdentifier = processIdentifier
        self.fallbackName = fallbackName
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

/// Failures surfaced while sampling macOS per-process network accounting.
public enum ProcessNetworkSourceError: Error, Sendable {
    case unavailable
    case launch(String)
    case failed(Int32, String)
}

/// Reads cumulative per-process byte counters from the system `nettop` utility.
///
/// `nettop` is part of macOS and reads the same kernel network accounting used by
/// Activity Monitor. Barometer requests one noninteractive CSV snapshot and never
/// bundles or installs a helper executable.
public struct ProcessNetworkSource: Sendable {
    private static let executablePath = "/usr/bin/nettop"

    /// Whether the macOS per-process network accounting utility is present.
    public var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: Self.executablePath)
    }

    /// Creates a per-process network source.
    public init() {}

    /// Reads one cumulative snapshot for external, non-loopback traffic.
    public func read() throws -> [ProcessNetworkCounter] {
        guard isAvailable else {
            throw ProcessNetworkSourceError.unavailable
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.executablePath)
        process.arguments = [
            "-P", "-L", "1", "-n", "-x",
            "-t", "external",
            "-J", "bytes_in,bytes_out",
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ProcessNetworkSourceError.launch(String(describing: error))
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessNetworkSourceError.failed(process.terminationStatus, message)
        }
        return Self.parse(String(decoding: output, as: UTF8.self))
    }

    static func parse(_ output: String) -> [ProcessNetworkCounter] {
        var counters: [pid_t: ProcessNetworkCounter] = [:]
        for line in output.split(whereSeparator: \Character.isNewline) {
            let fields = csvFields(String(line))
            guard fields.count >= 3,
                  let split = fields[0].lastIndex(of: "."),
                  let processIdentifier = pid_t(fields[0][fields[0].index(after: split)...]),
                  processIdentifier > 0,
                  let receivedBytes = UInt64(fields[1]),
                  let sentBytes = UInt64(fields[2])
            else {
                continue
            }
            let fallbackName = String(fields[0][..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = counters[processIdentifier]
            counters[processIdentifier] = ProcessNetworkCounter(
                processIdentifier: processIdentifier,
                fallbackName: fallbackName.isEmpty ? "PID \(processIdentifier)" : fallbackName,
                receivedBytes: (existing?.receivedBytes ?? 0) &+ receivedBytes,
                sentBytes: (existing?.sentBytes ?? 0) &+ sentBytes
            )
        }
        return counters.values.sorted { $0.processIdentifier < $1.processIdentifier }
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if isQuoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }
}
