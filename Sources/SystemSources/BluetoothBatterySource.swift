import Foundation
import IOKit

/// Named component of a Bluetooth device battery.
public enum BluetoothBatteryComponent: String, Equatable, Sendable {
    case device = "Device"
    case left = "Left"
    case right = "Right"
    case `case` = "Case"
}

/// One component-level Bluetooth charge reading.
public struct BluetoothBatteryLevel: Equatable, Sendable {
    public let component: BluetoothBatteryComponent
    public let percent: Int

    /// Creates a validated component level.
    public init(component: BluetoothBatteryComponent, percent: Int) {
        self.component = component
        self.percent = percent
    }
}

/// Battery levels for one runtime-discovered Bluetooth or wireless HID device.
public struct BluetoothBatterySnapshot: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let levels: [BluetoothBatteryLevel]

    /// Creates a device battery snapshot.
    public init(id: String, name: String, levels: [BluetoothBatteryLevel]) {
        self.id = id
        self.name = name
        self.levels = levels
    }
}

/// Discovers connected device batteries from generic IORegistry battery keys.
public struct BluetoothBatterySource: Sendable {
    /// Whether the system publishes at least one supported device service class.
    public var isAvailable: Bool {
        Self.serviceClasses.contains { IOServiceMatching($0) != nil }
    }

    /// Creates a Bluetooth battery source.
    public init() {}

    /// Reads every currently published device battery without a hardware identifier table.
    public func read() -> [BluetoothBatterySnapshot] {
        var byIdentifier: [String: BluetoothBatterySnapshot] = [:]
        for className in Self.serviceClasses {
            for (properties, identifier) in Self.properties(matching: className) {
                guard let value = Self.snapshot(
                    properties: properties,
                    registryIdentifier: identifier
                ) else {
                    continue
                }
                if value.levels.count > (byIdentifier[value.id]?.levels.count ?? 0) {
                    byIdentifier[value.id] = value
                }
            }
        }
        return byIdentifier.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func snapshot(
        properties: [String: Any],
        registryIdentifier: UInt64
    ) -> BluetoothBatterySnapshot? {
        let name = string(properties, keys: ["Product", "ProductName", "DeviceName", "Name"])
            ?? "Bluetooth Device"
        let identifier = string(properties, keys: ["DeviceAddress", "SerialNumber"])
            ?? String(registryIdentifier)
        var levels: [BluetoothBatteryLevel] = []
        if let value = percent(properties, keys: ["BatteryPercent", "BatteryPercentSingle", "BatteryLevel"]) {
            levels.append(BluetoothBatteryLevel(component: .device, percent: value))
        }
        if let value = percent(properties, keys: ["BatteryPercentLeft"]) {
            levels.append(BluetoothBatteryLevel(component: .left, percent: value))
        }
        if let value = percent(properties, keys: ["BatteryPercentRight"]) {
            levels.append(BluetoothBatteryLevel(component: .right, percent: value))
        }
        if let value = percent(properties, keys: ["BatteryPercentCase"]) {
            levels.append(BluetoothBatteryLevel(component: .case, percent: value))
        }
        guard !levels.isEmpty else { return nil }
        return BluetoothBatterySnapshot(id: identifier, name: name, levels: levels)
    }

    private static func properties(matching className: String) -> [([String: Any], UInt64)] {
        guard let matching = IOServiceMatching(className) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [([String: Any], UInt64)] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var unmanagedProperties: Unmanaged<CFMutableDictionary>?
            var identifier: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS,
                  IORegistryEntryCreateCFProperties(service, &unmanagedProperties, nil, 0) == KERN_SUCCESS,
                  let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
            else {
                continue
            }
            result.append((properties, identifier))
        }
        return result
    }

    private static func string(_ values: [String: Any], keys: [String]) -> String? {
        keys.lazy.compactMap { values[$0] as? String }.first
    }

    private static func percent(_ values: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = (values[key] as? NSNumber)?.intValue else { continue }
            if (0...100).contains(value) { return value }
        }
        return nil
    }

    private static let serviceClasses = [
        "AppleDeviceManagementHIDEventService",
        "IOBluetoothDevice",
    ]
}
