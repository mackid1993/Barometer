import Foundation
import SystemSources

/// One complete internal-battery sample.
public struct BatterySample: Equatable, Sendable {
    public let timestamp: Date
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
    public let bluetoothDevices: [BluetoothBatterySnapshot]

    /// Creates a timestamped sample from the normalized system source.
    public init(timestamp: Date = Date(), snapshot: BatterySnapshot) {
        self.init(timestamp: timestamp, snapshot: snapshot, bluetoothDevices: [])
    }

    /// Creates a timestamped sample with connected device battery readings.
    public init(
        timestamp: Date = Date(),
        snapshot: BatterySnapshot,
        bluetoothDevices: [BluetoothBatterySnapshot]
    ) {
        self.timestamp = timestamp
        name = snapshot.name
        chargePercent = snapshot.chargePercent
        state = snapshot.state
        isExternalConnected = snapshot.isExternalConnected
        isCharging = snapshot.isCharging
        isFullyCharged = snapshot.isFullyCharged
        timeRemainingMinutes = snapshot.timeRemainingMinutes
        healthPercent = snapshot.healthPercent
        cycleCount = snapshot.cycleCount
        temperatureCelsius = snapshot.temperatureCelsius
        voltageVolts = snapshot.voltageVolts
        amperageAmps = snapshot.amperageAmps
        wattageWatts = snapshot.wattageWatts
        condition = snapshot.condition
        adapter = snapshot.adapter
        isLowPowerModeEnabled = snapshot.isLowPowerModeEnabled
        self.bluetoothDevices = bluetoothDevices
    }
}

/// Compact, stable battery formatting shared by menu bar presentations.
public enum BatteryPresentation {
    /// Formats a remaining-time estimate as hours and zero-padded minutes.
    public static func time(minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "—" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Formats charging or discharging magnitude without allowing a sign to move the item.
    public static func power(watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "—" }
        return String(format: "%.1fW", abs(watts))
    }
}

/// Samples the internal battery through one isolated source wrapper.
public actor BatteryMonitor: Monitor {
    public nonisolated let interval: Duration

    private let readSnapshot: @Sendable () throws -> BatterySnapshot
    private let sourceIsAvailable: @Sendable () -> Bool
    private let readBluetoothDevices: @Sendable () -> [BluetoothBatterySnapshot]

    /// Whether the system currently publishes an internal battery.
    public var isAvailable: Bool { sourceIsAvailable() }

    /// Creates the production battery monitor.
    public init(
        interval: Duration = .seconds(10),
        source: BatterySource = BatterySource(),
        bluetoothSource: BluetoothBatterySource = BluetoothBatterySource()
    ) {
        self.interval = interval
        readSnapshot = { try source.read() }
        sourceIsAvailable = { source.isAvailable }
        readBluetoothDevices = { bluetoothSource.read() }
    }

    /// Creates a monitor with injectable closures for deterministic verification.
    public init(
        interval: Duration = .seconds(10),
        read: @escaping @Sendable () throws -> BatterySnapshot,
        isAvailable: @escaping @Sendable () -> Bool,
        bluetoothDevices: @escaping @Sendable () -> [BluetoothBatterySnapshot] = { [] }
    ) {
        self.interval = interval
        readSnapshot = read
        sourceIsAvailable = isAvailable
        readBluetoothDevices = bluetoothDevices
    }

    /// Collects the latest battery state.
    public func sample() throws -> BatterySample {
        BatterySample(snapshot: try readSnapshot(), bluetoothDevices: readBluetoothDevices())
    }
}
