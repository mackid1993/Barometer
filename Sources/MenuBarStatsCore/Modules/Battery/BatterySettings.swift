/// Persisted choices specific to the Battery module.
public struct BatterySettings: Codable, Equatable, Sendable {
    /// Whether the status item stays visible while external power is connected.
    public var showsWhenConnectedToPower: Bool

    /// Charge percentage at or below which the status item uses its warning color.
    public var lowBatteryThresholdPercent: Int

    /// Whether connected Bluetooth battery readings appear in the dropdown.
    public var showsBluetoothDevices: Bool

    /// Creates Battery settings.
    public init(
        showsWhenConnectedToPower: Bool = true,
        lowBatteryThresholdPercent: Int = 20,
        showsBluetoothDevices: Bool = true
    ) {
        self.showsWhenConnectedToPower = showsWhenConnectedToPower
        self.lowBatteryThresholdPercent = lowBatteryThresholdPercent
        self.showsBluetoothDevices = showsBluetoothDevices
    }
}
