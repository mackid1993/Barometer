/// Stable identities for every Barometer module.
public enum ModuleID: String, CaseIterable, Codable, Hashable, Sendable {
    case cpu
    case gpu
    case memory
    case disks
    case network
    case sensors
    case battery
    case weather
    case time
    case combined

    /// The permanent status-item autosave name.
    public var autosaveName: String {
        switch self {
        case .cpu: "Barometer.CPU"
        case .gpu: "Barometer.GPU"
        case .memory: "Barometer.Memory"
        case .disks: "Barometer.Disks"
        case .network: "Barometer.Network"
        case .sensors: "Barometer.Sensors"
        case .battery: "Barometer.Battery"
        case .weather: "Barometer.Weather"
        case .time: "Barometer.Time"
        case .combined: "Barometer.Combined"
        }
    }

    /// The permanent human-readable accessibility label.
    public var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disks: "Disks"
        case .network: "Network"
        case .sensors: "Sensors"
        case .battery: "Battery"
        case .weather: "Weather"
        case .time: "Time"
        case .combined: "Combined"
        }
    }
}
