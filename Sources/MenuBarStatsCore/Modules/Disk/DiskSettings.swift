import Foundation

/// Base used for disk capacities and transfer rates.
public enum DiskUnitSystem: String, Codable, CaseIterable, Sendable {
    case decimal
    case binary
}

/// Persisted choices specific to the Disk module.
public struct DiskSettings: Codable, Equatable, Sendable {
    /// Preferred volume, or `nil` to use the startup volume.
    public var selectedVolumeID: String?

    /// Whether implementation and recovery volumes are hidden from the dropdown and picker.
    public var hidesSystemVolumes: Bool

    /// Decimal SI or binary IEC capacity and rate units.
    public var unitSystem: DiskUnitSystem

    /// Stable volume identifiers explicitly hidden by the user.
    public var hiddenVolumeIDs: Set<String>

    /// Creates Disk settings.
    public init(
        selectedVolumeID: String? = nil,
        hidesSystemVolumes: Bool = true,
        unitSystem: DiskUnitSystem = .binary,
        hiddenVolumeIDs: Set<String> = []
    ) {
        self.selectedVolumeID = selectedVolumeID
        self.hidesSystemVolumes = hidesSystemVolumes
        self.unitSystem = unitSystem
        self.hiddenVolumeIDs = hiddenVolumeIDs
    }

    private enum CodingKeys: String, CodingKey {
        case selectedVolumeID
        case hidesSystemVolumes
        case unitSystem
        case hiddenVolumeIDs
    }

    /// Decodes settings while preserving defaults introduced after the first Disk build.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedVolumeID = try container.decodeIfPresent(String.self, forKey: .selectedVolumeID)
        hidesSystemVolumes = try container.decodeIfPresent(Bool.self, forKey: .hidesSystemVolumes) ?? true
        unitSystem = try container.decodeIfPresent(DiskUnitSystem.self, forKey: .unitSystem) ?? .binary
        hiddenVolumeIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenVolumeIDs) ?? []
    }
}

/// Stable disk capacity and transfer-rate formatting.
public enum DiskValueFormatter {
    /// Formats bytes as a capacity.
    public static func capacity(_ bytes: UInt64, unitSystem: DiskUnitSystem, compact: Bool = false) -> String {
        format(Double(bytes), unitSystem: unitSystem, compact: compact, rate: false)
    }

    /// Formats bytes per second as a transfer rate.
    public static func rate(_ bytesPerSecond: Double, unitSystem: DiskUnitSystem, compact: Bool = false) -> String {
        format(max(0, bytesPerSecond), unitSystem: unitSystem, compact: compact, rate: true)
    }

    private static func format(
        _ rawValue: Double,
        unitSystem: DiskUnitSystem,
        compact: Bool,
        rate: Bool
    ) -> String {
        let divisor = unitSystem == .decimal ? 1_000.0 : 1_024.0
        let suffixes = unitSystem == .decimal
            ? ["B", "KB", "MB", "GB", "TB"]
            : ["B", "KiB", "MiB", "GiB", "TiB"]
        var value = rawValue
        var suffixIndex = 0
        while value >= divisor, suffixIndex < suffixes.count - 1 {
            value /= divisor
            suffixIndex += 1
        }
        let precision = value < 10 && suffixIndex > 0 ? 1 : 0
        let number = String(format: "%.*f", precision, value)
        let separator = compact ? "" : " "
        return "\(number)\(separator)\(suffixes[suffixIndex])\(rate ? "/s" : "")"
    }
}

public extension DiskSample {
    /// Volumes appropriate for user-facing presentation under the supplied settings.
    func visibleVolumes(settings: DiskSettings) -> [DiskVolumeSample] {
        volumes.filter { volume in
            guard volume.totalBytes > 0 else {
                return false
            }
            if settings.hidesSystemVolumes {
                guard volume.mountPoint == "/" || !volume.mountPoint.hasPrefix("/System/Volumes/") else {
                    return false
                }
            }
            return !settings.hiddenVolumeIDs.contains(volume.id)
        }
    }

    /// Resolves the selected volume, falling back to the startup volume and then the first visible volume.
    func selectedVolume(settings: DiskSettings) -> DiskVolumeSample? {
        let visible = visibleVolumes(settings: settings)
        return settings.selectedVolumeID.flatMap { id in visible.first { $0.id == id } }
            ?? visible.first { $0.mountPoint == "/" }
            ?? visible.first
    }
}
