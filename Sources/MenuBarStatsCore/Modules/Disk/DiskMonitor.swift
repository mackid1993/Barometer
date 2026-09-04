import Foundation
import SystemSources

/// Mounted-volume capacity normalized for the Disk module.
public struct DiskVolumeSample: Equatable, Sendable {
    public let id: String
    public let name: String
    public let mountPoint: String
    public let bsdName: String?
    public let physicalBSDName: String?
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64
    public let kind: DiskVolumeKind
    public let isEjectable: Bool
    public let isRemovable: Bool
    public let isReadOnly: Bool

    /// Creates one normalized mounted-volume sample.
    public init(
        id: String,
        name: String,
        mountPoint: String,
        bsdName: String?,
        physicalBSDName: String?,
        totalBytes: UInt64,
        usedBytes: UInt64,
        availableBytes: UInt64,
        kind: DiskVolumeKind,
        isEjectable: Bool,
        isRemovable: Bool,
        isReadOnly: Bool
    ) {
        self.id = id
        self.name = name
        self.mountPoint = mountPoint
        self.bsdName = bsdName
        self.physicalBSDName = physicalBSDName
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.kind = kind
        self.isEjectable = isEjectable
        self.isRemovable = isRemovable
        self.isReadOnly = isReadOnly
    }

    /// Percentage of total capacity currently in use.
    public var usedPercent: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0
    }
}

/// Current rates and lifetime counters for one physical disk.
public struct DiskDeviceSample: Equatable, Sendable {
    public let bsdName: String
    public let model: String?
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double
    public let readOperationsPerSecond: Double
    public let writeOperationsPerSecond: Double
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let readOperations: UInt64
    public let writeOperations: UInt64
    public let readErrors: UInt64
    public let writeErrors: UInt64

    /// Creates one physical-disk rate and counter sample.
    public init(
        bsdName: String,
        model: String?,
        readBytesPerSecond: Double,
        writeBytesPerSecond: Double,
        readOperationsPerSecond: Double,
        writeOperationsPerSecond: Double,
        bytesRead: UInt64,
        bytesWritten: UInt64,
        readOperations: UInt64,
        writeOperations: UInt64,
        readErrors: UInt64,
        writeErrors: UInt64
    ) {
        self.bsdName = bsdName
        self.model = model
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.readOperationsPerSecond = readOperationsPerSecond
        self.writeOperationsPerSecond = writeOperationsPerSecond
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.readOperations = readOperations
        self.writeOperations = writeOperations
        self.readErrors = readErrors
        self.writeErrors = writeErrors
    }
}

/// Mounted volumes and physical disk activity sampled together.
public struct DiskSample: Equatable, Sendable {
    public let timestamp: Date
    public let volumes: [DiskVolumeSample]
    public let devices: [DiskDeviceSample]

    /// Creates a complete Disk sample.
    public init(timestamp: Date, volumes: [DiskVolumeSample], devices: [DiskDeviceSample]) {
        self.timestamp = timestamp
        self.volumes = volumes
        self.devices = devices
    }
}

/// Converts cumulative block-driver statistics into live disk throughput and operation rates.
public actor DiskMonitor: Monitor {
    public nonisolated let interval: Duration

    private let source: DiskSource
    private var previousCounters: [String: PreviousDiskCounter] = [:]

    /// Whether mounted volumes or block-driver statistics are available.
    public var isAvailable: Bool {
        source.isAvailable
    }

    /// Creates a disk monitor.
    public init(interval: Duration = .seconds(1), source: DiskSource = DiskSource()) {
        self.interval = interval
        self.source = source
    }

    /// Reads capacities and calculates rates since the previous sample.
    public func sample() async throws -> DiskSample {
        let timestamp = Date()
        let snapshot = try source.read()
        let volumes = snapshot.volumes.map { volume in
            DiskVolumeSample(
                id: volume.id,
                name: volume.name,
                mountPoint: volume.mountPoint,
                bsdName: volume.bsdName,
                physicalBSDName: volume.physicalBSDName,
                totalBytes: volume.totalBytes,
                usedBytes: volume.usedBytes,
                availableBytes: volume.availableBytes,
                kind: volume.kind,
                isEjectable: volume.isEjectable,
                isRemovable: volume.isRemovable,
                isReadOnly: volume.isReadOnly
            )
        }
        var nextCounters: [String: PreviousDiskCounter] = [:]
        let devices = snapshot.devices.map { device in
            let previous = previousCounters[device.bsdName]
            let elapsed = previous.map { timestamp.timeIntervalSince($0.timestamp) } ?? 0
            let divisor = max(0, elapsed)
            nextCounters[device.bsdName] = PreviousDiskCounter(
                timestamp: timestamp,
                bytesRead: device.bytesRead,
                bytesWritten: device.bytesWritten,
                readOperations: device.readOperations,
                writeOperations: device.writeOperations
            )
            return DiskDeviceSample(
                bsdName: device.bsdName,
                model: device.model,
                readBytesPerSecond: Self.rate(from: previous?.bytesRead, to: device.bytesRead, elapsed: divisor),
                writeBytesPerSecond: Self.rate(
                    from: previous?.bytesWritten,
                    to: device.bytesWritten,
                    elapsed: divisor
                ),
                readOperationsPerSecond: Self.rate(
                    from: previous?.readOperations,
                    to: device.readOperations,
                    elapsed: divisor
                ),
                writeOperationsPerSecond: Self.rate(
                    from: previous?.writeOperations,
                    to: device.writeOperations,
                    elapsed: divisor
                ),
                bytesRead: device.bytesRead,
                bytesWritten: device.bytesWritten,
                readOperations: device.readOperations,
                writeOperations: device.writeOperations,
                readErrors: device.readErrors,
                writeErrors: device.writeErrors
            )
        }
        previousCounters = nextCounters
        return DiskSample(timestamp: timestamp, volumes: volumes, devices: devices)
    }

    static func rate(from previous: UInt64?, to current: UInt64, elapsed: TimeInterval) -> Double {
        guard let previous, current >= previous, elapsed > 0 else {
            return 0
        }
        return Double(current - previous) / elapsed
    }
}

private struct PreviousDiskCounter {
    let timestamp: Date
    let bytesRead: UInt64
    let bytesWritten: UInt64
    let readOperations: UInt64
    let writeOperations: UInt64
}
