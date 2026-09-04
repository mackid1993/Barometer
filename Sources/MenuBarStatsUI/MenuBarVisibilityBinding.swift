import MenuBarStatsCore
import SwiftUI

extension SettingsStore {
    /// A staged binding for a module's menu bar visibility.
    func menuBarVisibilityBinding(for module: ModuleID) -> Binding<Bool> {
        Binding(
            get: { self.menuBarVisibility(for: module) },
            set: { self.stageMenuBarVisibility($0, for: module) }
        )
    }

    /// A staged binding for an independently movable Sensors widget.
    func sensorWidgetVisibilityBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { self.sensorWidgetVisibility(for: id) },
            set: { self.stageSensorWidgetVisibility($0, for: id) }
        )
    }
}
