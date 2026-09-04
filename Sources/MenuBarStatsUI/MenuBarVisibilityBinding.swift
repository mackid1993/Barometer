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

    /// A staged binding for an independently movable stack.
    func stackVisibilityBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { self.stackVisibility(for: id) },
            set: { self.stageStackVisibility($0, for: id) }
        )
    }

    /// A staged binding for whether a stack replaces the items it draws from.
    func stackHidesSourceItemsBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { self.stackHidesSourceItems(for: id) },
            set: { self.stageStackHidesSourceItems($0, for: id) }
        )
    }
}
