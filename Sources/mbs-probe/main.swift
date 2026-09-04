import Darwin
import Foundation
import MenuBarStatsCore
import SystemSources

private enum ProbeCommand: String {
    case battery
    case cpu
    case disks
    case fans
    case freq
    case geocode
    case gpu
    case identity
    case memory
    case net
    case power
    case sensors
    case smc
    case temps
    case time
    case version
    case weather
    case wifi
}

private func runBatteryProbe() throws {
    let sample = try BatterySource().read()
    print(String(format: "Battery %.1f%% — %@", sample.chargePercent, sample.state.rawValue))
    print(
        "health \(sample.healthPercent.map { String(format: "%.1f%%", $0) } ?? "unavailable"); "
            + "cycles \(sample.cycleCount.map(String.init) ?? "unavailable")"
    )
    print(
        "temperature \(sample.temperatureCelsius.map { String(format: "%.2f °C", $0) } ?? "unavailable"); "
            + "voltage \(sample.voltageVolts.map { String(format: "%.3f V", $0) } ?? "unavailable"); "
            + "current \(sample.amperageAmps.map { String(format: "%.3f A", $0) } ?? "unavailable"); "
            + "power \(sample.wattageWatts.map { String(format: "%.2f W", $0) } ?? "unavailable")"
    )
    if let adapter = sample.adapter {
        print(
            "adapter \(adapter.name ?? adapter.description ?? "unknown"); "
                + "rated \(adapter.watts.map { String(format: "%.0f W", $0) } ?? "unavailable")"
        )
    }
    print("low power mode: \(sample.isLowPowerModeEnabled ? "on" : "off")")
    let devices = BluetoothBatterySource().read()
    if devices.isEmpty {
        print("Bluetooth batteries: none published")
    } else {
        for device in devices {
            let levels = device.levels.map { "\($0.component.rawValue) \($0.percent)%" }.joined(separator: ", ")
            print("Bluetooth battery: \(device.name) — \(levels)")
        }
    }
}

private func runTimeProbe() async throws {
    let sample = await TimeMonitor().sample()
    guard let timeZone = TimeZone(identifier: sample.systemTimeZoneIdentifier) else {
        throw CocoaError(.formatting)
    }
    let local = TimeFormatEngine.render(
        date: sample.timestamp,
        timeZone: timeZone,
        template: "{weekday} {date} {time} · W{week} D{day} · {zone}",
        showsSeconds: true
    )
    print("Time \(local)")
    print("system time zone: \(sample.systemTimeZoneIdentifier)")
}

private func runIdentityProbe() {
    print("statusItemCreation=disabled")
    print("probeBundleIdentifier=\(Bundle.main.bundleIdentifier ?? "none")")
    for module in ModuleID.allCases {
        print("\(module.displayName)=\(module.autosaveName)")
    }
}

private func printVersion() {
    let versionURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("VERSION")
    guard let version = try? String(contentsOf: versionURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    else {
        writeError("Unable to read VERSION from \(versionURL.path)")
        exit(EXIT_FAILURE)
    }
    print(version)
}

private func runCPUProbe(watch: Bool) async throws {
    let monitor = CPUMonitor(processRefreshInterval: 0.2)
    _ = try await monitor.sample()

    repeat {
        try await Task.sleep(for: watch ? .seconds(1) : .milliseconds(250))
        let sample = try await monitor.sample()
        printCPUSample(sample)
    } while watch
}

private func runGPUProbe(watch: Bool) async throws {
    let monitor = GPUMonitor()
    repeat {
        let sample = try await monitor.sample()
        print(String(format: "GPU %.1f%% — %@", sample.deviceUtilizationPercent, sample.name))
        print(
            String(
                format: "renderer %@; tiler %@; memory %@ / %@",
                sample.rendererUtilizationPercent.map { String(format: "%.1f%%", $0) } ?? "unavailable",
                sample.tilerUtilizationPercent.map { String(format: "%.1f%%", $0) } ?? "unavailable",
                sample.memoryInUseBytes.map(formatBytes) ?? "unavailable",
                sample.memoryAllocatedBytes.map(formatBytes) ?? "unavailable"
            )
        )
        print(
            "frequency \(sample.frequencyMHz.map { String(format: "%.0f MHz", $0) } ?? "unavailable"); "
                + "power \(sample.powerWatts.map { String(format: "%.2f W", $0) } ?? "unavailable"); "
                + "temperature \(sample.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "unavailable")"
        )
        if watch {
            try await Task.sleep(for: .seconds(1))
        }
    } while watch
}

private func printCPUSample(_ sample: CPUSample) {
    let load = sample.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: ", ")
    let uptime = sample.uptime.map { String(format: "%.0f s", $0) } ?? "unavailable"
    print(
        String(
            format: "CPU %.1f%% (user %.1f%%, system %.1f%%, nice %.1f%%, idle %.1f%%)",
            sample.totalPercent,
            sample.userPercent,
            sample.systemPercent,
            sample.nicePercent,
            sample.idlePercent
        )
    )
    print("load averages: \(load); uptime: \(uptime)")
    print("processes: \(sample.processCount); threads: \(sample.threadCount)")
    let cores = sample.perCore.map { core in
        let prefix: String
        switch core.kind {
        case .efficiency: prefix = "E"
        case .performance: prefix = "P"
        case .unknown: prefix = "C"
        }
        return String(format: "%@%d %.1f%%", prefix, core.index, core.usagePercent)
    }
    print("cores: \(cores.joined(separator: ", "))")
    if !sample.topProcesses.isEmpty {
        print("top processes:")
        for process in sample.topProcesses {
            print(
                String(
                    format: "  %6d  %6.2f%%  %@",
                    process.processIdentifier,
                    process.cpuPercent,
                    process.name
                )
            )
        }
    }
}

private func runMemoryProbe() async throws {
    let monitor = MemoryMonitor()
    let sample = try await monitor.sample()
    printMemorySample(sample)
}

private func runNetworkProbe(watch: Bool) async throws {
    let monitor = NetworkMonitor()
    _ = try await monitor.sample()
    repeat {
        try await Task.sleep(for: .seconds(1))
        let sample = try await monitor.sample()
        printNetworkSample(sample)
    } while watch
}

private func runDiskProbe(watch: Bool) async throws {
    let monitor = DiskMonitor()
    _ = try await monitor.sample()
    repeat {
        try await Task.sleep(for: .seconds(1))
        let sample = try await monitor.sample()
        printDiskSample(sample)
    } while watch
}

private func printDiskSample(_ sample: DiskSample) {
    print("Volumes:")
    for volume in sample.volumes where volume.totalBytes > 0 {
        let attachment = volume.kind.rawValue
        let device = volume.physicalBSDName ?? volume.bsdName ?? "unmapped"
        print(
            String(
                format: "  %@ (%@): %.1f%% used, %@ free of %@ [%@, %@]",
                volume.name,
                volume.mountPoint,
                volume.usedPercent,
                formatBytes(volume.availableBytes),
                formatBytes(volume.totalBytes),
                attachment,
                device
            )
        )
    }
    print("Physical disks:")
    for device in sample.devices {
        print(
            "  \(device.bsdName) \(device.model ?? "Unknown"): "
                + "read \(formatRate(device.readBytesPerSecond)), "
                + "write \(formatRate(device.writeBytesPerSecond)), "
                + String(format: "%.1f/%.1f ops/s", device.readOperationsPerSecond, device.writeOperationsPerSecond)
        )
        print("    lifetime read \(formatBytes(device.bytesRead)), write \(formatBytes(device.bytesWritten))")
    }
}

private func printNetworkSample(_ sample: NetworkSample) {
    guard let primary = sample.primary else {
        print("Network unavailable")
        return
    }
    print(
        "Primary \(primary.name): down \(formatRate(primary.downloadBytesPerSecond)), "
            + "up \(formatRate(primary.uploadBytesPerSecond))"
    )
    print("IPv4: \(primary.ipv4Addresses.joined(separator: ", "))")
    print("IPv6: \(primary.ipv6Addresses.joined(separator: ", "))")
    print("Router: \(sample.router ?? "unavailable"); DNS: \(sample.dnsServers.joined(separator: ", "))")
    print("Totals: down \(formatBytes(primary.receivedBytes)); up \(formatBytes(primary.sentBytes))")
    if !sample.isProcessActivityAvailable {
        print("Per-process activity unavailable")
    } else if !sample.topProcesses.isEmpty {
        print("Top network activity:")
        for process in sample.topProcesses.prefix(5) {
            print(
                "  \(process.name): down \(formatRate(process.downloadBytesPerSecond)), "
                    + "up \(formatRate(process.uploadBytesPerSecond))"
            )
        }
    }
}

private func runWiFiProbe() async throws {
    let sample = try await NetworkMonitor().sample()
    guard let wifi = sample.wifi else {
        print("Wi-Fi unavailable")
        return
    }
    print("Interface: \(wifi.interfaceName); powered: \(wifi.isPowered ? "yes" : "no")")
    print("SSID: \(wifi.ssid ?? "unavailable (Location permission may be required)")")
    print("BSSID: \(wifi.bssid ?? "unavailable (Location permission may be required)")")
    print("RSSI: \(wifi.rssi.map { "\($0) dBm" } ?? "unavailable")")
    print("Noise: \(wifi.noise.map { "\($0) dBm" } ?? "unavailable")")
    print("Channel: \(wifi.channel.map(String.init) ?? "unavailable"); band: \(wifi.band ?? "unavailable")")
    print(
        "Transmit rate: \(wifi.transmitRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "unavailable"); "
            + "security: \(wifi.security ?? "unavailable")"
    )
}

private func runTemperatureProbe() async throws {
    let readings = try await HIDTemperatureSource().read()
    guard !readings.isEmpty else {
        print("Temperature sensors unavailable")
        return
    }
    for reading in readings {
        print(
            String(
                format: "%@: %.2f °C (%@, %d %@)",
                reading.name,
                reading.celsius,
                reading.rawName,
                reading.sampleCount,
                reading.sampleCount == 1 ? "service" : "services"
            )
        )
    }
}

private func runIOReportProbe(command: ProbeCommand, watch: Bool) async throws {
    let source = try IOReportSource()
    repeat {
        let sample = try await source.sample(over: .seconds(1))
        switch command {
        case .power:
            print(String(format: "Power sample %.3f s", sample.elapsedSeconds))
            for reading in sample.power {
                print(String(format: "  %@: %.3f W", reading.name, reading.watts))
            }
            if !sample.power.contains(where: { $0.name == "CPU" }) {
                print("  CPU: unavailable (IOReport CPU energy channels returned no value)")
            }
        case .freq:
            print(String(format: "Frequency sample %.3f s", sample.elapsedSeconds))
            let tables = await source.availableFrequencyTables()
            print(
                "  Discovered tables: "
                    + tables.map { "\($0.count) states / \(Int($0.last ?? 0)) MHz max" }.joined(separator: ", ")
            )
            for reading in sample.frequencies {
                let frequency = reading.averageMHz.map { String(format: "%.0f MHz", $0) } ?? "unavailable"
                let states = reading.states.map { $0.name }.joined(separator: ",")
                print(
                    String(
                        format: "  %@ [%@]: %@, %.1f%% active; states %@",
                        reading.name,
                        reading.kind.rawValue,
                        frequency,
                        reading.activePercent,
                        states
                    )
                )
            }
        default:
            return
        }
    } while watch
}

private func runSMCListProbe() async throws {
    let client = try SMCClient()
    for key in try await client.allKeys() {
        guard let value = try? await client.read(key) else {
            print("\(key) unavailable")
            continue
        }
        let decoded: String
        if let number = value.numericValue {
            decoded = String(format: "%.4f", number)
        } else if let string = value.stringValue {
            decoded = string
        } else {
            decoded = value.bytes.map { String(format: "%02x", $0) }.joined()
        }
        print("\(key) \(value.metadata.dataType) \(value.metadata.dataSize) \(decoded)")
    }
}

private func runSensorsProbe(watch: Bool) async throws {
    let monitor = SensorsMonitor()
    repeat {
        let sample = try await monitor.sample()
        print("Sensors at \(sample.timestamp.formatted())")
        for kind in SensorKind.allCases {
            let readings = sample.readings.filter { $0.kind == kind }
            guard !readings.isEmpty else { continue }
            print("  \(kind.rawValue):")
            for reading in readings {
                let value = SensorValueFormatter.string(
                    reading,
                    temperatureUnit: .celsius,
                    decimalPlaces: 2
                )
                print("    \(reading.name) [\(reading.source.rawValue):\(reading.rawName)]: \(value)")
            }
        }
        if !sample.sessionEnergy.isEmpty {
            print("  session energy:")
            for energy in sample.sessionEnergy {
                print(String(format: "    %@: %.3f J", energy.name, energy.joules))
            }
        }
        if watch {
            try await Task.sleep(for: .seconds(2))
        }
    } while watch
}

private func runFanProbe() async throws {
    let fans = try await SMCClient().fans()
    guard !fans.isEmpty else {
        print("Fans unavailable")
        return
    }
    for fan in fans {
        let minimum = fan.minimumRPM.map { String(format: "%.0f", $0) } ?? "unavailable"
        let maximum = fan.maximumRPM.map { String(format: "%.0f", $0) } ?? "unavailable"
        print(
            String(
                format: "%@ (F%d): %.0f RPM, min %@, max %@",
                fan.name,
                fan.id,
                fan.currentRPM,
                minimum,
                maximum
            )
        )
    }
}

private func runGeocodingProbe(query: String) async throws {
    let results = try await OpenMeteoClient().geocode(query)
    for result in results {
        let region = [result.admin, result.country].compactMap { $0 }.joined(separator: ", ")
        print("\(result.name), \(region) [\(result.latitude), \(result.longitude)] \(result.timeZone)")
    }
}

private func runWeatherProbe(latitude: Double, longitude: Double) async throws {
    let location = Location(
        id: "probe",
        name: "Probe Location",
        admin: nil,
        country: "",
        latitude: latitude,
        longitude: longitude,
        timeZone: "auto"
    )
    let client = OpenMeteoClient()
    let forecast = try await client.forecast(for: location, units: .imperial)
    let airQuality = try await client.airQuality(for: location)
    print(
        String(
            format: "Current %.1f°F, feels like %.1f°F, %@",
            forecast.current.temperature,
            forecast.current.apparentTemperature ?? forecast.current.temperature,
            forecast.current.code.description
        )
    )
    print(
        "Humidity \(format(forecast.current.humidity, suffix: "%")); "
            + "wind \(format(forecast.current.windSpeed, suffix: " mph")); "
            + "AQI \(airQuality.usAQI.map(String.init) ?? "unavailable")"
    )
    let formatter = DateFormatter()
    formatter.timeZone = forecast.timeZone
    formatter.dateFormat = "EEE MMM d"
    print("10-day forecast:")
    for day in forecast.daily {
        let high = format(day.high, suffix: "°")
        let low = format(day.low, suffix: "°")
        let precipitation = format(day.precipitationProbability, suffix: "%")
        let condition = day.code?.description ?? "Unknown"
        print("  \(formatter.string(from: day.date)): \(condition), \(high)/\(low), rain \(precipitation)")
    }
}

private func format(_ value: Double?, suffix: String) -> String {
    value.map { String(format: "%.0f%@", $0, suffix) } ?? "unavailable"
}

private func printMemorySample(_ sample: MemorySample) {
    print("Memory \(formatBytes(sample.used)) used of \(formatBytes(sample.total))")
    print(
        "app \(formatBytes(sample.app)); wired \(formatBytes(sample.wired)); "
            + "compressed \(formatBytes(sample.compressed)); cached \(formatBytes(sample.cached)); "
            + "free \(formatBytes(sample.free))"
    )
    print(
        String(
            format: "pressure %.1f%% (%@); swap %@ of %@",
            sample.pressurePercent,
            sample.pressureLevel.rawValue,
            formatBytes(sample.swapUsed),
            formatBytes(sample.swapTotal)
        )
    )
    if !sample.topProcesses.isEmpty {
        print("top processes:")
        for process in sample.topProcesses {
            print(
                String(
                    format: "  %6d  %8@  %@",
                    process.processIdentifier,
                    formatBytes(process.physicalFootprint),
                    process.name
                )
            )
        }
    }
}

private func formatBytes(_ bytes: UInt64) -> String {
    let gibibytes = Double(bytes) / 1_073_741_824
    if gibibytes >= 1 {
        return String(format: "%.2f GiB", gibibytes)
    }
    return String(format: "%.1f MiB", Double(bytes) / 1_048_576)
}

private func formatRate(_ bytesPerSecond: Double) -> String {
    if bytesPerSecond >= 1_048_576 {
        return String(format: "%.1f MiB/s", bytesPerSecond / 1_048_576)
    }
    if bytesPerSecond >= 1_024 {
        return String(format: "%.1f KiB/s", bytesPerSecond / 1_024)
    }
    return String(format: "%.0f B/s", bytesPerSecond)
}

private func writeError(_ message: String) {
    let data = Data("mbs-probe: \(message)\n".utf8)
    FileHandle.standardError.write(data)
}

@main
private enum ProbeMain {
    static func main() async {
        setbuf(stdout, nil)
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let commandName = arguments.first, let command = ProbeCommand(rawValue: commandName) else {
            writeError(
                "usage: mbs-probe <battery|cpu [--watch]|disks [--watch]|fans|freq [--watch]|geocode QUERY|"
                    + "gpu [--watch]|"
                    + "identity|"
                    + "memory|net [--watch]|power [--watch]|sensors [--watch]|smc --list|temps|time|version|"
                    + "weather --lat N --lon N|wifi>"
            )
            exit(EXIT_FAILURE)
        }

        do {
            switch command {
            case .battery:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe battery")
                    exit(EXIT_FAILURE)
                }
                try runBatteryProbe()
            case .cpu:
                guard arguments.count == 1 || arguments == ["cpu", "--watch"] else {
                    writeError("usage: mbs-probe cpu [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runCPUProbe(watch: arguments.count == 2)
            case .disks:
                guard arguments.count == 1 || arguments == ["disks", "--watch"] else {
                    writeError("usage: mbs-probe disks [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runDiskProbe(watch: arguments.count == 2)
            case .fans:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe fans")
                    exit(EXIT_FAILURE)
                }
                try await runFanProbe()
            case .freq:
                guard arguments.count == 1 || arguments == ["freq", "--watch"] else {
                    writeError("usage: mbs-probe freq [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runIOReportProbe(command: command, watch: arguments.count == 2)
            case .geocode:
                guard arguments.count >= 2 else {
                    writeError("usage: mbs-probe geocode QUERY")
                    exit(EXIT_FAILURE)
                }
                try await runGeocodingProbe(query: arguments.dropFirst().joined(separator: " "))
            case .gpu:
                guard arguments.count == 1 || arguments == ["gpu", "--watch"] else {
                    writeError("usage: mbs-probe gpu [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runGPUProbe(watch: arguments.count == 2)
            case .identity:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe identity")
                    exit(EXIT_FAILURE)
                }
                runIdentityProbe()
            case .memory:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe memory")
                    exit(EXIT_FAILURE)
                }
                try await runMemoryProbe()
            case .net:
                guard arguments.count == 1 || arguments == ["net", "--watch"] else {
                    writeError("usage: mbs-probe net [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runNetworkProbe(watch: arguments.count == 2)
            case .power:
                guard arguments.count == 1 || arguments == ["power", "--watch"] else {
                    writeError("usage: mbs-probe power [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runIOReportProbe(command: command, watch: arguments.count == 2)
            case .sensors:
                guard arguments.count == 1 || arguments == ["sensors", "--watch"] else {
                    writeError("usage: mbs-probe sensors [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runSensorsProbe(watch: arguments.count == 2)
            case .smc:
                guard arguments == ["smc", "--list"] else {
                    writeError("usage: mbs-probe smc --list")
                    exit(EXIT_FAILURE)
                }
                try await runSMCListProbe()
            case .temps:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe temps")
                    exit(EXIT_FAILURE)
                }
                try await runTemperatureProbe()
            case .time:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe time")
                    exit(EXIT_FAILURE)
                }
                try await runTimeProbe()
            case .version:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe version")
                    exit(EXIT_FAILURE)
                }
                printVersion()
            case .weather:
                guard arguments.count == 5,
                      arguments[1] == "--lat",
                      let latitude = Double(arguments[2]),
                      arguments[3] == "--lon",
                      let longitude = Double(arguments[4])
                else {
                    writeError("usage: mbs-probe weather --lat N --lon N")
                    exit(EXIT_FAILURE)
                }
                try await runWeatherProbe(latitude: latitude, longitude: longitude)
            case .wifi:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe wifi")
                    exit(EXIT_FAILURE)
                }
                try await runWiFiProbe()
            }
        } catch {
            writeError(String(describing: error))
            exit(EXIT_FAILURE)
        }
    }
}
