import MenuBarStatsCore

extension ModuleID {
    /// Sidebar and pane title.
    ///
    /// Separate from displayName, which is the permanent accessibility label a menu bar manager
    /// pairs with an autosave name and can never change.
    var settingsTitle: String {
        self == .combined ? "Stacks" : displayName
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .disks: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .battery: "battery.75percent"
        case .weather: "cloud.sun"
        case .time: "clock"
        case .combined: "rectangle.3.group"
        }
    }
}
