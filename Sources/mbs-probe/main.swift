import AppKit
import Darwin
import Foundation
import MenuBarStatsCore

private enum ProbeCommand: String {
    case cpu
    case identity
    case memory
    case version
}

@MainActor
private func runIdentityProbe() {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let autosaveName = "MenuBarStats.Probe"
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = autosaveName
    statusItem.behavior = []

    guard let button = statusItem.button else {
        writeError("AppKit did not create a status item button")
        exit(EXIT_FAILURE)
    }

    button.title = ""
    button.setAccessibilityIdentifier(autosaveName)
    button.setAccessibilityLabel("Probe")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    print("autosaveName=\(autosaveName)")
    print("window.title=\(button.window?.title ?? "")")
    print("AXIdentifier=\(button.accessibilityIdentifier())")
    print("AXLabel=\(button.accessibilityLabel() ?? "")")
    print("AXTitle=\(button.accessibilityTitle() ?? "")")
    print("button.title=\(button.title)")

    NSStatusBar.system.removeStatusItem(statusItem)
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
    let monitor = CPUMonitor()
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
            writeError("usage: mbs-probe <cpu [--watch]|identity|memory|version>")
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
            case .version:
                guard arguments.count == 1 else {
                    writeError("usage: mbs-probe version")
                    exit(EXIT_FAILURE)
                }
                printVersion()
            }
        } catch {
            writeError(String(describing: error))
            exit(EXIT_FAILURE)
        }
    }
}
