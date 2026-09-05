/// Sample limits shared by the application and its memory regression benchmark.
public enum GraphHistoryRetention {
    /// Retains day-long CPU and Memory graphs and the displayed windows for other modules.
    public static func capacity(for module: ModuleID) -> Int {
        switch module {
        case .cpu: 86_400
        case .memory: 43_200
        case .gpu, .network, .disks: 300
        case .sensors: 240
        case .battery: 720
        case .weather, .time: 1
        case .combined: 2
        }
    }
}
