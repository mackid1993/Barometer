import AppKit
import MenuBarStatsCore
import SwiftUI

/// Settings for Sensors discovery, formatting, and independently movable status items.
public struct SensorSettingsView: View {
    private let store: ModuleStore<SensorSample>
    private let settingsStore: SettingsStore

    /// Creates Sensors settings backed by live discovered readings.
    public init(store: ModuleStore<SensorSample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Show Sensors in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: .sensors))
                let count = store.latestSample?.readings.count ?? 0
                LabeledContent("Live readings", value: count == 0 ? "Discovering…" : "\(count)")
            }

            Section("Formatting") {
                Picker("Temperature", selection: appBinding(\.sensorTemperatureUnit)) {
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                }
                Picker("Graph style", selection: moduleBinding(\.graphStyle)) {
                    Text("Line").tag(GraphStyle.line)
                    Text("Area").tag(GraphStyle.area)
                    Text("Bars").tag(GraphStyle.bars)
                }
                Stepper(value: sensorBinding(\.decimalPlaces), in: 0...2) {
                    Text("Decimal places: \(settingsStore.settings.sensors.decimalPlaces)")
                }
                Toggle("Show advanced firmware sensors", isOn: sensorBinding(\.showsRawNames))
                if settingsStore.settings.sensors.showsRawNames {
                    Text("Includes undocumented SMC identifiers intended for diagnostics and hardware reports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Hide equivalent readings", isOn: sensorBinding(\.hidesDuplicates))
            }

            Section("Menu Bar Widgets") {
                ForEach(settingsStore.settings.sensors.widgets) { widget in
                    DisclosureGroup("Widget \(widget.id)") {
                        Toggle("Visible", isOn: settingsStore.sensorWidgetVisibilityBinding(for: widget.id))
                        Picker("Display", selection: widgetBinding(widget.id, \.mode)) {
                            ForEach(SensorWidgetMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        if widget.sensorIDs.isEmpty {
                            Text("Select at least one reading below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(widget.sensorIDs.enumerated()), id: \.element) { index, sensorID in
                            HStack {
                                Text(readingName(sensorID)).lineLimit(1)
                                Spacer()
                                Button {
                                    moveReading(widgetID: widget.id, from: index, offset: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(index == 0)
                                .buttonStyle(.plain)
                                Button {
                                    moveReading(widgetID: widget.id, from: index, offset: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .disabled(index == widget.sensorIDs.count - 1)
                                .buttonStyle(.plain)
                                Button {
                                    removeReading(sensorID, widgetID: widget.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                        }

                        Menu("Add Reading") {
                            ForEach(SensorKind.allCases, id: \.self) { kind in
                                let choices = availableReadings.filter {
                                    $0.kind == kind && !widget.sensorIDs.contains($0.id)
                                }
                                if !choices.isEmpty {
                                    Menu(kind.title) {
                                        ForEach(choices) { reading in
                                            Button(reading.name) { addReading(reading.id, widgetID: widget.id) }
                                        }
                                    }
                                }
                            }
                        }
                        if widget.id > 1 {
                            Button("Remove Widget", role: .destructive) { disableWidget(widget.id) }
                        }
                    }
                }
                Button {
                    addWidget()
                } label: {
                    Label("Add Movable Widget", systemImage: "plus")
                }
                Text("Each widget is a separate menu bar item and can be moved independently with Command-drag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sampling") {
                HStack {
                    Text("Interval")
                    Slider(value: moduleBinding(\.interval), in: 5...30, step: 1)
                    Text("\(Int(moduleSettings.interval)) s")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                Text("A five-second minimum keeps private hardware polling energy-efficient.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SamplingIntervalNote()
            }

            Section("Menu Bar Colors") {
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
                if settingsStore.settings.usesGlobalColors {
                    Text("The global palette in General is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if settingsStore.settings.isMonochrome {
                    Text("Turn off Monochrome menu bar in General to display colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .sensors, settings: settingsStore.settings)
    }

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.sensors] ?? ModuleSettings(mode: "compactStack", interval: 5)
    }

    private var availableReadings: [SensorReading] {
        let settings = settingsStore.settings.sensors
        return store.latestSample?.displayReadings(
            hidesDuplicates: settings.hidesDuplicates,
            showsRawNames: settings.showsRawNames
        ) ?? []
    }

    private func readingName(_ id: String) -> String {
        store.latestSample?.reading(id: id)?.name ?? id
    }

    private func appBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                var settings = settingsStore.settings
                settings[keyPath: keyPath] = value
                settingsStore.settings = settings
            }
        )
    }

    private func sensorBinding<Value>(_ keyPath: WritableKeyPath<SensorSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.sensors[keyPath: keyPath] },
            set: { value in
                var settings = settingsStore.settings
                settings.sensors[keyPath: keyPath] = value
                settingsStore.settings = settings
            }
        )
    }

    private func moduleBinding<Value>(_ keyPath: WritableKeyPath<ModuleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { moduleSettings[keyPath: keyPath] },
            set: { value in
                var settings = settingsStore.settings
                var module = settings.modules[.sensors] ?? ModuleSettings()
                module[keyPath: keyPath] = value
                settings.modules[.sensors] = module
                settingsStore.settings = settings
            }
        )
    }

    private func widgetBinding<Value>(
        _ id: Int,
        _ keyPath: WritableKeyPath<SensorWidgetSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settingsStore.settings.sensors.widget(id: id)?[keyPath: keyPath]
                    ?? SensorWidgetSettings(id: id)[keyPath: keyPath]
            },
            set: { value in
                updateWidget(id) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor) },
            set: { color in
                guard let hex = NSColor(color).hexRGB else { return }
                var settings = settingsStore.settings
                var module = settings.modules[.sensors] ?? ModuleSettings()
                module[keyPath: keyPath] = hex
                settings.modules[.sensors] = module
                settingsStore.settings = settings
            }
        )
    }

    private func updateWidget(_ id: Int, mutation: (inout SensorWidgetSettings) -> Void) {
        var settings = settingsStore.settings
        guard let index = settings.sensors.widgets.firstIndex(where: { $0.id == id }) else { return }
        mutation(&settings.sensors.widgets[index])
        settingsStore.settings = settings
    }

    private func addReading(_ sensorID: String, widgetID: Int) {
        updateWidget(widgetID) { widget in
            guard !widget.sensorIDs.contains(sensorID) else { return }
            widget.sensorIDs.append(sensorID)
        }
    }

    private func removeReading(_ sensorID: String, widgetID: Int) {
        updateWidget(widgetID) { $0.sensorIDs.removeAll { $0 == sensorID } }
    }

    private func moveReading(widgetID: Int, from index: Int, offset: Int) {
        updateWidget(widgetID) { widget in
            let destination = index + offset
            guard widget.sensorIDs.indices.contains(index),
                widget.sensorIDs.indices.contains(destination)
            else {
                return
            }
            widget.sensorIDs.swapAt(index, destination)
        }
    }

    private func addWidget() {
        var settings = settingsStore.settings
        let id = settings.sensors.nextWidgetID
        settings.sensors.widgets.append(SensorWidgetSettings(id: id, isEnabled: false))
        settingsStore.settings = settings
        settingsStore.stageSensorWidgetVisibility(true, for: id)
        settingsStore.stageMenuBarVisibility(true, for: .sensors)
    }

    private func disableWidget(_ id: Int) {
        settingsStore.stageSensorWidgetVisibility(false, for: id)
    }
}

extension SensorWidgetMode {
    fileprivate var title: String {
        switch self {
        case .compactStack: "Compact two-row stack"
        case .text: "Labels and values"
        case .graph: "History graph"
        case .fan: "Fan RPM"
        }
    }
}

extension SensorKind {
    fileprivate var title: String {
        switch self {
        case .temperature: "Temperatures"
        case .fan: "Fans"
        case .power: "Power"
        case .voltage: "Voltage"
        case .current: "Current"
        }
    }
}

extension NSColor {
    fileprivate var hexRGB: String? {
        guard let components = usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(components.redComponent * 255),
            Int(components.greenComponent * 255),
            Int(components.blueComponent * 255)
        )
    }
}
