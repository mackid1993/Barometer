import AppKit
import MenuBarStatsCore

extension InterfaceAppearance {
    /// Applies this choice to the whole application.
    ///
    /// Setting `NSApp.appearance` changes the Settings window, the dropdown panels, and the
    /// appearance the status item buttons report, so colored menu bar marks pick their light or
    /// dark variant from the same choice. System restores the default, which follows macOS.
    @MainActor
    public func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
