import Foundation
import Testing
@testable import SystemSources

@Test func systemSourcesLayerLoads() {
    #expect(SystemSourcesAvailability.isAvailable)
}

@Test func processMetadataResolvesContainingApplication() throws {
    let applicationURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("BarometerProcessTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Parallels Desktop.app", isDirectory: true)
    let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
    let executableURL = contentsURL
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("prl_vm_app", isDirectory: false)
    try FileManager.default.createDirectory(
        at: executableURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let info: [String: Any] = [
        "CFBundleIdentifier": "com.parallels.desktop.console",
        "CFBundleName": "Parallels Desktop",
    ]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)

    #expect(ProcessSource.applicationBundleURL(forExecutablePath: executableURL.path) == applicationURL)
    #expect(ProcessSource.applicationDisplayName(forExecutablePath: executableURL.path) == "Parallels Desktop")
}

@Test func processNetworkSourceParsesQuotedNamesAndAggregatesDuplicateRows() throws {
    let output = """
    ,bytes_in,bytes_out,
    "Example, Helper.42",100,20,
    "Example, Helper.42",25,5,
    Browser.81,900,120,
    invalid,1,2,
    """

    let counters = ProcessNetworkSource.parse(output)
    let helper = try #require(counters.first { $0.processIdentifier == 42 })

    #expect(helper.fallbackName == "Example, Helper")
    #expect(helper.receivedBytes == 125)
    #expect(helper.sentBytes == 25)
    #expect(counters.first { $0.processIdentifier == 81 }?.receivedBytes == 900)
    #expect(counters.count == 2)
}

@Test func networkSourceReadsRouteInterfaces() throws {
    let snapshot = try NetworkSource().read()

    #expect(!snapshot.interfaces.isEmpty)
    #expect(snapshot.interfaces.contains { $0.name == "lo0" && $0.isLoopback })
    #expect(snapshot.interfaces.allSatisfy { !$0.name.isEmpty && $0.index > 0 })
}

@Test func publicIPSourceParsesAndValidatesAddresses() {
    let data = Data(#"{"ip":"203.0.113.4"}"#.utf8)

    #expect(PublicIPSource.address(from: data) == "203.0.113.4")
    #expect(PublicIPSource.isValid(address: "203.0.113.4", family: AF_INET))
    #expect(PublicIPSource.isValid(address: "2001:db8::1", family: AF_INET6))
    #expect(!PublicIPSource.isValid(address: "not-an-address", family: AF_INET))
}

@Test func diskSourceReadsMountedVolumesAndPhysicalCounters() throws {
    let snapshot = try DiskSource().read()

    #expect(snapshot.volumes.contains { $0.mountPoint == "/" && $0.totalBytes > 0 })
    #expect(snapshot.volumes.allSatisfy { $0.usedBytes + $0.availableBytes == $0.totalBytes })
    #expect(snapshot.devices.allSatisfy { !$0.bsdName.isEmpty })
}

@Test func diskVolumeClassificationKeepsNetworkVolumesDistinct() {
    #expect(DiskSource.volumeKind(isLocal: false, isInternal: false) == .network)
    #expect(DiskSource.volumeKind(isLocal: true, isInternal: true) == .internalDisk)
    #expect(DiskSource.volumeKind(isLocal: true, isInternal: false) == .externalDisk)
    #expect(DiskSource.bsdName(fromMountSource: "/dev/disk3s3s1") == "disk3s3s1")
    #expect(DiskSource.bsdName(fromMountSource: "map auto_home") == nil)
}

@Test func hidTemperatureSourceNormalizesFiltersAndAveragesReadings() {
    let readings = HIDTemperatureSource.readings(
        from: [
            "PMU tdie3": [48, 54, -9_199, .nan],
            "gas gauge battery": [31.5],
            "NAND CH0 temp": [34],
            "PMU tcal": [51.75],
            "invalid": [-1, 0, 126, .infinity],
        ]
    )

    #expect(readings.count == 4)
    #expect(readings.first { $0.rawName == "PMU tdie3" }?.name == "SoC die 3")
    #expect(readings.first { $0.rawName == "PMU tdie3" }?.celsius == 51)
    #expect(readings.first { $0.rawName == "PMU tdie3" }?.sampleCount == 2)
    #expect(readings.first { $0.rawName == "gas gauge battery" }?.name == "Battery")
    #expect(readings.first { $0.rawName == "NAND CH0 temp" }?.name == "SSD")
    #expect(readings.first { $0.rawName == "PMU tcal" }?.name == "PMU")
    #expect(!readings.contains { $0.rawName == "invalid" })
}

@Test func hidTemperatureSourceReadsValidHardwareSensors() async throws {
    let source = HIDTemperatureSource()
    guard await source.isAvailable else {
        return
    }
    let readings = try await source.read()

    #expect(!readings.isEmpty)
    #expect(readings.allSatisfy { $0.celsius > 0 && $0.celsius <= 125 })
    #expect(Set(readings.map(\.rawName)).count == readings.count)
}

@Test func ioReportConvertsEnergyUnitsUsingTheMeasuredInterval() {
    #expect(IOReportSource.watts(energy: 2, unit: "J", elapsedSeconds: 0.5) == 4)
    #expect(IOReportSource.watts(energy: 2_000, unit: "mJ", elapsedSeconds: 0.5) == 4)
    #expect(IOReportSource.watts(energy: 2_000_000, unit: "uJ", elapsedSeconds: 0.5) == 4)
    #expect(IOReportSource.watts(energy: 2_000_000_000, unit: "nJ", elapsedSeconds: 0.5) == 4)
    #expect(IOReportSource.watts(energy: 1, unit: "unknown", elapsedSeconds: 1) == nil)
}

@Test func ioReportNormalizesDynamicFrequencyTableWithoutDroppingStates() {
    let values: [UInt32] = [600_000, 600_000, 1_470_000]
    let bytes = values.flatMap { frequency in
        withUnsafeBytes(of: frequency.littleEndian) { Array($0) }
            + withUnsafeBytes(of: UInt32(800).littleEndian) { Array($0) }
    }

    #expect(IOReportSource.normalizedFrequencyTable(data: Data(bytes)) == [600, 600, 1_470])
}

@Test func ioReportFrequencyExcludesIdleResidencyAndWeightsActiveStates() {
    let states = [
        IOReportStateReading(name: "DOWN", residency: 10),
        IOReportStateReading(name: "IDLE", residency: 20),
        IOReportStateReading(name: "P1", residency: 30),
        IOReportStateReading(name: "P2", residency: 40),
    ]
    let result = IOReportSource.frequency(states: states, candidates: [[1_000, 2_000]], kind: .lowerCPU)

    #expect(result.averageMHz == 11_000.0 / 7.0)
    #expect(result.activePercent == 70)
}

@Test func ioReportRecognizesAggregateCPUEnergyNamesWithoutCoreCounts() {
    for name in ["CPU Energy", "DIE0 CPU Energy", "EACC_CPU", "PACC12_CPU", "MCPU0", "SCPU"] {
        #expect(IOReportSource.isCPUEnergyChannel(name))
    }
    for name in ["EACC_CPU0", "PACC_0", "MCPU0_0", "PCPM", "GPU Energy"] {
        #expect(!IOReportSource.isCPUEnergyChannel(name))
    }
}

@Test func ioReportReadsRuntimeDiscoveredChannels() async throws {
    guard IOReportSource.isAvailable else {
        return
    }
    let source = try IOReportSource()
    let snapshot = try await source.sample(over: .milliseconds(50))

    #expect(snapshot.elapsedSeconds > 0)
    #expect(!snapshot.energy.isEmpty)
    #expect(!snapshot.frequencies.isEmpty)
    #expect(snapshot.power.allSatisfy { $0.watts >= 0 && $0.watts.isFinite })
    #expect(snapshot.frequencies.allSatisfy { (0...100).contains($0.activePercent) })
    #expect(snapshot.temperatures.allSatisfy { (10...125).contains($0.celsius) })
}

@Test func ioReportNormalizesTemperatureGaugeScales() {
    #expect(IOReportSource.normalizedTemperature(54) == 54)
    #expect(IOReportSource.normalizedTemperature(54_250) == 54.25)
    #expect(IOReportSource.normalizedTemperature(5_425) == 54.25)
    #expect(IOReportSource.normalizedTemperature(Int64.min) == nil)
}

@Test func gpuAcceleratorParsesPublishedStatisticsWithoutModelAssumptions() throws {
    let snapshot = try #require(
        GPUAcceleratorSource.snapshot(
            name: "Test GPU",
            statistics: [
                "Device Utilization %": 42,
                "Renderer Utilization %": 39,
                "Tiler Utilization %": 17,
                "In use system memory": 1_000,
                "Alloc system memory": 2_000,
                "In use system memory (driver)": 250,
            ]
        )
    )

    #expect(snapshot.name == "Test GPU")
    #expect(snapshot.deviceUtilizationPercent == 42)
    #expect(snapshot.rendererUtilizationPercent == 39)
    #expect(snapshot.memoryInUseBytes == 1_000)
    #expect(snapshot.memoryAllocatedBytes == 2_000)
}

@Test func gpuAcceleratorReadsLivePerformanceStatistics() throws {
    let source = GPUAcceleratorSource()
    guard source.isAvailable else {
        return
    }
    let snapshots = try source.read()

    #expect(!snapshots.isEmpty)
    #expect(snapshots.allSatisfy { (0...100).contains($0.deviceUtilizationPercent) })
}

@Test func smcDecodesIntegerFloatAndFixedPointTypes() {
    #expect(SMCClient.decodeNumeric(bytes: [0x2a], dataType: "ui8 ") == 42)
    #expect(SMCClient.decodeNumeric(bytes: [0x12, 0x34], dataType: "ui16") == 4_660)
    #expect(SMCClient.decodeNumeric(bytes: [0, 0, 0x0d, 0x86], dataType: "ui32") == 3_462)
    #expect(SMCClient.decodeNumeric(bytes: [0xff], dataType: "si8 ") == -1)
    #expect(SMCClient.decodeNumeric(bytes: [0xff, 0xfe], dataType: "si16") == -2)
    #expect(SMCClient.decodeNumeric(bytes: [0xff, 0xff, 0xff, 0xfd], dataType: "si32") == -3)
    #expect(SMCClient.decodeNumeric(bytes: [0, 0, 0x18, 0x41], dataType: "flt ") == 9.5)
    #expect(SMCClient.decodeNumeric(bytes: [0, 0, 0x18, 0x41], dataType: "iof ") == 9.5)
    #expect(SMCClient.decodeNumeric(bytes: [0, 0, 0x02, 0, 0, 0, 0, 0], dataType: "ioft") == 2)
    #expect(SMCClient.decodeNumeric(bytes: [0, 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], dataType: "ioft") == -1)
    #expect(SMCClient.decodeNumeric(bytes: [0x13, 0x88], dataType: "fpe2") == 1_250)
    #expect(SMCClient.decodeNumeric(bytes: [0x19, 0x80], dataType: "sp78") == 25.5)
    #expect(SMCClient.decodeNumeric(bytes: [0xfe, 0x80], dataType: "sp78") == -1.5)
    #expect(SMCClient.decodeNumeric(bytes: [0x06, 0x00], dataType: "fp2e") == 0.09375)
}

@Test func smcDecodesFourCharacterKeysAndDescriptions() {
    let code = SMCClient.code(for: "F0Ac")

    #expect(code.map(SMCClient.key(from:)) == "F0Ac")
    #expect(SMCClient.code(for: "bad") == nil)
    #expect(SMCClient.decodeString(bytes: [0, 0, 0, 0] + Array("Left fan\0".utf8), dataType: "{fds") == "Left fan")
}

@Test func smcEnumeratesKeysAndReadsFans() async throws {
    guard SMCClient.isAvailable else {
        return
    }
    let client = try SMCClient()
    let keys = try await client.allKeys()
    let fans = try await client.fans()

    #expect(keys.count > 100)
    #expect(keys.contains("#KEY"))
    #expect(fans.allSatisfy { $0.currentRPM >= 0 })
}
