import Darwin
import Foundation
import MenuBarStatsCore

private enum ProbeCommand: String {
    case cpu
    case geocode
    case identity
    case memory
    case net
    case version
    case weather
    case wifi
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
                "usage: mbs-probe <cpu [--watch]|geocode QUERY|identity|memory|net [--watch]|version|"
                    + "weather --lat N --lon N|wifi>"
            )
            exit(EXIT_FAILURE)
        }

        do {
            switch command {
            case .cpu:
                guard arguments.count == 1 || arguments == ["cpu", "--watch"] else {
                    writeError("usage: mbs-probe cpu [--watch]")
                    exit(EXIT_FAILURE)
                }
                try await runCPUProbe(watch: arguments.count == 2)
            case .geocode:
                guard arguments.count >= 2 else {
                    writeError("usage: mbs-probe geocode QUERY")
                    exit(EXIT_FAILURE)
                }
                try await runGeocodingProbe(query: arguments.dropFirst().joined(separator: " "))
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
