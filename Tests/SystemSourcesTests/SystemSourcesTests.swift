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
