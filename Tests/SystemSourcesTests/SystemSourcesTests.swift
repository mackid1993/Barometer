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
    let readings = try await HIDTemperatureSource().read()

    #expect(!readings.isEmpty)
    #expect(readings.allSatisfy { $0.celsius > 0 && $0.celsius <= 125 })
    #expect(Set(readings.map(\.rawName)).count == readings.count)
}
