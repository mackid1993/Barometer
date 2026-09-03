import AppKit
import MenuBarStatsCore
import SwiftUI

/// Owns and presents the MenuBarStats settings window.
@MainActor
public final class SettingsWindowController: NSWindowController {
    /// Creates the settings window controller.
    public convenience init() {
        let rootView = SettingsRootView()
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MenuBarStats Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 440))
        window.minSize = NSSize(width: 580, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    /// Brings the settings window to the front.
    public func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private enum SettingsSelection: Hashable {
    case general
    case module(ModuleID)

    var title: String {
        switch self {
        case .general: "General"
        case let .module(module): module.displayName
        }
    }
}

private struct SettingsRootView: View {
    @State private var selection: SettingsSelection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("General")
                    .tag(SettingsSelection.general)

                Section("Modules") {
                    ForEach(ModuleID.allCases, id: \.self) { module in
                        Text(module.displayName)
                            .tag(SettingsSelection.module(module))
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                Text((selection ?? .general).title)
                    .font(.title2.weight(.semibold))
                Text("Settings for this section will be added in a later phase.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}
