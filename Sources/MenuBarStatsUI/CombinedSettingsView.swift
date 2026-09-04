import AppKit
import MenuBarStatsCore
import SwiftUI

/// Ordered membership, separator, visibility, and color settings for Combined.
struct CombinedSettingsView: View {
    let settingsStore: SettingsStore

    private var settings: CombinedSettings { settingsStore.settings.combined }

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: moduleBinding(\.isEnabled))
                Toggle("Hide included individual items", isOn: combinedBinding(\.hidesIndividualMembers))
                Text("Hidden member items remain allocated and keep their saved menu bar positions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Included Modules") {
                ForEach(Array(settings.members.enumerated()), id: \.element) { index, module in
                    HStack {
                        Label(module.displayName, systemImage: module.symbolName)
                        Spacer()
                        Button {
                            move(index, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button {
                            move(index, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == settings.members.count - 1)
                        Button(role: .destructive) {
                            remove(module)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add Module") {
                    ForEach(availableModules, id: \.self) { module in
                        Button(module.displayName) { add(module) }
                    }
                }
                .disabled(availableModules.isEmpty)
            }
            Section("Appearance") {
                Toggle("Show separators", isOn: combinedBinding(\.showsSeparators))
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .combined, settings: settingsStore.settings)
    }

    private var availableModules: [ModuleID] {
        ModuleID.allCases.filter { $0 != .combined && !settings.members.contains($0) }
    }

    private func add(_ module: ModuleID) {
        var appSettings = settingsStore.settings
        appSettings.combined.members.append(module)
        appSettings.combined.normalize()
        settingsStore.settings = appSettings
    }

    private func remove(_ module: ModuleID) {
        var appSettings = settingsStore.settings
        appSettings.combined.members.removeAll { $0 == module }
        settingsStore.settings = appSettings
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard settings.members.indices.contains(index), settings.members.indices.contains(destination) else { return }
        var appSettings = settingsStore.settings
        appSettings.combined.members.swapAt(index, destination)
        settingsStore.settings = appSettings
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.modules[.combined]?[keyPath: keyPath] ?? ModuleSettings()[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                var moduleSettings = appSettings.modules[.combined] ?? ModuleSettings(mode: "members")
                moduleSettings[keyPath: keyPath] = value
                appSettings.modules[.combined] = moduleSettings
                settingsStore.settings = appSettings
            }
        )
    }

    private func combinedBinding<Value>(_ keyPath: WritableKeyPath<CombinedSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.combined[keyPath: keyPath] },
            set: { value in
                var appSettings = settingsStore.settings
                appSettings.combined[keyPath: keyPath] = value
                settingsStore.settings = appSettings
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: {
                let value = settingsStore.settings.modules[.combined]?[keyPath: keyPath] ?? "#2F7CF6"
                return Color(nsColor: NSColor(hex: value) ?? .controlAccentColor)
            },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                var appSettings = settingsStore.settings
                var moduleSettings = appSettings.modules[.combined] ?? ModuleSettings(mode: "members")
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
