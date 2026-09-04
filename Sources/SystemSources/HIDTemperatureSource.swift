import CSystemSources
import Foundation

/// One filtered and deduplicated IOHID temperature reading.
public struct HIDTemperatureReading: Equatable, Sendable {
    public let rawName: String
    public let name: String
    public let celsius: Double
    public let sampleCount: Int
}

/// Failures surfaced while constructing the HID sensor client.
public enum HIDTemperatureSourceError: Error, Sendable {
    case clientUnavailable
    case servicesUnavailable
}

/// Reads Apple Silicon temperature events while reusing one HID client and matched service list.
public actor HIDTemperatureSource {
    private struct Service {
        let reference: IOHIDServiceClient
        let rawName: String
    }

    private var client: IOHIDEventSystemClient?
    private var services: [Service] = []

    /// Creates an uninitialized source. The HID client is created on the first read.
    public init() {}

    /// Whether at least one valid temperature reading is currently available.
    public var isAvailable: Bool {
        get async {
            (try? read()).map { !$0.isEmpty } ?? false
        }
    }

    /// Reads, filters, averages duplicate service names, and returns friendly labels.
    public func read() throws -> [HIDTemperatureReading] {
        try prepareServicesIfNeeded()
        var grouped: [String: [Double]] = [:]
        for service in services {
            guard let event = IOHIDServiceClientCopyEvent(
                service.reference,
                Int64(MBS_IOHID_EVENT_TYPE_TEMPERATURE),
                0,
                0
            ) else {
                continue
            }
            defer { mbs_iohid_event_release(event) }
            let value = IOHIDEventGetFloatValue(
                event,
                mbs_iohid_event_field_base(Int64(MBS_IOHID_EVENT_TYPE_TEMPERATURE))
            )
            guard value.isFinite, value > 0, value <= 125 else {
                continue
            }
            grouped[service.rawName, default: []].append(value)
        }
        return Self.readings(from: grouped)
    }

    static func readings(from grouped: [String: [Double]]) -> [HIDTemperatureReading] {
        grouped.compactMap { rawName, unfilteredValues in
            let values = unfilteredValues.filter { $0.isFinite && $0 > 0 && $0 <= 125 }
            guard !values.isEmpty else {
                return nil
            }
            return HIDTemperatureReading(
                rawName: rawName,
                name: Self.friendlyName(rawName),
                celsius: values.reduce(0, +) / Double(values.count),
                sampleCount: values.count
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Drops the cached services so the next read discovers the current hardware set.
    public func refreshServices() {
        services = []
        client = nil
    }

    static func friendlyName(_ rawName: String) -> String {
        if rawName == "gas gauge battery" {
            return "Battery"
        }
        if rawName == "NAND CH0 temp" {
            return "SSD"
        }
        if rawName == "PMU tcal" {
            return "PMU"
        }
        if rawName.hasPrefix("PMU tdie"), let number = Int(rawName.dropFirst("PMU tdie".count)) {
            return "SoC die \(number)"
        }
        return rawName
    }

    private func prepareServicesIfNeeded() throws {
        guard services.isEmpty else {
            return
        }
        guard let unmanagedClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            throw HIDTemperatureSourceError.clientUnavailable
        }
        let client = unmanagedClient.takeRetainedValue()
        self.client = client
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 0x0005,
        ]
        _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        guard let references = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            throw HIDTemperatureSourceError.servicesUnavailable
        }
        services = references.compactMap { reference in
            guard let property = IOHIDServiceClientCopyProperty(reference, "Product" as CFString),
                  let name = property as? String else {
                return nil
            }
            return Service(reference: reference, rawName: name)
        }
    }
}
