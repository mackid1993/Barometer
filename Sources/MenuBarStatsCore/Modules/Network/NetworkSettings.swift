import Foundation

/// Unit used to present network transfer rates.
public enum NetworkRateUnit: String, Codable, CaseIterable, Sendable {
    case bytes
    case bits
}

/// Scaling policy for menu bar and dropdown network graphs.
public enum NetworkGraphScale: String, Codable, CaseIterable, Sendable {
    case automatic
    case fixed
}

/// Persisted choices specific to the Network module.
public struct NetworkSettings: Codable, Equatable, Sendable {
    /// Preferred interface, or `nil` to follow the primary route.
    public var selectedInterfaceName: String?

    /// Unit used for transfer rates.
    public var rateUnit: NetworkRateUnit

    /// Number of fractional digits shown in live transfer rates.
    public var decimalPlaces: Int

    /// Whether the external public-address lookup is allowed.
    public var showsPublicIP: Bool

    /// Graph scaling policy.
    public var graphScale: NetworkGraphScale

    /// Fixed graph ceiling expressed in bytes per second.
    public var fixedGraphMaximumBytesPerSecond: Double

    /// Creates Network settings.
    public init(
        selectedInterfaceName: String? = nil,
        rateUnit: NetworkRateUnit = .bytes,
        decimalPlaces: Int = 1,
        showsPublicIP: Bool = false,
        graphScale: NetworkGraphScale = .automatic,
        fixedGraphMaximumBytesPerSecond: Double = 10_000_000
    ) {
        self.selectedInterfaceName = selectedInterfaceName
        self.rateUnit = rateUnit
        self.decimalPlaces = min(2, max(0, decimalPlaces))
        self.showsPublicIP = showsPublicIP
        self.graphScale = graphScale
        self.fixedGraphMaximumBytesPerSecond = fixedGraphMaximumBytesPerSecond
    }

    private enum CodingKeys: String, CodingKey {
        case selectedInterfaceName
        case rateUnit
        case decimalPlaces
        case showsPublicIP
        case graphScale
        case fixedGraphMaximumBytesPerSecond
    }

    /// Decodes settings while supplying the precision default for builds that predate it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedInterfaceName = try container.decodeIfPresent(String.self, forKey: .selectedInterfaceName)
        rateUnit = try container.decodeIfPresent(NetworkRateUnit.self, forKey: .rateUnit) ?? .bytes
        decimalPlaces = min(2, max(0, try container.decodeIfPresent(Int.self, forKey: .decimalPlaces) ?? 1))
        showsPublicIP = try container.decodeIfPresent(Bool.self, forKey: .showsPublicIP) ?? false
        graphScale = try container.decodeIfPresent(NetworkGraphScale.self, forKey: .graphScale) ?? .automatic
        fixedGraphMaximumBytesPerSecond = try container.decodeIfPresent(
            Double.self,
            forKey: .fixedGraphMaximumBytesPerSecond
        ) ?? 10_000_000
    }
}

/// Stable decimal formatting shared by the Network menu bar and dropdown.
public enum NetworkRateFormatter {
    /// Formats a bytes-per-second value with a full unit suffix.
    public static func string(bytesPerSecond: Double, unit: NetworkRateUnit, decimalPlaces: Int = 1) -> String {
        format(bytesPerSecond: bytesPerSecond, unit: unit, decimalPlaces: decimalPlaces, compact: false)
    }

    /// Formats a bytes-per-second value for compact menu bar presentation.
    public static func compactString(
        bytesPerSecond: Double,
        unit: NetworkRateUnit,
        decimalPlaces: Int = 1
    ) -> String {
        format(bytesPerSecond: bytesPerSecond, unit: unit, decimalPlaces: decimalPlaces, compact: true)
    }

    /// Returns the normal two-digit value reserved by the stable two-row renderer.
    public static func compactPlaceholder(unit: NetworkRateUnit, decimalPlaces: Int) -> String {
        let precision = min(2, max(0, decimalPlaces))
        let fraction = precision == 0 ? "" : "." + String(repeating: "9", count: precision)
        return "99\(fraction)\(unit == .bits ? "m" : "M")"
    }

    private static func format(
        bytesPerSecond: Double,
        unit: NetworkRateUnit,
        decimalPlaces: Int,
        compact: Bool
    ) -> String {
        let clampedBytes = max(0, bytesPerSecond)
        let value = unit == .bits ? clampedBytes * 8 : clampedBytes
        let suffixes = unit == .bits
            ? (compact ? ["b", "k", "m", "g", "t"] : ["b/s", "Kb/s", "Mb/s", "Gb/s", "Tb/s"])
            : (compact ? ["B", "K", "M", "G", "T"] : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"])
        let precision = min(2, max(0, decimalPlaces))
        let compactBoundary = 100 - 0.5 * pow(10, -Double(precision))
        let unitBoundary = compact ? compactBoundary : 1_000
        var scaled = value / 1_000
        var suffixIndex = 1
        while scaled >= unitBoundary, suffixIndex < suffixes.count - 1 {
            scaled /= 1_000
            suffixIndex += 1
        }
        let number = String(format: "%.*f", precision, scaled)
        return compact ? "\(number)\(suffixes[suffixIndex])" : "\(number) \(suffixes[suffixIndex])"
    }
}
