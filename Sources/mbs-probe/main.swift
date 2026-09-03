import AppKit
import Foundation

private enum ProbeCommand: String {
    case identity
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

private func writeError(_ message: String) {
    let data = Data("mbs-probe: \(message)\n".utf8)
    FileHandle.standardError.write(data)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1, let command = ProbeCommand(rawValue: arguments[0]) else {
    writeError("usage: mbs-probe <identity|version>")
    exit(EXIT_FAILURE)
}

switch command {
case .identity:
    runIdentityProbe()
case .version:
    printVersion()
}
