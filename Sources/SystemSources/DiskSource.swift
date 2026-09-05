import Darwin
import Foundation
import IOKit

/// Broad attachment class for a mounted volume.
public enum DiskVolumeKind: String, Equatable, Sendable {
    case internalDisk
    case externalDisk
    case network
}

/// Capacity, identity, and ejectability for one mounted volume.
public struct DiskVolumeSnapshot: Equatable, Sendable {
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
}

/// Cumulative I/O counters for one physical block-storage driver.
public struct DiskDeviceSnapshot: Equatable, Sendable {
    public let bsdName: String
    public let model: String?
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let readOperations: UInt64
    public let writeOperations: UInt64
    public let readErrors: UInt64
    public let writeErrors: UInt64
}

/// Mounted volumes and physical storage counters sampled at one instant.
public struct SystemDiskSnapshot: Equatable, Sendable {
    public let volumes: [DiskVolumeSnapshot]
    public let devices: [DiskDeviceSnapshot]
}

/// Failures surfaced while enumerating physical storage drivers.
public enum DiskSourceError: Error, Sendable {
    case matchingServices(kern_return_t)
}

/// Reads mounted-volume capacity and IOBlockStorageDriver statistics without writing to any disk.
public struct DiskSource: Sendable {
    /// Whether at least one mounted volume or block-storage driver is available.
    public var isAvailable: Bool {
        (try? read()).map { !$0.volumes.isEmpty || !$0.devices.isEmpty } ?? false
    }

    /// Creates a disk source.
    public init() {}

    /// Reads all currently mounted volumes and physical storage counters.
    public func read() throws -> SystemDiskSnapshot {
        let devices = try physicalDevices()
        let volumes = mountedVolumes()
        return SystemDiskSnapshot(volumes: volumes, devices: devices)
    }

    private func mountedVolumes() -> [DiskVolumeSnapshot] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeIsReadOnlyKey,
            .volumeUUIDStringKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else {
                return nil
            }
            let totalBytes = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let availableBytes = min(totalBytes, UInt64(max(0, values.volumeAvailableCapacity ?? 0)))
            let mountSource = Self.mountSource(for: url.path)
            let bsdName = mountSource.flatMap(Self.bsdName(fromMountSource:))
            return DiskVolumeSnapshot(
                id: values.volumeUUIDString ?? url.standardizedFileURL.path,
                name: values.volumeName ?? url.lastPathComponent,
                mountPoint: url.standardizedFileURL.path,
                bsdName: bsdName,
                physicalBSDName: bsdName.flatMap(Self.physicalBSDName(for:)),
                totalBytes: totalBytes,
                usedBytes: totalBytes - availableBytes,
                availableBytes: availableBytes,
                kind: Self.volumeKind(isLocal: values.volumeIsLocal, isInternal: values.volumeIsInternal),
                isEjectable: values.volumeIsEjectable ?? false,
                isRemovable: values.volumeIsRemovable ?? false,
                isReadOnly: values.volumeIsReadOnly ?? false
            )
        }
        .sorted { left, right in
            if left.mountPoint == "/" {
                return true
            }
            if right.mountPoint == "/" {
                return false
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func physicalDevices() throws -> [DiskDeviceSnapshot] {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return []
        }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            throw DiskSourceError.matchingServices(result)
        }
        defer { IOObjectRelease(iterator) }

        var devices: [DiskDeviceSnapshot] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let snapshot = Self.deviceSnapshot(service: service) {
                devices.append(snapshot)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return devices.sorted(using: KeyPathComparator(\.bsdName, comparator: .localizedStandard))
    }

    private static func deviceSnapshot(service: io_registry_entry_t) -> DiskDeviceSnapshot? {
        guard let bsdName = stringProperty(
            service: service,
            key: "BSD Name",
            options: IOOptionBits(kIORegistryIterateRecursively)
        ),
        let statistics = dictionaryProperty(service: service, key: "Statistics")
        else {
            return nil
        }
        let parentOptions = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let characteristics = dictionarySearchProperty(
            service: service,
            key: "Device Characteristics",
            options: parentOptions
        )
        let model = characteristics?["Product Name"] as? String
            ?? stringProperty(service: service, key: "Model", options: parentOptions)
            ?? stringProperty(service: service, key: "Product Name", options: parentOptions)
        return DiskDeviceSnapshot(
            bsdName: bsdName,
            model: model?.trimmingCharacters(in: .whitespacesAndNewlines),
            bytesRead: number(statistics, key: "Bytes (Read)"),
            bytesWritten: number(statistics, key: "Bytes (Write)"),
            readOperations: number(statistics, key: "Operations (Read)"),
            writeOperations: number(statistics, key: "Operations (Write)"),
            readErrors: number(statistics, key: "Errors (Read)"),
            writeErrors: number(statistics, key: "Errors (Write)")
        )
    }

    private static func physicalBSDName(for bsdName: String) -> String? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else {
            return nil
        }
        var current = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard current != 0 else {
            return nil
        }

        while current != 0 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                IOObjectRelease(current)
                break
            }
            IOObjectRelease(current)
            if IOObjectConformsTo(parent, "IOBlockStorageDriver") != 0 {
                defer { IOObjectRelease(parent) }
                return stringProperty(
                    service: parent,
                    key: "BSD Name",
                    options: IOOptionBits(kIORegistryIterateRecursively)
                )
            }
            current = parent
        }
        return nil
    }

    static func volumeKind(isLocal: Bool?, isInternal: Bool?) -> DiskVolumeKind {
        if isLocal == false {
            return .network
        }
        return isInternal == true ? .internalDisk : .externalDisk
    }

    static func bsdName(fromMountSource source: String) -> String? {
        guard source.hasPrefix("/dev/disk") else {
            return nil
        }
        return String(source.dropFirst("/dev/".count))
    }

    private static func mountSource(for path: String) -> String? {
        var fileSystem = statfs()
        guard path.withCString({ statfs($0, &fileSystem) }) == 0 else {
            return nil
        }
        return withUnsafePointer(to: &fileSystem.f_mntfromname) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
    }

    private static func dictionaryProperty(service: io_registry_entry_t, key: String) -> [String: Any]? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, nil, 0) else {
            return nil
        }
        return property.takeRetainedValue() as? [String: Any]
    }

    private static func stringProperty(
        service: io_registry_entry_t,
        key: String,
        options: IOOptionBits
    ) -> String? {
        guard let property = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            nil,
            options
        ) else {
            return nil
        }
        return property as? String
    }

    private static func dictionarySearchProperty(
        service: io_registry_entry_t,
        key: String,
        options: IOOptionBits
    ) -> [String: Any]? {
        guard let property = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            nil,
            options
        ) else {
            return nil
        }
        return property as? [String: Any]
    }

    private static func number(_ dictionary: [String: Any], key: String) -> UInt64 {
        (dictionary[key] as? NSNumber)?.uint64Value ?? 0
    }
}
