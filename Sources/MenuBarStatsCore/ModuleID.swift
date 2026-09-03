/// Stable identities for every MenuBarStats module.
public enum ModuleID: String, CaseIterable, Hashable, Sendable {
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
        case .cpu: "MenuBarStats.CPU"
        case .gpu: "MenuBarStats.GPU"
        case .memory: "MenuBarStats.Memory"
        case .disks: "MenuBarStats.Disks"
        case .network: "MenuBarStats.Network"
        case .sensors: "MenuBarStats.Sensors"
        case .battery: "MenuBarStats.Battery"
        case .weather: "MenuBarStats.Weather"
        case .time: "MenuBarStats.Time"
        case .combined: "MenuBarStats.Combined"
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
