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

    /// The permanent autosave name for a one-based module instance.
    public func autosaveName(instance: Int) -> String {
        precondition(instance > 0)
        precondition(instance == 1 || self == .sensors || self == .weather)
        return instance == 1 ? autosaveName : "\(autosaveName).\(instance)"
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

    /// The permanent accessibility label for a one-based module instance.
    public func displayName(instance: Int) -> String {
        instance == 1 ? displayName : "\(displayName) \(instance)"
    }
}

/// Stable identity of one permanent status item, including numbered module instances.
public struct StatusItemIdentity: Hashable, Sendable {
    public let module: ModuleID
    public let instance: Int

    /// Creates a status-item identity. Only Sensors and Weather support extra instances.
    public init(module: ModuleID, instance: Int = 1) {
        precondition(instance > 0)
        precondition(instance == 1 || module == .sensors || module == .weather)
        self.module = module
        self.instance = instance
    }

    /// Permanent AppKit autosave name.
    public var autosaveName: String { module.autosaveName(instance: instance) }

    /// Permanent human-readable accessibility label.
    public var displayName: String { module.displayName(instance: instance) }
}
