import Foundation

/// Durable scalar history retained across normal Barometer restarts and application updates.
public struct GraphHistoryArchive: Codable, Sendable {
    /// CPU utilization samples in chronological order.
    public let cpu: [HistoryEntry<CPUHistoryValue>]

    /// GPU utilization samples in chronological order.
    public let gpu: [HistoryEntry<GPUHistoryValue>]

    /// Creates a graph history archive.
    public init(cpu: [HistoryEntry<CPUHistoryValue>], gpu: [HistoryEntry<GPUHistoryValue>]) {
        self.cpu = cpu
        self.gpu = gpu
    }
}

/// Loads and atomically saves the rolling graph history file.
public enum GraphHistoryPersistence {
    /// Default history location in the user's Application Support directory.
    public static func defaultURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Barometer", isDirectory: true)
            .appendingPathComponent("graph-history.plist", isDirectory: false)
    }

    /// Loads a previously saved archive.
    public static func load(from url: URL) throws -> GraphHistoryArchive {
        try PropertyListDecoder().decode(GraphHistoryArchive.self, from: Data(contentsOf: url))
    }

    /// Atomically saves an archive, creating its private application directory when needed.
    public static func save(_ archive: GraphHistoryArchive, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(archive).write(to: url, options: .atomic)
    }
}
