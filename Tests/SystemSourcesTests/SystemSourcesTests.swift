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
