import AppKit
import MenuBarStatsCore
import SwiftUI

/// Stack composition, layout, and color settings.
///
/// A stack is one independently movable status item holding readings drawn from any module, so
/// several modules can share a slot without giving up individual positioning.
struct CombinedSettingsView: View {
    let settingsStore: SettingsStore

    private var settings: StacksSettings {
        settingsStore.settingsIncludingPendingMenuBarChanges.stacks
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: .combined))
                Text("Each enabled stack is its own menu bar item and keeps its own position.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(settings.stacks) { stack in
                stackSection(stack)
            }

            Section {
                Button {
                    addStack()
                } label: {
                    Label("Add Stack", systemImage: "plus")
                }
                if settings.stacks.isEmpty {
                    Text("No stacks yet. Add one, then choose the readings it shows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Every menu bar item shares one automatic font size, so each stack you add makes the "
                            + "others slightly smaller."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                Text("Every reading in a stack is drawn in the stack's own color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .combined, settings: settingsStore.settings)
    }

    @ViewBuilder
    private func stackSection(_ stack: StackSettings) -> some View {
        Section(stack.settingsName) {
            Toggle("Show in menu bar", isOn: settingsStore.stackVisibilityBinding(for: stack.id))
            TextField("Name", text: stackBinding(stack.id, \.name), prompt: Text(stack.defaultName))
            Picker("Layout", selection: stackBinding(stack.id, \.layout)) {
                Text("Two rows per column").tag(StackLayout.columns)
                Text("One row").tag(StackLayout.singleRow)
            }
            Toggle(
                "Hide the individual items it replaces",
                isOn: settingsStore.stackHidesSourceItemsBinding(for: stack.id)
            )

            ForEach(Array(stack.metrics.enumerated()), id: \.offset) { index, metric in
                HStack {
                    Label(metric.displayName, systemImage: metric.module.symbolName)
                    Spacer()
                    Button {
                        move(stack.id, index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    Button {
                        move(stack.id, index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == stack.metrics.count - 1)
                    Button(role: .destructive) {
                        removeMetric(stack.id, at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if stack.metrics.isEmpty {
                Text("No readings yet. Add the first one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu("Add Reading") {
                ForEach(StackMetric.byModule, id: \.module) { group in
                    Menu(group.module.settingsTitle) {
                        ForEach(group.metrics, id: \.self) { metric in
                            Button(metric.displayName) { addMetric(stack.id, metric) }
                        }
                    }
                }
            }

            Button(role: .destructive) {
                deleteStack(stack.id)
            } label: {
                Label("Delete \(stack.settingsName)", systemImage: "trash")
            }
        }
    }

    // MARK: - Mutation

    private func addStack() {
        var appSettings = settingsStore.settings
        // Ids come from a saved high-water mark, so a new stack never reuses a deleted stack's
        // autosave name and therefore never inherits its saved menu bar position. The stack starts
        // empty and hidden, and its visibility is staged like a new Sensors widget.
        let id = appSettings.stacks.allocateID()
        appSettings.stacks.stacks.append(StackSettings(id: id, isEnabled: false, metrics: []))
        settingsStore.settings = appSettings
        settingsStore.stageStackVisibility(true, for: id)
        settingsStore.stageMenuBarVisibility(true, for: .combined)
    }

    private func deleteStack(_ id: Int) {
        var appSettings = settingsStore.settings
        appSettings.stacks.remove(id: id)
        settingsStore.settings = appSettings
        settingsStore.forgetStack(id)
    }

    private func addMetric(_ id: Int, _ metric: StackMetric) {
        mutateMetrics(id) { $0.append(metric) }
    }

    private func removeMetric(_ id: Int, at index: Int) {
        mutateMetrics(id) { metrics in
            guard metrics.indices.contains(index) else { return }
            metrics.remove(at: index)
        }
    }

    private func move(_ id: Int, _ index: Int, by offset: Int) {
        mutateMetrics(id) { metrics in
            let target = index + offset
            guard metrics.indices.contains(index), metrics.indices.contains(target) else { return }
            metrics.swapAt(index, target)
        }
    }

    /// Readings are staged, because which modules a stack replaces decides the visible item set.
    private func mutateMetrics(_ id: Int, _ change: (inout [StackMetric]) -> Void) {
        var metrics = settingsStore.stackMetrics(for: id)
        change(&metrics)
        settingsStore.stageStackMetrics(metrics, for: id)
    }

    private func mutate(_ id: Int, _ change: (inout StackSettings) -> Void) {
        var appSettings = settingsStore.settings
        guard let index = appSettings.stacks.stacks.firstIndex(where: { $0.id == id }) else { return }
        change(&appSettings.stacks.stacks[index])
        settingsStore.settings = appSettings
    }

    private func stackBinding<Value>(
        _ id: Int,
        _ keyPath: WritableKeyPath<StackSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settingsStore.settings.stacks.stack(id: id)?[keyPath: keyPath]
                    ?? StackSettings(id: id)[keyPath: keyPath]
            },
            set: { value in mutate(id) { $0[keyPath: keyPath] = value } }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: {
                let moduleSettings = settingsStore.settings.modules[.combined] ?? ModuleSettings()
                return Color(nsColor: NSColor(hex: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor)
            },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                var appSettings = settingsStore.settings
                var moduleSettings = appSettings.modules[.combined] ?? ModuleSettings()
                moduleSettings[keyPath: keyPath] = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                appSettings.modules[.combined] = moduleSettings
                settingsStore.settings = appSettings
            }
        )
    }
}
