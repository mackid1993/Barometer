import Foundation
import OSLog
import SystemSources

/// Physical quantity represented by a sensor reading.
public enum SensorKind: String, CaseIterable, Codable, Sendable {
    case temperature
    case fan
    case power
    case voltage
    case current
}

/// Hardware interface that produced a reading.
public enum SensorSourceKind: String, Codable, Sendable {
    case derived
    case hid
    case smc
    case ioReport
}

/// Canonical unit stored in a sensor sample.
public enum SensorUnit: String, Codable, Sendable {
    case celsius
    case rpm
    case watts
    case volts
    case amps
}

/// One normalized, stable hardware reading.
public struct SensorReading: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let shortName: String
    public let rawName: String
    public let kind: SensorKind
    public let source: SensorSourceKind
    public let value: Double
    public let unit: SensorUnit

    /// Creates a normalized sensor reading.
    public init(
        id: String,
        name: String,
        shortName: String,
        rawName: String,
        kind: SensorKind,
        source: SensorSourceKind,
        value: Double,
        unit: SensorUnit
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.rawName = rawName
        self.kind = kind
        self.source = source
        self.value = value
        self.unit = unit
    }
}

/// Energy accumulated since this Barometer process began monitoring.
public struct SensorEnergyReading: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let joules: Double

    /// Creates a session energy total.
    public init(id: String, name: String, joules: Double) {
        self.id = id
        self.name = name
        self.joules = joules
    }
}

/// Combined hardware sample from IOHID, AppleSMC, and IOReport.
public struct SensorSample: Equatable, Sendable {
    public let timestamp: Date
    public let readings: [SensorReading]
    public let sessionEnergy: [SensorEnergyReading]

    /// Creates a complete Sensors sample.
    public init(timestamp: Date, readings: [SensorReading], sessionEnergy: [SensorEnergyReading]) {
        self.timestamp = timestamp
        self.readings = readings
        self.sessionEnergy = sessionEnergy
    }

    /// Hottest currently valid temperature.
    public var hottestTemperature: SensorReading? {
        readings.filter { $0.kind == .temperature }.max { $0.value < $1.value }
    }

    /// Finds a stable reading identifier.
    public func reading(id: String) -> SensorReading? {
        readings.first { $0.id == id }
    }

    /// Returns user-facing readings, keeping firmware identifiers behind the explicit raw-name option.
    public func displayReadings(hidesDuplicates: Bool, showsRawNames: Bool = false) -> [SensorReading] {
        let visible = showsRawNames ? readings : readings.filter(\.isFriendly)
        guard hidesDuplicates else {
            return visible
        }
        var seen: Set<String> = []
        return visible.sorted { $0.source.priority < $1.source.priority }.filter { reading in
            let key = "\(reading.kind.rawValue):\(reading.name.lowercased())"
            return seen.insert(key).inserted
        }
    }
}

/// Formatting shared by Sensors menu bar and dropdown presentation.
public enum SensorValueFormatter {
    /// Formats a reading with the selected temperature unit and stable fractional precision.
    public static func string(
        _ reading: SensorReading,
        temperatureUnit: TemperatureUnit,
        decimalPlaces: Int,
        compact: Bool = false
    ) -> String {
        let precision = min(2, max(0, decimalPlaces))
        let converted: Double
        let suffix: String
        switch reading.unit {
        case .celsius:
            converted = temperatureUnit == .fahrenheit ? reading.value * 9 / 5 + 32 : reading.value
            suffix = temperatureUnit.symbol
        case .rpm:
            converted = reading.value
            suffix = compact ? "r" : " RPM"
        case .watts:
            converted = reading.value
            suffix = compact ? "W" : " W"
        case .volts:
            converted = reading.value
            suffix = compact ? "V" : " V"
        case .amps:
            converted = reading.value
            suffix = compact ? "A" : " A"
        }
        let places = reading.unit == .rpm ? 0 : precision
        return String(format: "%.*f%@", places, converted, suffix)
    }

    /// Stable widest field used to prevent live values from shifting adjacent menu items.
    public static func placeholder(
        for reading: SensorReading,
        temperatureUnit: TemperatureUnit,
        decimalPlaces: Int
    ) -> String {
        let precision = reading.unit == .rpm ? 0 : min(2, max(0, decimalPlaces))
        let fraction = precision == 0 ? "" : "." + String(repeating: "9", count: precision)
        switch reading.unit {
        case .celsius:
            let maximum = temperatureUnit == .celsius ? "125" : "257"
            return "\(maximum)\(fraction)\(temperatureUnit.symbol)"
        case .rpm: return "9999r"
        case .watts: return "999\(fraction)W"
        case .volts: return "999\(fraction)V"
        case .amps: return "999\(fraction)A"
        }
    }
}

/// Merges the three read-only hardware interfaces without requiring root or a helper process.
public actor SensorsMonitor: Monitor {
    public nonisolated let interval: Duration

    private static let logger = Logger(subsystem: "com.barometer.app", category: "sensors")
    private let hidSource: HIDTemperatureSource
    private let smcSource: SMCClient?
    private let ioReportSource: IOReportSource?
    private var energyAccumulator = SensorEnergyAccumulator()
    private var cachedSMCReadings: [SensorReading] = []
    private var cachedIOReportReadings: [SensorReading] = []
    private var lastSMCRefresh: Date?
    private var lastIOReportRefresh: Date?

    /// Whether at least one supported hardware interface opened successfully.
    public var isAvailable: Bool {
        get async {
            if smcSource != nil || ioReportSource != nil {
                return true
            }
            return (try? await hidSource.read().isEmpty) == false
        }
    }

    /// Creates a runtime-discovered Sensors monitor.
    public init(interval: Duration = .seconds(2)) {
        self.interval = interval
        hidSource = HIDTemperatureSource()
        smcSource = try? SMCClient()
        ioReportSource = try? IOReportSource()
    }

    /// Collects available sources independently and returns every valid reading.
    public func sample() async throws -> SensorSample {
        var readings: [SensorReading] = []
        let timestamp = Date()

        do {
            readings.append(contentsOf: Self.hidReadings(try await hidSource.read()))
        } catch {
            Self.logger.debug("IOHID sensor read unavailable: \(String(describing: error), privacy: .public)")
        }

        if let smcSource, Self.shouldRefresh(lastRefresh: lastSMCRefresh, now: timestamp, interval: 10) {
            lastSMCRefresh = timestamp
            do {
                cachedSMCReadings = try await Self.smcReadings(from: smcSource)
            } catch {
                Self.logger.debug("SMC sensor read unavailable: \(String(describing: error), privacy: .public)")
            }
        }
        readings.append(contentsOf: cachedSMCReadings)

        if let ioReportSource, Self.shouldRefresh(lastRefresh: lastIOReportRefresh, now: timestamp, interval: 5) {
            let previousRefresh = lastIOReportRefresh
            lastIOReportRefresh = timestamp
            do {
                let snapshot = try await ioReportSource.sample(over: .seconds(1))
                let power = Self.ioReportReadings(snapshot.power)
                cachedIOReportReadings = power
                let elapsed = previousRefresh.map { timestamp.timeIntervalSince($0) } ?? snapshot.elapsedSeconds
                accumulateIOReportEnergy(power, elapsedSeconds: max(snapshot.elapsedSeconds, elapsed))
            } catch {
                Self.logger.debug("IOReport sensor read unavailable: \(String(describing: error), privacy: .public)")
            }
        }
        readings.append(contentsOf: cachedIOReportReadings)

        readings = Self.addDerivedTemperatures(to: readings)
        accumulateSystemEnergy(readings: readings, timestamp: timestamp)
        guard !readings.isEmpty else {
            throw SensorsMonitorError.noReadings
        }
        let energy = energyAccumulator.joules.map { id, joules in
            SensorEnergyReading(id: id, name: Self.energyName(for: id), joules: joules)
        }.sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))
        return SensorSample(
            timestamp: timestamp,
            readings: readings.sorted(by: Self.readingOrder),
            sessionEnergy: energy
        )
    }

    /// Clears energy accumulated during the current process session.
    public func resetSessionEnergy() {
        energyAccumulator.reset()
    }

    static func shouldRefresh(lastRefresh: Date?, now: Date, interval: TimeInterval) -> Bool {
        lastRefresh.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    private static func hidReadings(_ source: [HIDTemperatureReading]) -> [SensorReading] {
        source.map { reading in
            SensorReading(
                id: "hid:temperature:\(reading.rawName)",
                name: reading.name,
                shortName: shortTemperatureName(reading.name, rawName: reading.rawName),
                rawName: reading.rawName,
                kind: .temperature,
                source: .hid,
                value: reading.celsius,
                unit: .celsius
            )
        }
    }

    private static func smcReadings(from source: SMCClient) async throws -> [SensorReading] {
        var readings: [SensorReading] = []
        for value in try await source.sensorValues() {
            guard let number = value.numericValue,
                let kind = smcKind(key: value.key, value: number)
            else {
                continue
            }
            readings.append(
                SensorReading(
                    id: "smc:\(kind.rawValue):\(value.key)",
                    name: friendlySMCName(key: value.key, kind: kind),
                    shortName: shortSMCName(key: value.key, kind: kind),
                    rawName: value.key,
                    kind: kind,
                    source: .smc,
                    value: number,
                    unit: unit(for: kind)
                )
            )
        }
        for fan in try await source.fans() {
            readings.append(
                SensorReading(
                    id: "smc:fan:\(fan.id)",
                    name: fan.name,
                    shortName: "FAN\(fan.id + 1)",
                    rawName: "F\(fan.id)Ac",
                    kind: .fan,
                    source: .smc,
                    value: fan.currentRPM,
                    unit: .rpm
                )
            )
        }
        return readings
    }

    private static func ioReportReadings(_ source: [IOReportPowerReading]) -> [SensorReading] {
        source.filter { $0.watts.isFinite && $0.watts >= 0 }.map { reading in
            SensorReading(
                id: "ioreport:power:\(reading.name.lowercased())",
                name: "\(reading.name) Power",
                shortName: reading.name.uppercased(),
                rawName: reading.name,
                kind: .power,
                source: .ioReport,
                value: reading.watts,
                unit: .watts
            )
        }
    }

    /// Appends the summary readings shown by the menu bar and the top of the dropdown.
    ///
    /// The CPU value is the hottest processor die sensor, in this order of preference:
    /// the IOHID `PMU tdie*` sensors (`SoC die N`), then the SMC `TPD*` die keys, and only
    /// then the broad SMC `Tp*`/`Te*` families. On the M4 Pro those broad families include
    /// package and hotspot sensors that read 20 to 30 degrees above the cores, which made
    /// the earlier "hottest of anything named CPU" rule report a CPU temperature no other
    /// monitor agreed with.
    static func addDerivedTemperatures(to readings: [SensorReading]) -> [SensorReading] {
        var result = readings
        let temperatures = readings.filter { $0.kind == .temperature }
        if let hottest = temperatures.max(by: { $0.value < $1.value }) {
            result.append(
                derivedTemperature(
                    id: "hottest",
                    name: "Hottest Temperature",
                    shortName: "HOT",
                    value: hottest.value
                )
            )
        }
        if let cpu = cpuDieReadings(in: temperatures).max(by: { $0.value < $1.value }) {
            result.append(derivedTemperature(id: "cpu", name: "CPU Temperature", shortName: "CPU", value: cpu.value))
        }
        let gpuMatches = temperatures.filter { $0.name.hasPrefix("GPU ") || $0.name == "GPU" }
        if let gpu = gpuMatches.max(by: { $0.value < $1.value }) {
            result.append(derivedTemperature(id: "gpu", name: "GPU Temperature", shortName: "GPU", value: gpu.value))
        }
        return result
    }

    /// The readings that represent processor die temperature, best source first.
    static func cpuDieReadings(in temperatures: [SensorReading]) -> [SensorReading] {
        let dieSensors = temperatures.filter { $0.source == .hid && $0.name.hasPrefix("SoC die") }
        if !dieSensors.isEmpty {
            return dieSensors
        }
        let packageDieKeys = temperatures.filter { $0.source == .smc && $0.rawName.hasPrefix("TPD") }
        if !packageDieKeys.isEmpty {
            return packageDieKeys
        }
        return temperatures.filter { $0.name.hasPrefix("CPU ") || $0.name == "CPU" }
    }

    private static func derivedTemperature(
        id: String,
        name: String,
        shortName: String,
        value: Double
    ) -> SensorReading {
        SensorReading(
            id: "derived:temperature:\(id)",
            name: name,
            shortName: shortName,
            rawName: id,
            kind: .temperature,
            source: .derived,
            value: value,
            unit: .celsius
        )
    }

    private func accumulateIOReportEnergy(_ readings: [SensorReading], elapsedSeconds: Double) {
        for reading in readings {
            let id = "ioreport:\(reading.rawName.lowercased())"
            energyAccumulator.addPowerSample(id: id, watts: reading.value, elapsedSeconds: elapsedSeconds)
        }
    }

    private func accumulateSystemEnergy(readings: [SensorReading], timestamp: Date) {
        guard let system = readings.first(where: { $0.id == "smc:power:PSTR" }) else {
            energyAccumulator.clearPreviousSystemPower()
            return
        }
        energyAccumulator.addSystemPowerSample(watts: system.value, timestamp: timestamp)
    }

    private static func smcKind(key: String, value: Double) -> SensorKind? {
        guard value.isFinite, let first = key.first else {
            return nil
        }
        switch first {
        // Runtime enumeration exposes calibration and threshold keys alongside
        // physical probes. Values at or below 10 °C are not credible operating
        // temperatures inside a running Mac and otherwise flood the UI.
        case "T" where (10...125).contains(value): return .temperature
        case "P" where (-500...2_000).contains(value): return .power
        case "V" where (-100...1_000).contains(value): return .voltage
        case "I" where (-1_000...1_000).contains(value): return .current
        default: return nil
        }
    }

    private static func friendlySMCName(key: String, kind: SensorKind) -> String {
        guard kind == .temperature else {
            return knownSMCName(key) ?? key
        }
        if key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("TPD") || key.hasPrefix("TRD") {
            return "CPU \(key)"
        }
        if key.hasPrefix("Tg") || key.hasPrefix("TG") {
            return "GPU \(key)"
        }
        if key.hasPrefix("TB") { return "Battery \(key)" }
        if key.hasPrefix("TS") || key.hasPrefix("Ts") { return "Storage \(key)" }
        if key.hasPrefix("Tm") || key.hasPrefix("TM") { return "Memory \(key)" }
        return key
    }

    private static func shortSMCName(key: String, kind: SensorKind) -> String {
        if let known = knownSMCShortName(key) {
            return known
        }
        if kind == .temperature {
            if key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("TPD") || key.hasPrefix("TRD") {
                return "CPU"
            }
            if key.hasPrefix("Tg") || key.hasPrefix("TG") { return "GPU" }
            if key.hasPrefix("TB") { return "BAT" }
            if key.hasPrefix("TS") || key.hasPrefix("Ts") { return "SSD" }
        }
        return key.uppercased()
    }

    private static func knownSMCName(_ key: String) -> String? {
        switch key {
        case "PSTR": "System Power"
        case "PDTR": "Adapter Power"
        case "PPBR": "Battery Power"
        default: nil
        }
    }

    private static func knownSMCShortName(_ key: String) -> String? {
        switch key {
        case "PSTR": "SYS"
        case "PDTR": "AC"
        case "PPBR": "BAT"
        default: nil
        }
    }

    private static func shortTemperatureName(_ name: String, rawName: String) -> String {
        if name == "Battery" { return "BAT" }
        if name == "SSD" { return "SSD" }
        if name == "PMU" { return "PMU" }
        if name.hasPrefix("SoC die") { return "SOC" }
        return String(rawName.prefix(4)).uppercased()
    }

    private static func unit(for kind: SensorKind) -> SensorUnit {
        switch kind {
        case .temperature: .celsius
        case .fan: .rpm
        case .power: .watts
        case .voltage: .volts
        case .current: .amps
        }
    }

    private static func readingOrder(_ lhs: SensorReading, _ rhs: SensorReading) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind.sortIndex < rhs.kind.sortIndex
        }
        if lhs.source != rhs.source {
            return lhs.source.priority < rhs.source.priority
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func energyName(for id: String) -> String {
        if id == "smc:system" { return "System" }
        let raw = id.split(separator: ":").last.map(String.init) ?? id
        return raw.uppercased()
    }
}

struct SensorEnergyAccumulator {
    private(set) var joules: [String: Double] = [:]
    private var previousSystemPower: (timestamp: Date, watts: Double)?

    mutating func addPowerSample(id: String, watts: Double, elapsedSeconds: Double) {
        guard watts.isFinite, watts >= 0, elapsedSeconds > 0, elapsedSeconds <= 10 else {
            return
        }
        joules[id, default: 0] += watts * elapsedSeconds
    }

    mutating func addSystemPowerSample(watts: Double, timestamp: Date) {
        guard watts.isFinite, watts >= 0 else {
            previousSystemPower = nil
            return
        }
        defer { previousSystemPower = (timestamp, watts) }
        guard let previousSystemPower else {
            return
        }
        let elapsed = timestamp.timeIntervalSince(previousSystemPower.timestamp)
        guard elapsed > 0, elapsed <= 10 else {
            return
        }
        joules["smc:system", default: 0] += (previousSystemPower.watts + watts) / 2 * elapsed
    }

    mutating func clearPreviousSystemPower() {
        previousSystemPower = nil
    }

    mutating func reset() {
        joules = [:]
        previousSystemPower = nil
    }
}

/// Sensors monitor failures after all independent sources have degraded.
public enum SensorsMonitorError: Error, Sendable {
    case noReadings
}

extension SensorSourceKind {
    fileprivate var priority: Int {
        switch self {
        case .derived: 0
        case .ioReport: 1
        case .hid: 2
        case .smc: 3
        }
    }
}

extension SensorKind {
    fileprivate var sortIndex: Int {
        switch self {
        case .temperature: 0
        case .fan: 1
        case .power: 2
        case .voltage: 3
        case .current: 4
        }
    }
}

extension SensorReading {
    fileprivate var isFriendly: Bool {
        switch source {
        case .derived, .hid, .ioReport:
            return true
        case .smc:
            if kind == .fan {
                return true
            }
            return ["PSTR", "PDTR", "PPBR"].contains(rawName)
        }
    }
}
