import Foundation
import IOKit
import IOKit.ps

/// Current charging state of the Mac's internal battery.
public enum BatteryChargeState: String, Equatable, Sendable {
    case charging
    case discharging
    case full
    case onAC
}

/// Details published by the connected power adapter.
public struct PowerAdapterSnapshot: Equatable, Sendable {
    public let name: String?
    public let description: String?
    public let watts: Double?
    public let isWireless: Bool?
}

/// One normalized internal-battery observation.
public struct BatterySnapshot: Equatable, Sendable {
    public let name: String
    public let chargePercent: Double
    public let state: BatteryChargeState
    public let isExternalConnected: Bool
    public let isCharging: Bool
    public let isFullyCharged: Bool
    public let timeRemainingMinutes: Int?
    public let healthPercent: Double?
    public let cycleCount: Int?
    public let temperatureCelsius: Double?
    public let voltageVolts: Double?
    public let amperageAmps: Double?
    public let wattageWatts: Double?
    public let condition: String?
    public let adapter: PowerAdapterSnapshot?
    public let isLowPowerModeEnabled: Bool
}

/// Failures surfaced while reading the internal battery.
public enum BatterySourceError: Error, Sendable {
    case unavailable
}

/// Merges the public IOPS summary with optional runtime AppleSmartBattery details.
public struct BatterySource: Sendable {
    /// Whether an internal battery is currently reported.
    public var isAvailable: Bool {
        summary() != nil
    }

    /// Creates a battery source.
    public init() {}

    /// Reads the internal battery and every available optional detail.
    public func read() throws -> BatterySnapshot {
        guard let summary = summary() else {
            throw BatterySourceError.unavailable
        }
        let detail = Self.properties(matching: "AppleSmartBattery") ?? [:]
        let pack = Self.properties(matching: "AppleSmartBatteryPack") ?? [:]
        let batteryData = Self.dictionary(detail["BatteryData"]) ?? [:]
        let packData = Self.dictionary(pack["BatteryData"]) ?? [:]

        let currentCapacity = Self.double(summary[Self.currentCapacityKey]) ?? 0
        let maximumCapacity = Self.double(summary[Self.maximumCapacityKey]) ?? 100
        let chargePercent = maximumCapacity > 0
            ? min(100, max(0, currentCapacity / maximumCapacity * 100))
            : min(100, max(0, currentCapacity))
        let isCharging = Self.bool(summary[Self.isChargingKey])
            ?? Self.bool(detail["IsCharging"])
            ?? false
        let isFullyCharged = Self.bool(summary[Self.isChargedKey])
            ?? Self.bool(detail["FullyCharged"])
            ?? false
        let isExternalConnected = Self.string(summary[Self.powerSourceStateKey]) == Self.acPowerValue
            || Self.bool(detail["ExternalConnected"]) == true
        let state: BatteryChargeState = if isCharging {
            .charging
        } else if isFullyCharged {
            .full
        } else if isExternalConnected {
            .onAC
        } else {
            .discharging
        }

        let timeRemainingMinutes: Int? = switch state {
        case .charging:
            Self.validMinutes(Self.double(summary[Self.timeToFullKey]))
                ?? Self.validMinutes(Self.double(batteryData["AvgTimeToFull"]))
        case .discharging:
            Self.validMinutes(Self.double(summary[Self.timeToEmptyKey]))
                ?? Self.validMinutes(Self.double(batteryData["AvgTimeToEmpty"]))
        case .full, .onAC:
            nil
        }
        let fullChargeCapacity = Self.double(batteryData["FullChargeCapacity"])
            ?? Self.double(packData["AppleRawMaxCapacity"])
            ?? Self.double(packData["FccComp1"])
        let designCapacity = Self.double(batteryData["DesignCapacity"])
            ?? Self.double(packData["DesignCapacity"])
        let voltageMillivolts = Self.double(detail["Voltage"])
            ?? Self.double(packData["Voltage"])
        let rawAmperage = Self.unsignedInteger(detail["InstantAmperage"])
            ?? Self.unsignedInteger(detail["Amperage"])
            ?? Self.unsignedInteger(packData["InstantAmperage"])
            ?? Self.unsignedInteger(packData["Amperage"])
        let amperageAmps = rawAmperage.map { Double(Self.signedMilliamps(raw: $0)) / 1_000 }
        let voltageVolts = voltageMillivolts.map { $0 / 1_000 }
        let adapter = Self.adapter(from: Self.dictionary(detail["AdapterDetails"]))

        return BatterySnapshot(
            name: Self.string(summary[Self.nameKey]) ?? "Internal Battery",
            chargePercent: chargePercent,
            state: state,
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            timeRemainingMinutes: timeRemainingMinutes,
            healthPercent: Self.healthPercent(
                fullChargeCapacity: fullChargeCapacity,
                designCapacity: designCapacity
            ),
            cycleCount: Self.integer(detail["CycleCount"]) ?? Self.integer(packData["CycleCount"]),
            temperatureCelsius: Self.celsius(
                raw: Self.double(packData["Temperature"]) ?? Self.double(detail["Temperature"])
            ),
            voltageVolts: voltageVolts,
            amperageAmps: amperageAmps,
            wattageWatts: voltageVolts.flatMap { voltage in amperageAmps.map { voltage * $0 } },
            condition: Self.string(summary[Self.healthKey]),
            adapter: adapter,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    static func signedMilliamps(raw: UInt64) -> Int64 {
        if raw > UInt64(Int64.max) {
            return Int64(bitPattern: raw)
        }
        if raw > UInt64(Int32.max), raw <= UInt64(UInt32.max) {
            return Int64(Int32(bitPattern: UInt32(raw)))
        }
        return Int64(raw)
    }

    static func celsius(raw: Double?) -> Double? {
        guard let raw, raw > 0 else {
            return nil
        }
        let value = raw >= 1_000 ? raw / 100 : raw
        return (-20...100).contains(value) ? value : nil
    }

    static func healthPercent(fullChargeCapacity: Double?, designCapacity: Double?) -> Double? {
        guard let fullChargeCapacity, let designCapacity, designCapacity > 0 else {
            return nil
        }
        let value = fullChargeCapacity / designCapacity * 100
        return value.isFinite && (0...150).contains(value) ? value : nil
    }

    private func summary() -> [String: Any]? {
        let information = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue()
                as? [String: Any]
            else {
                continue
            }
            if Self.string(description[Self.transportTypeKey]) == Self.internalTypeValue {
                return description
            }
        }
        return nil
    }

    private static func properties(matching className: String) -> [String: Any]? {
        guard let matching = IOServiceMatching(className) else {
            return nil
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, nil, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return values
    }

    private static func adapter(from values: [String: Any]?) -> PowerAdapterSnapshot? {
        guard let values else {
            return nil
        }
        return PowerAdapterSnapshot(
            name: string(values["Name"]),
            description: string(values["Description"]),
            watts: double(values["Watts"]),
            isWireless: bool(values["IsWireless"])
        )
    }

    private static func validMinutes(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0, value < 65_535 else {
            return nil
        }
        return Int(value.rounded())
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static let currentCapacityKey = kIOPSCurrentCapacityKey as String
    private static let maximumCapacityKey = kIOPSMaxCapacityKey as String
    private static let isChargingKey = kIOPSIsChargingKey as String
    private static let isChargedKey = kIOPSIsChargedKey as String
    private static let powerSourceStateKey = kIOPSPowerSourceStateKey as String
    private static let timeToEmptyKey = kIOPSTimeToEmptyKey as String
    private static let timeToFullKey = kIOPSTimeToFullChargeKey as String
    private static let healthKey = kIOPSBatteryHealthKey as String
    private static let nameKey = kIOPSNameKey as String
    private static let transportTypeKey = kIOPSTransportTypeKey as String
    private static let acPowerValue = kIOPSACPowerValue as String
    private static let internalTypeValue = kIOPSInternalType as String
}
