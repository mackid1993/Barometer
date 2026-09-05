import Darwin
import Foundation
@testable import MenuBarStatsCore

/// Deterministic storage workload. Never creates status items or accesses hardware/preferences.
@main
struct MemoryHistoryBenchmark {
    @MainActor
    static func main() throws {
        let seconds = Int(CommandLine.arguments.dropFirst().first ?? "3600") ?? 3_600
        #if COMPACT_HISTORY
        let capacities: [Int] = [ModuleID.cpu, .memory, .gpu, .network, .disks, .sensors, .battery]
            .map { GraphHistoryRetention.capacity(for: $0) }
        let mode = "compact"
        #else
        let capacities = [86_400, 43_200, 86_400, 86_400, 86_400, 28_800, 8_640]
        let mode = "baseline"
        #endif
        let cpu = ModuleStore<CPUSample>(historyCapacity: capacities[0])
        let memory = ModuleStore<MemorySample>(historyCapacity: capacities[1])
        let gpu = ModuleStore<GPUSample>(historyCapacity: capacities[2])
        let network = ModuleStore<NetworkSample>(historyCapacity: capacities[3])
        let disk = ModuleStore<DiskSample>(historyCapacity: capacities[4])
        let sensors = ModuleStore<SensorSample>(historyCapacity: capacities[5])
        let battery = ModuleStore<BatterySample>(historyCapacity: capacities[6])
        report(mode: mode, seconds: 0, retained: 0)
        for second in 1...max(1, seconds) {
            let date = Date(timeIntervalSince1970: Double(second))
            let sample = CPUSample(
                timestamp: date, totalPercent: Double(second % 100), userPercent: 20, systemPercent: 10,
                idlePercent: 70, nicePercent: 0,
                perCore: (0..<14).map { CPUCoreSample(index: $0, kind: .unknown, usagePercent: Double(second % 100)) },
                loadAverages: [Double(second % 10), 2, 3], uptime: Double(second), processCount: 500,
                threadCount: 2_000, topProcesses: (0..<5).map {
                    CPUProcessSample(processIdentifier: Int32($0), name: "Process \($0)", path: "/usr/bin/process\($0)",
                                     cpuPercent: Double(second % 20), userIdentifier: 501)
                }
            )
            cpu.receive(sample, at: date)
            network.receive(NetworkSample(
                timestamp: date, interfaces: (0..<16).map {
                    NetworkInterfaceSample(
                        name: "en\($0)", isUp: true, isLoopback: false, isVPN: false,
                        ipv4Addresses: ["192.0.2.\($0)"], ipv6Addresses: [],
                        downloadBytesPerSecond: Double(second), uploadBytesPerSecond: Double(second / 2),
                        receivedBytes: UInt64(second * 1_000), sentBytes: UInt64(second * 500),
                        inputErrors: 0, outputErrors: 0
                    )
                }, primaryInterface: "en0", router: "192.0.2.1", dnsServers: ["192.0.2.53"], wifi: nil, publicIP: nil
            ), at: date)
            if second % 5 == 0 {
                sensors.receive(SensorSample(
                    timestamp: date, readings: (0..<300).map {
                        SensorReading(
                            id: "smc:temperature:\($0)", name: "Temperature sensor \($0)", shortName: "T\($0)",
                            rawName: "Hardware temperature sensor \($0)", kind: .temperature, source: .smc,
                            value: Double(second % 80 + $0 % 10), unit: .celsius
                        )
                    }, sessionEnergy: []
                ), at: date)
            }
            if [360, 3_600, 86_400, 172_800].contains(second) || second == seconds {
                report(mode: mode, seconds: second,
                       retained: cpu.history.count + sensors.history.count + network.history.count)
            }
        }
        // Keep every store alive through the final measurement, including empty eager baseline buffers.
        withExtendedLifetime((cpu, memory, gpu, network, disk, sensors, battery)) {}
    }

    private static func report(mode: String, seconds: Int, retained: Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            print("Memory measurement failed: \(result)")
            exit(1)
        }
        print("\(mode) seconds=\(seconds) footprint_bytes=\(info.phys_footprint) retained_samples=\(retained)")
    }
}
