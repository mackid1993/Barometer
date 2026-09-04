import Foundation

/// One reading a stack can show in the menu bar.
///
/// A stack composes readings rather than whole module presentations, so a single independently
/// movable item can mix CPU, memory, network, and power the way the Sensors compact stack already
/// mixes temperatures and fans. Raw values are persisted and must never change.
public enum StackMetric: String, CaseIterable, Codable, Hashable, Sendable {
    case cpuTotal = "cpu.total"
    case cpuUser = "cpu.user"
    case cpuSystem = "cpu.system"
    case cpuIdle = "cpu.idle"
    case cpuLoad = "cpu.load"

    case gpuUtilization = "gpu.utilization"
    case gpuPower = "gpu.power"
    case gpuTemperature = "gpu.temperature"

    case memoryUsedPercent = "memory.usedPercent"
    case memoryUsedBytes = "memory.usedBytes"
    case memoryFreeBytes = "memory.freeBytes"
    case memoryPressure = "memory.pressure"
    case memorySwap = "memory.swap"

    case diskRead = "disks.read"
    case diskWrite = "disks.write"
    case diskUsedPercent = "disks.usedPercent"
    case diskFreeBytes = "disks.freeBytes"

    case networkDownload = "network.download"
    case networkUpload = "network.upload"

    case sensorsHottest = "sensors.hottest"
    case sensorsFan = "sensors.fan"

    case batteryCharge = "battery.charge"
    case batteryTime = "battery.time"

    case weatherTemperature = "weather.temperature"

    case timeClock = "time.clock"

    /// The module that samples this reading.
    ///
    /// A stack keeps its source module's scheduler running and takes its color from the module,
    /// so every metric must name exactly one owner.
    public var module: ModuleID {
        switch self {
        case .cpuTotal, .cpuUser, .cpuSystem, .cpuIdle, .cpuLoad: .cpu
        case .gpuUtilization, .gpuPower, .gpuTemperature: .gpu
        case .memoryUsedPercent, .memoryUsedBytes, .memoryFreeBytes, .memoryPressure, .memorySwap: .memory
        case .diskRead, .diskWrite, .diskUsedPercent, .diskFreeBytes: .disks
        case .networkDownload, .networkUpload: .network
        case .sensorsHottest, .sensorsFan: .sensors
        case .batteryCharge, .batteryTime: .battery
        case .weatherTemperature: .weather
        case .timeClock: .time
        }
    }

    /// Short menu bar label drawn above or beside the value.
    public var label: String {
        switch self {
        case .cpuTotal: "CPU"
        case .cpuUser: "USR"
        case .cpuSystem: "SYS"
        case .cpuIdle: "IDLE"
        case .cpuLoad: "LOAD"
        case .gpuUtilization: "GPU"
        case .gpuPower: "GPUW"
        case .gpuTemperature: "GPU°"
        case .memoryUsedPercent: "MEM"
        case .memoryUsedBytes: "USED"
        case .memoryFreeBytes: "FREE"
        case .memoryPressure: "PRES"
        case .memorySwap: "SWAP"
        case .diskRead: "READ"
        case .diskWrite: "WRIT"
        case .diskUsedPercent: "DISK"
        case .diskFreeBytes: "DFRE"
        case .networkDownload: "DOWN"
        case .networkUpload: "UP"
        case .sensorsHottest: "TEMP"
        case .sensorsFan: "FAN"
        case .batteryCharge: "BAT"
        case .batteryTime: "TIME"
        case .weatherTemperature: "OUT"
        case .timeClock: "CLOCK"
        }
    }

    /// Full name shown when choosing metrics in Settings.
    public var displayName: String {
        switch self {
        case .cpuTotal: "CPU usage"
        case .cpuUser: "CPU user"
        case .cpuSystem: "CPU system"
        case .cpuIdle: "CPU idle"
        case .cpuLoad: "Load average"
        case .gpuUtilization: "GPU usage"
        case .gpuPower: "GPU power"
        case .gpuTemperature: "GPU temperature"
        case .memoryUsedPercent: "Memory used"
        case .memoryUsedBytes: "Memory used bytes"
        case .memoryFreeBytes: "Memory free bytes"
        case .memoryPressure: "Memory pressure"
        case .memorySwap: "Swap used"
        case .diskRead: "Disk read rate"
        case .diskWrite: "Disk write rate"
        case .diskUsedPercent: "Disk used"
        case .diskFreeBytes: "Disk free"
        case .networkDownload: "Network download"
        case .networkUpload: "Network upload"
        case .sensorsHottest: "Hottest temperature"
        case .sensorsFan: "Fan speed"
        case .batteryCharge: "Battery charge"
        case .batteryTime: "Battery time remaining"
        case .weatherTemperature: "Outside temperature"
        case .timeClock: "Clock"
        }
    }

    /// Metrics grouped by owning module in a stable order for the Settings picker.
    public static var byModule: [(module: ModuleID, metrics: [StackMetric])] {
        ModuleID.allCases.compactMap { module in
            let metrics = StackMetric.allCases.filter { $0.module == module }
            return metrics.isEmpty ? nil : (module, metrics)
        }
    }

    /// The metric a module contributes when an older Combined membership is migrated.
    public static func primary(for module: ModuleID) -> StackMetric? {
        switch module {
        case .cpu: .cpuTotal
        case .gpu: .gpuUtilization
        case .memory: .memoryUsedPercent
        case .disks: .diskRead
        case .network: .networkDownload
        case .sensors: .sensorsHottest
        case .battery: .batteryCharge
        case .weather: .weatherTemperature
        case .time: .timeClock
        case .combined: nil
        }
    }
}

extension StackMetric {
    /// Widest string this reading can ever show, given the units currently selected.
    ///
    /// The menu bar renderer and the Settings preview both size from this, so a preview can never
    /// show a different width than the item it is previewing.
    public func reservedValue(settings: AppSettings) -> String {
        let unitSystem = settings.disks.unitSystem
        let capacity = unitSystem == .binary ? "999GiB" : "999GB"
        let rate = unitSystem == .binary ? "999GiB/s" : "999GB/s"
        let degrees = settings.sensorTemperatureUnit == .fahrenheit ? "257°F" : "125°C"
        switch self {
        case .cpuTotal, .cpuUser, .cpuSystem, .cpuIdle, .gpuUtilization,
            .memoryUsedPercent, .memoryPressure, .diskUsedPercent, .batteryCharge:
            return "100%"
        case .cpuLoad:
            return "99.99"
        case .gpuPower:
            return "199.9W"
        case .gpuTemperature, .sensorsHottest:
            return degrees
        case .memoryUsedBytes, .memoryFreeBytes, .memorySwap, .diskFreeBytes:
            return capacity
        case .diskRead, .diskWrite:
            return rate
        case .networkDownload, .networkUpload:
            return NetworkRateFormatter.compactPlaceholder(
                unit: settings.network.rateUnit,
                decimalPlaces: settings.network.decimalPlaces
            )
        case .sensorsFan:
            return "9999r"
        case .batteryTime:
            return BatteryTimeFormatter.reservedCompact
        case .weatherTemperature:
            return "-99°"
        case .timeClock:
            return TimeFormatEngine.menuBarPlaceholder(
                template: settings.time.menuBarTemplate,
                showsSeconds: settings.time.showsSeconds
            )
        }
    }

    /// Representative value used by the Settings preview before any sample exists.
    public func previewValue(settings: AppSettings) -> String {
        let unitSystem = settings.disks.unitSystem
        switch self {
        case .cpuTotal: return "12%"
        case .cpuUser: return "8%"
        case .cpuSystem: return "4%"
        case .cpuIdle: return "88%"
        case .cpuLoad: return "1.42"
        case .gpuUtilization: return "6%"
        case .gpuPower: return "3.4W"
        case .gpuTemperature, .sensorsHottest:
            return settings.sensorTemperatureUnit == .fahrenheit ? "118°F" : "48°C"
        case .memoryUsedPercent: return "71%"
        case .memoryPressure: return "29%"
        case .memoryUsedBytes: return unitSystem == .binary ? "17GiB" : "18GB"
        case .memoryFreeBytes: return unitSystem == .binary ? "7GiB" : "7GB"
        case .memorySwap: return unitSystem == .binary ? "2GiB" : "2GB"
        case .diskUsedPercent: return "64%"
        case .diskFreeBytes: return unitSystem == .binary ? "312GiB" : "335GB"
        case .diskRead: return unitSystem == .binary ? "4MiB/s" : "4MB/s"
        case .diskWrite: return unitSystem == .binary ? "1MiB/s" : "1MB/s"
        case .networkDownload:
            return NetworkRateFormatter.compactString(
                bytesPerSecond: 1_200_000,
                unit: settings.network.rateUnit,
                decimalPlaces: settings.network.decimalPlaces
            )
        case .networkUpload:
            return NetworkRateFormatter.compactString(
                bytesPerSecond: 82_000,
                unit: settings.network.rateUnit,
                decimalPlaces: settings.network.decimalPlaces
            )
        case .sensorsFan: return "2100r"
        case .batteryCharge: return "78%"
        case .batteryTime: return "7:30"
        case .weatherTemperature: return "72°"
        case .timeClock:
            return TimeFormatEngine.render(
                date: Date(timeIntervalSince1970: 1_757_000_000),
                timeZone: .current,
                template: settings.time.menuBarTemplate,
                showsSeconds: settings.time.showsSeconds
            )
        }
    }
}
