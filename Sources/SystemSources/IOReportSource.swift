import CSystemSources
import Foundation
import IOKit

/// One normalized IOReport energy reading.
public struct IOReportPowerReading: Equatable, Sendable {
    public let name: String
    public let watts: Double
}

/// One current temperature gauge reported by an IOReport channel.
public struct IOReportTemperatureReading: Equatable, Sendable {
    public let name: String
    public let celsius: Double
}

/// One unaggregated energy channel retained for diagnostics across hardware generations.
public struct IOReportEnergyReading: Equatable, Sendable {
    public let group: String
    public let subgroup: String
    public let channel: String
    public let unit: String
    public let energy: Double
    public let watts: Double?
}

/// One residency-weighted processor frequency reading.
public struct IOReportFrequencyReading: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case lowerCPU
        case middleCPU
        case upperCPU
        case gpu
        case unknown
    }

    public let name: String
    public let kind: Kind
    public let averageMHz: Double?
    public let activePercent: Double
    public let states: [IOReportStateReading]
}

/// One raw residency state retained for diagnostics and future hardware compatibility.
public struct IOReportStateReading: Equatable, Sendable {
    public let name: String
    public let residency: Int64
}

/// Energy and performance-state deltas collected over one measured interval.
public struct IOReportSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let elapsedSeconds: Double
    public let energy: [IOReportEnergyReading]
    public let power: [IOReportPowerReading]
    public let frequencies: [IOReportFrequencyReading]
    public let temperatures: [IOReportTemperatureReading]
}

/// Failures exposed by the private IOReport data source.
public enum IOReportSourceError: Error, Sendable {
    case channelsUnavailable
    case subscriptionUnavailable
    case sampleUnavailable
    case sampleContentsUnavailable
}

/// Samples energy and performance-state residency from runtime-discovered IOReport channels.
public actor IOReportSource {
    private struct EnergyChannelKey: Hashable {
        let group: String
        let subgroup: String
        let channel: String
        let unit: String
    }

    // The actor exclusively owns these immutable Core Foundation and C handles.
    // They are only sampled while actor-isolated and released once during deinit.
    private struct Subscription: @unchecked Sendable {
        let channels: CFMutableDictionary
        let reference: MBSIOReportSubscriptionRef
    }

    private let subscriptions: [Subscription]
    private let frequencyTables: [[Double]]

    /// Creates and caches one subscription for the groups used by Barometer.
    public init() throws {
        let groups: [(String, String?)] = [
            ("Energy Model", nil),
            ("PMP", "Energy Counters"),
            ("CPU Stats", nil),
            ("GPU Stats", nil),
        ]
        subscriptions = groups.compactMap { group, subgroup in
            try? Self.makeSubscription(group: group, subgroup: subgroup)
        }
        guard !subscriptions.isEmpty else {
            throw IOReportSourceError.channelsUnavailable
        }
        frequencyTables = Self.readFrequencyTables()
    }

    deinit {
        for subscription in subscriptions {
            mbs_ioreport_subscription_release(subscription.reference)
        }
    }

    /// Whether the required IOReport groups and a subscription can be created.
    public nonisolated static var isAvailable: Bool {
        (try? IOReportSource()) != nil
    }

    /// Collects one complete delta using the actual monotonic elapsed duration.
    public func sample(over interval: Duration = .seconds(1)) async throws -> IOReportSnapshot {
        let clock = ContinuousClock()
        let first = try makeSamples()
        let started = clock.now
        try await clock.sleep(for: interval)
        let second = try makeSamples()
        let ended = clock.now
        let deltas = try zip(first, second).map { previous, current in
            guard let delta = mbs_ioreport_create_samples_delta(previous, current)?.takeRetainedValue() else {
                throw IOReportSourceError.sampleUnavailable
            }
            return delta
        }
        let elapsedSeconds = Self.seconds(from: started.duration(to: ended))
        return try Self.decode(
            deltas,
            currentSamples: second,
            energy: Self.energyChannels(from: deltas),
            elapsedSeconds: elapsedSeconds,
            frequencyTables: frequencyTables,
            timestamp: Date()
        )
    }

    /// Runtime-discovered frequency tables, exposed for the diagnostic probe.
    public func availableFrequencyTables() -> [[Double]] {
        frequencyTables
    }

    static func watts(energy: Double, unit: String, elapsedSeconds: Double) -> Double? {
        guard elapsedSeconds > 0 else {
            return nil
        }
        let joules: Double
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "J": joules = energy
        case "mJ": joules = energy / 1_000
        case "uJ", "µJ": joules = energy / 1_000_000
        case "nJ": joules = energy / 1_000_000_000
        default: return nil
        }
        return joules / elapsedSeconds
    }

    static func frequency(
        states: [IOReportStateReading],
        candidates: [[Double]],
        kind: IOReportFrequencyReading.Kind
    ) -> (averageMHz: Double?, activePercent: Double) {
        let activeStates = states.filter { !Self.isIdleState($0.name) }
        let total = states.reduce(0.0) { $0 + Double(max(0, $1.residency)) }
        let active = activeStates.reduce(0.0) { $0 + Double(max(0, $1.residency)) }
        let activePercent = total > 0 ? active / total * 100 : 0
        guard active > 0,
              let table = Self.frequencyTable(
                  stateCount: activeStates.count,
                  candidates: candidates,
                  kind: kind
              )
        else {
            return (nil, activePercent)
        }
        let weighted = zip(activeStates, table).reduce(0.0) { partial, pair in
            partial + Double(max(0, pair.0.residency)) * pair.1
        }
        return (weighted / active, activePercent)
    }

    static func normalizedFrequencyTable(data: Data) -> [Double]? {
        guard data.count >= 8, data.count.isMultiple(of: 8) else {
            return nil
        }
        var frequencies: [Double] = []
        for offset in stride(from: 0, to: data.count, by: 8) {
            let raw = data[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { partial, byte in
                partial | UInt32(byte.element) << UInt32(byte.offset * 8)
            }
            guard raw > 0 else {
                continue
            }
            let value = Double(raw)
            let megahertz: Double
            if value >= 100_000_000 {
                megahertz = value / 1_000_000
            } else if value >= 100_000 {
                megahertz = value / 1_000
            } else {
                megahertz = value
            }
            if (100...10_000).contains(megahertz) {
                frequencies.append(megahertz)
            }
        }
        return frequencies.isEmpty ? nil : frequencies
    }

    private static func makeSubscription(group: String, subgroup: String?) throws -> Subscription {
        guard let copied = mbs_ioreport_copy_channels_in_group(
            group as CFString,
            subgroup as CFString?
        )?.takeRetainedValue(),
              let channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, copied),
              let dictionary = channels as? [String: Any],
              dictionary["IOReportChannels"] != nil
        else {
            throw IOReportSourceError.channelsUnavailable
        }
        var subscribedChannels: Unmanaged<CFMutableDictionary>?
        guard let reference = mbs_ioreport_create_subscription(channels, &subscribedChannels) else {
            throw IOReportSourceError.subscriptionUnavailable
        }
        guard let subscribed = subscribedChannels?.takeRetainedValue() else {
            mbs_ioreport_subscription_release(reference)
            throw IOReportSourceError.subscriptionUnavailable
        }
        return Subscription(channels: subscribed, reference: reference)
    }

    private func makeSamples() throws -> [CFDictionary] {
        try subscriptions.map { subscription in
            guard let sample = mbs_ioreport_create_samples(
                subscription.reference,
                subscription.channels
            )?.takeRetainedValue() else {
                throw IOReportSourceError.sampleUnavailable
            }
            return sample
        }
    }

    private static func decode(
        _ samples: [CFDictionary],
        currentSamples: [CFDictionary],
        energy: [(key: EnergyChannelKey, value: Double)],
        elapsedSeconds: Double,
        frequencyTables: [[Double]],
        timestamp: Date
    ) throws -> IOReportSnapshot {
        var frequencies: [IOReportFrequencyReading] = []
        let channelArrays = samples.compactMap { sample -> NSArray? in
            guard let dictionary = sample as? [String: Any] else {
                return nil
            }
            return dictionary["IOReportChannels"] as? NSArray
        }
        guard !channelArrays.isEmpty else {
            throw IOReportSourceError.sampleContentsUnavailable
        }
        for object in channelArrays.flatMap({ Array($0) }) {
            let item = unsafeBitCast(object as AnyObject, to: CFDictionary.self)
            let group = string(mbs_ioreport_channel_get_group(item))
            let subgroup = string(mbs_ioreport_channel_get_subgroup(item))
            let channel = string(mbs_ioreport_channel_get_name(item))
            guard subgroup == "CPU Core Performance States" || subgroup == "CPU Complex Performance States"
                    || subgroup == "GPU Performance States"
            else {
                continue
            }
            let states = states(from: item)
            guard !states.isEmpty else {
                continue
            }
            let kind = frequencyKind(group: group, channel: channel)
            guard kind != .unknown, !channel.hasSuffix("_IDLE") else {
                continue
            }
            let derived = frequency(states: states, candidates: frequencyTables, kind: kind)
            frequencies.append(
                IOReportFrequencyReading(
                    name: channel,
                    kind: kind,
                    averageMHz: derived.averageMHz,
                    activePercent: derived.activePercent,
                    states: states
                )
            )
        }
        let energyReadings = energy.map { reading in
            IOReportEnergyReading(
                group: reading.key.group,
                subgroup: reading.key.subgroup,
                channel: reading.key.channel,
                unit: reading.key.unit,
                energy: reading.value,
                watts: watts(energy: reading.value, unit: reading.key.unit, elapsedSeconds: elapsedSeconds)
            )
        }
        return IOReportSnapshot(
            timestamp: timestamp,
            elapsedSeconds: elapsedSeconds,
            energy: energyReadings,
            power: powerReadings(from: energy, elapsedSeconds: elapsedSeconds),
            frequencies: frequencies.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            temperatures: temperatureReadings(from: currentSamples)
        )
    }

    private static func temperatureReadings(from samples: [CFDictionary]) -> [IOReportTemperatureReading] {
        var readings: [IOReportTemperatureReading] = []
        for sample in samples {
            guard let dictionary = sample as? [String: Any],
                  let channels = dictionary["IOReportChannels"] as? NSArray
            else {
                continue
            }
            for object in channels {
                let item = unsafeBitCast(object as AnyObject, to: CFDictionary.self)
                guard string(mbs_ioreport_channel_get_group(item)) == "GPU Stats",
                      string(mbs_ioreport_channel_get_subgroup(item)) == "Temperature"
                else {
                    continue
                }
                let name = string(mbs_ioreport_channel_get_name(item))
                guard name.hasSuffix(" Latest") else {
                    continue
                }
                let raw = mbs_ioreport_simple_get_integer_value(item, 0)
                guard let celsius = normalizedTemperature(raw), (10...125).contains(celsius) else {
                    continue
                }
                readings.append(IOReportTemperatureReading(name: name, celsius: celsius))
            }
        }
        return readings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func normalizedTemperature(_ raw: Int64) -> Double? {
        guard raw != Int64.min else {
            return nil
        }
        let value = Double(raw)
        if (10...125).contains(value) {
            return value
        }
        for divisor in [1_000.0, 100.0] {
            let scaled = value / divisor
            if (10...125).contains(scaled) {
                return scaled
            }
        }
        return nil
    }

    private static func energyChannels(
        from samples: [CFDictionary]
    ) -> [(key: EnergyChannelKey, value: Double)] {
        var result: [(key: EnergyChannelKey, value: Double)] = []
        for sample in samples {
            guard let dictionary = sample as? [String: Any],
                  let channels = dictionary["IOReportChannels"] as? NSArray
            else {
                continue
            }
            for object in channels {
                let item = unsafeBitCast(object as AnyObject, to: CFDictionary.self)
                let group = string(mbs_ioreport_channel_get_group(item))
                let subgroup = string(mbs_ioreport_channel_get_subgroup(item))
                guard isUnit(group, "Energy Model")
                        || (isUnit(group, "PMP") && isUnit(subgroup, "Energy Counters"))
                else {
                    continue
                }
                let channel = string(mbs_ioreport_channel_get_name(item))
                let key = EnergyChannelKey(
                    group: group,
                    subgroup: subgroup,
                    channel: channel,
                    unit: string(mbs_ioreport_channel_get_unit_label(item))
                )
                let rawValue = mbs_ioreport_simple_get_integer_value(item, 0)
                result.append((key, rawValue == Int64.min ? 0 : Double(rawValue)))
            }
        }
        return result
    }

    private static func powerReadings(
        from energy: [(key: EnergyChannelKey, value: Double)],
        elapsedSeconds: Double
    ) -> [IOReportPowerReading] {
        let selectors: [(String, (String) -> Bool)] = [
            ("CPU", isCPUEnergyChannel),
            ("GPU", { isUnit($0, "GPU Energy") || $0.hasSuffix("_GPU Energy") }),
            ("ANE", { hasUnitPrefix($0, "ANE") }),
            ("DRAM", { hasUnitPrefix($0, "DRAM") }),
            ("GPU SRAM", { hasUnitPrefix($0, "GPU SRAM") }),
        ]
        return selectors.compactMap { name, matches in
            let matching = energy.filter { matches($0.key.channel) }
            let converted = matching.compactMap { reading -> (channel: String, watts: Double)? in
                guard let value = watts(
                    energy: reading.value,
                    unit: reading.key.unit,
                    elapsedSeconds: elapsedSeconds
                ) else {
                    return nil
                }
                return (reading.key.channel, value)
            }
            let exact = converted.first { isUnit($0.channel, "\(name) Energy") && $0.watts > 0 }
            let values = (exact.map { [$0.watts] } ?? converted.map(\.watts)).filter { $0 >= 0 }
            guard !values.isEmpty, name == "ANE" || values.contains(where: { $0 > 0 }) else {
                return nil
            }
            return IOReportPowerReading(name: name, watts: values.reduce(0, +))
        }
    }

    private static func states(from channel: CFDictionary) -> [IOReportStateReading] {
        let count = mbs_ioreport_state_get_count(channel)
        guard count > 0 else {
            return []
        }
        return (0..<count).map { index in
            IOReportStateReading(
                name: string(mbs_ioreport_state_get_name(channel, index)),
                residency: mbs_ioreport_state_get_residency(channel, index)
            )
        }
    }

    private static func string(_ value: Unmanaged<CFString>?) -> String {
        guard let value else {
            return ""
        }
        return value.takeUnretainedValue() as String
    }

    private static func frequencyKind(group: String, channel: String) -> IOReportFrequencyReading.Kind {
        if group == "GPU Stats" {
            return .gpu
        }
        if channel.contains("MCPU") {
            return .middleCPU
        }
        if channel.contains("ECPU") {
            return .lowerCPU
        }
        if channel.contains("PCPU") || channel.contains("SCPU") {
            return .upperCPU
        }
        return .unknown
    }

    private static func frequencyTable(
        stateCount: Int,
        candidates: [[Double]],
        kind: IOReportFrequencyReading.Kind
    ) -> [Double]? {
        let variants = candidates.flatMap { table -> [[Double]] in
            var results: [[Double]] = []
            if table.count == stateCount {
                results.append(table)
            }
            if table.count == stateCount + 1 {
                results.append(Array(table.dropFirst()))
            }
            return results
        }
        let sorted = variants.sorted { ($0.last ?? 0) < ($1.last ?? 0) }
        switch kind {
        case .lowerCPU, .gpu: return sorted.first
        case .upperCPU: return sorted.last
        case .middleCPU: return sorted.dropFirst().first ?? sorted.first
        case .unknown: return sorted.count == 1 ? sorted[0] : nil
        }
    }

    private static func isIdleState(_ name: String) -> Bool {
        ["IDLE", "DOWN", "OFF"].contains(name.uppercased())
    }

    private static func isUnit(_ name: String, _ unit: String) -> Bool {
        name == unit || name.hasSuffix(" \(unit)")
    }

    private static func hasUnitPrefix(_ name: String, _ prefix: String) -> Bool {
        name.hasPrefix(prefix) || name.contains(" \(prefix)")
    }

    static func isCPUEnergyChannel(_ name: String) -> Bool {
        if isUnit(name, "CPU Energy") {
            return true
        }
        let token = name.split(separator: " ").last.map(String.init) ?? name
        if token.hasSuffix("_CPU") {
            let prefix = token.dropLast("_CPU".count)
            return prefix.hasPrefix("EACC") || prefix.hasPrefix("PACC") || prefix.hasPrefix("MACC")
        }
        for prefix in ["ECPU", "MCPU", "PCPU", "SCPU"] where token.hasPrefix(prefix) {
            return token.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
        return false
    }

    private static func readFrequencyTables() -> [[Double]] {
        guard let matching = IOServiceMatching("AppleARMIODevice") else {
            return []
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var tables: [[Double]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS else {
                continue
            }
            let serviceName = String(
                decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            guard serviceName == "pmgr",
                  let properties = properties(for: service)
            else {
                continue
            }
            for (key, value) in properties where key.hasPrefix("voltage-states") {
                guard let data = value as? Data, let table = normalizedFrequencyTable(data: data) else {
                    continue
                }
                if !tables.contains(table) {
                    tables.append(table)
                }
            }
        }
        return tables
    }

    private static func properties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
