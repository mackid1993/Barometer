import AppKit
import MenuBarStatsCore
import OSLog
import Observation
import SwiftUI

/// Owns and presents the MenuBarStats settings window.
///
/// The controller is meant to live only while its window is open. When the window closes the
/// controller invokes ``windowCloseHandler`` so the owner can drop its reference, which releases
/// the window, the hosting view, and the SwiftUI tree behind it, and then schedules a malloc
/// pressure relief pass so the freed pages leave the process footprint.
@MainActor
public final class SettingsWindowController: NSWindowController {
    private nonisolated static let logger = Logger(subsystem: "com.barometer.app", category: "settings")

    /// Called from the window's will-close notification, before the controller is released.
    ///
    /// Owners should use this to drop their strong reference to the controller. Store only weak
    /// captures in the closure; the controller keeps it for its whole lifetime.
    public var windowCloseHandler: (@MainActor () -> Void)?

    private var navigationModel: SettingsNavigationModel?

    /// Creates the settings window controller.
    public convenience init(
        settingsStore: SettingsStore,
        gpuStore: ModuleStore<GPUSample>,
        batteryStore: ModuleStore<BatterySample>,
        timeStore: ModuleStore<TimeSample>,
        networkStore: ModuleStore<NetworkSample>,
        diskStore: ModuleStore<DiskSample>,
        sensorStore: ModuleStore<SensorSample>,
        calendarAccessAction: @escaping @MainActor () -> Void,
        applyMenuBarChangesAction: @escaping @MainActor () -> Void
    ) {
        let navigationModel = SettingsNavigationModel()
        let rootView = SettingsRootView(
            settingsStore: settingsStore,
            gpuStore: gpuStore,
            batteryStore: batteryStore,
            timeStore: timeStore,
            networkStore: networkStore,
            diskStore: diskStore,
            sensorStore: sensorStore,
            calendarAccessAction: calendarAccessAction,
            applyMenuBarChangesAction: applyMenuBarChangesAction,
            navigationModel: navigationModel
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Barometer Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 780, height: 580))
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        // Restore the last saved frame so a reopened window lands where the user left it.
        window.setFrameAutosaveName("BarometerSettings")
        self.init(window: window)
        self.navigationModel = navigationModel
        window.delegate = self
    }

    deinit {
        Self.logger.debug("Settings window controller deallocated")
    }

    /// Brings the settings window to the front.
    public func show(module: ModuleID? = nil) {
        navigationModel?.open(module: module)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    /// Lets the owner drop the controller, then asks libmalloc to return the freed pages.
    public func windowWillClose(_ notification: Notification) {
        Self.logger.debug("Settings window closing; releasing controller")
        windowCloseHandler?()
        windowCloseHandler = nil
        MemoryReclaim.scheduleRelief()
    }
}

enum SettingsSelection: Hashable {
    case general
    case module(ModuleID)
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .module(let module): module.settingsTitle
        case .about: "About"
        }
    }
}

@MainActor
@Observable
final class SettingsNavigationModel {
    var selection: SettingsSelection? = .general

    func open(module: ModuleID?) {
        selection = module.map(SettingsSelection.module) ?? .general
    }
}

private struct SettingsRootView: View {
    let settingsStore: SettingsStore
    let gpuStore: ModuleStore<GPUSample>
    let batteryStore: ModuleStore<BatterySample>
    let timeStore: ModuleStore<TimeSample>
    let networkStore: ModuleStore<NetworkSample>
    let diskStore: ModuleStore<DiskSample>
    let sensorStore: ModuleStore<SensorSample>
    let calendarAccessAction: @MainActor () -> Void
    let applyMenuBarChangesAction: @MainActor () -> Void
    @Bindable var navigationModel: SettingsNavigationModel

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationModel.selection) {
                SettingsSidebarRow(
                    symbolName: "gearshape.fill",
                    title: "General",
                    accent: ModuleAccent(primary: Color(hex: 0x64748B), secondary: Color(hex: 0x94A3B8))
                )
                .tag(SettingsSelection.general)

                Section("Modules") {
                    ForEach(ModuleID.allCases, id: \.self) { module in
                        SettingsSidebarRow(
                            symbolName: module.symbolName,
                            title: module.settingsTitle,
                            accent: ModuleAccent.resolve(settingsStore.settings, module: module)
                        )
                        .tag(SettingsSelection.module(module))
                    }
                }

                SettingsSidebarRow(
                    symbolName: "info.circle.fill",
                    title: "About Barometer",
                    accent: ModuleAccent(primary: Color(hex: 0x2F7CF6), secondary: Color(hex: 0x6BA4FF))
                )
                .tag(SettingsSelection.about)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch navigationModel.selection ?? .general {
                    case .general:
                        GeneralSettingsView(settingsStore: settingsStore)
                    case .module(.cpu):
                        ModuleSettingsView(module: .cpu, settingsStore: settingsStore)
                    case .module(.memory):
                        ModuleSettingsView(module: .memory, settingsStore: settingsStore)
                    case .module(.gpu):
                        GPUSettingsView(store: gpuStore, settingsStore: settingsStore)
                    case .module(.battery):
                        BatterySettingsView(settingsStore: settingsStore)
                    case .module(.time):
                        TimeSettingsView(
                            store: timeStore,
                            settingsStore: settingsStore,
                            requestCalendarAccess: calendarAccessAction
                        )
                    case .module(.combined):
                        CombinedSettingsView(settingsStore: settingsStore)
                    case .module(.weather):
                        WeatherSettingsView(settingsStore: settingsStore)
                    case .module(.network):
                        NetworkSettingsView(store: networkStore, settingsStore: settingsStore)
                    case .module(.disks):
                        DiskSettingsView(store: diskStore, settingsStore: settingsStore)
                    case .module(.sensors):
                        SensorSettingsView(store: sensorStore, settingsStore: settingsStore)
                    case .about:
                        AboutSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if settingsStore.hasPendingMenuBarChanges {
                    PendingMenuBarChangesBar(
                        previewSettings: settingsStore.settingsIncludingPendingMenuBarChanges,
                        applyAction: applyMenuBarChangesAction,
                        discardAction: settingsStore.discardPendingMenuBarChanges
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: settingsStore.hasPendingMenuBarChanges)
        }
    }
}
