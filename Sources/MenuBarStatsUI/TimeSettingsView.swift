import AppKit
import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Time format, world-clock, sampling, and color preferences.
struct TimeSettingsView: View {
    let store: ModuleStore<TimeSample>
    let settingsStore: SettingsStore
    let requestCalendarAccess: @MainActor () -> Void
    @State private var timeZoneSearch = ""
    @State private var notificationAccess = NotificationCenterSource.accessState()
    @State private var accessibilityAllowed = SystemClockCover.isTrusted

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.time] ?? ModuleSettings(mode: "custom", interval: 60)
    }

    private var menuBarConfiguration: TimeMenuBarConfiguration {
        settingsStore.timeMenuBarConfiguration
    }

    var body: some View {
        let now = store.latestSample?.timestamp ?? Date()
        Form {
            Section {
                Toggle("Show in menu bar", isOn: settingsStore.menuBarVisibilityBinding(for: .time))
                LabeledContent("Live preview", value: preview(date: now))
            }
            Section("Menu Bar") {
                TextField("Format", text: menuBarBinding(\.template))
                Toggle("Show seconds", isOn: menuBarBinding(\.showsSeconds))
                Toggle("Use fixed-width numbers", isOn: menuBarBinding(\.usesFixedWidth))
                Text("Tokens: {time}, {time24}, {date}, {weekday}, {week}, {day}, {zone}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use a separate text size for the clock", isOn: separateTextSizeBinding)
                if let clockFontSize = menuBarConfiguration.fontSize {
                    HStack {
                        Text("Clock text size")
                        Slider(value: clockTextSizeBinding, in: TimeSettings.menuBarFontSizeRange, step: 0.5)
                        Text(String(format: "%.1f pt", clockFontSize))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    Text("Takes effect when you select Apply Changes, which reopens Barometer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
            }
            Section("World Clocks") {
                ForEach(settingsStore.settings.time.worldClockIdentifiers, id: \.self) { identifier in
                    HStack {
                        Text(identifier)
                        Spacer()
                        Button("Remove") { removeTimeZone(identifier) }.buttonStyle(.borderless)
                    }
                }
                TextField("Search time zones", text: $timeZoneSearch)
                ForEach(searchResults.prefix(8), id: \.self) { identifier in
                    Button("Add \(identifier)") { addTimeZone(identifier) }
                        .buttonStyle(.borderless)
                }
            }
            Section("Calendar") {
                Picker("Start week on", selection: timeBinding(\.calendarWeekStart)) {
                    ForEach(CalendarWeekStart.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Toggle("Show upcoming events", isOn: timeBinding(\.showsCalendarEvents))
                Stepper(value: timeBinding(\.calendarEventCount), in: 1...10) {
                    Text("Event count: \(settingsStore.settings.time.calendarEventCount)")
                }
                calendarAuthorizationView
            }
            Section("System Clock") {
                Toggle("Hide the system clock", isOn: hideSystemClockBinding)
                Text("Covers the macOS clock so this clock can take its place. The covered strip keeps its "
                    + "width, and a click on it does nothing. Needs Accessibility access to find the clock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settingsStore.settings.time.hidesSystemClock {
                    accessibilityStatusView
                    ColorPicker("Cover color", selection: coverColorBinding, supportsOpacity: false)
                    Text("Pick the menu bar's own color with the eyedropper so the cover disappears into the bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: settingsStore.settings.time.hidesSystemClock) {
                await watchAccessibilityAccess()
            }
            Section("Dropdown") {
                HStack {
                    Text("Height")
                    Slider(value: timeBinding(\.dropdownHeight), in: TimeSettings.dropdownHeightRange, step: 20)
                    Text("\(Int(settingsStore.settings.time.dropdownHeight)) pt")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                Text("Applies the next time the dropdown opens. It never grows past the screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(settingsStore.settings.time.dropdownSectionOrder.enumerated()), id: \.element) {
                    index, section in
                    HStack {
                        Text(section.displayName)
                        Spacer()
                        Button { moveSection(at: index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(section.displayName) up")
                        Button { moveSection(at: index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == settingsStore.settings.time.dropdownSectionOrder.count - 1)
                            .accessibilityLabel("Move \(section.displayName) down")
                    }
                }
                Text("Sections appear in this order. A section with nothing to show stays hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Show notifications in the dropdown", isOn: timeBinding(\.showsNotifications))
                Text("Lists the notifications waiting in macOS Notification Center, so a hidden system clock "
                    + "loses nothing. Banners keep arriving exactly as before, and Barometer never dismisses or "
                    + "changes a notification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settingsStore.settings.time.showsNotifications {
                    notificationAccessView
                }
            }
            .task(id: settingsStore.settings.time.showsNotifications) {
                await watchNotificationAccess()
            }
        }
        .formStyle(.grouped)
        .settingsPane(module: .time, settings: settingsStore.settings)
    }

    @ViewBuilder
    private var calendarAuthorizationView: some View {
        switch store.latestSample?.calendarAuthorization ?? .notDetermined {
        case .notDetermined:
            Button("Allow Calendar Access…", action: requestCalendarAccess)
        case .fullAccess:
            Label("Calendar access allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied, .restricted, .writeOnly:
            Text("Full Calendar access is not allowed. Change it in System Settings > Privacy & Security > Calendars.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("Calendar events are unavailable.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accessibilityStatusView: some View {
        if accessibilityAllowed {
            Label("Accessibility access allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text("Barometer needs Accessibility access to find the system clock. Until it is allowed in "
                + "System Settings > Privacy & Security > Accessibility, the clock stays visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Accessibility Settings…") { SystemClockCover.openAccessibilitySettings() }
        }
    }

    /// Turning the option on asks macOS for Accessibility access, which is a direct user action.
    private var hideSystemClockBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.time.hidesSystemClock },
            set: { isOn in
                var settings = settingsStore.settings
                settings.time.hidesSystemClock = isOn
                settingsStore.settings = settings
                if isOn { accessibilityAllowed = SystemClockCover.requestAccess() }
            }
        )
    }

    private var coverColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: settingsStore.settings.time.systemClockCoverColor) ?? .black) },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                var settings = settingsStore.settings
                settings.time.systemClockCoverColor = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                settingsStore.settings = settings
            }
        )
    }

    /// Tracks the Accessibility grant while the option is on, so the pane updates as soon as it is allowed.
    private func watchAccessibilityAccess() async {
        accessibilityAllowed = SystemClockCover.isTrusted
        guard settingsStore.settings.time.hidesSystemClock else { return }
        while !Task.isCancelled, !accessibilityAllowed {
            try? await Task.sleep(for: .seconds(1))
            accessibilityAllowed = SystemClockCover.isTrusted
        }
    }

    @ViewBuilder
    private var notificationAccessView: some View {
        switch notificationAccess {
        case .available:
            Label("Full Disk Access allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .fullDiskAccessRequired:
            Text("Barometer needs Full Disk Access to read the notification list. Turn Barometer on in "
                + "System Settings > Privacy & Security > Full Disk Access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Full Disk Access Settings…") { NotificationAccessSettings.open() }
        case .unavailable:
            Text("Notifications are unavailable on this Mac.").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Tracks the Full Disk Access grant while the option is on, so the pane updates as soon as it is allowed.
    private func watchNotificationAccess() async {
        notificationAccess = NotificationCenterSource.accessState()
        guard settingsStore.settings.time.showsNotifications else { return }
        while !Task.isCancelled, notificationAccess != .available {
            try? await Task.sleep(for: .seconds(1))
            notificationAccess = NotificationCenterSource.accessState()
        }
    }

    /// Turning the separate size on starts from the global text size so nothing jumps.
    private var separateTextSizeBinding: Binding<Bool> {
        Binding(
            get: { menuBarConfiguration.fontSize != nil },
            set: { isOn in
                var configuration = menuBarConfiguration
                configuration.fontSize = isOn ? settingsStore.fontSize : nil
                settingsStore.stageTimeMenuBarConfiguration(configuration)
            }
        )
    }

    private var clockTextSizeBinding: Binding<Double> {
        Binding(
            get: { menuBarConfiguration.fontSize ?? settingsStore.fontSize },
            set: { size in
                var configuration = menuBarConfiguration
                configuration.fontSize = TimeSettings.clampedMenuBarFontSize(size)
                settingsStore.stageTimeMenuBarConfiguration(configuration)
            }
        )
    }

    private var searchResults: [String] {
        guard !timeZoneSearch.isEmpty else { return [] }
        let selected = Set(settingsStore.settings.time.worldClockIdentifiers)
        return TimeZone.knownTimeZoneIdentifiers.filter {
            !selected.contains($0) && $0.localizedCaseInsensitiveContains(timeZoneSearch)
        }
    }

    private func preview(date: Date) -> String {
        TimeFormatEngine.render(
            date: date,
            timeZone: .current,
            template: menuBarConfiguration.template,
            showsSeconds: menuBarConfiguration.showsSeconds
        )
    }

    private func moveSection(at index: Int, by offset: Int) {
        var settings = settingsStore.settings
        var order = settings.time.dropdownSectionOrder
        let destination = index + offset
        guard order.indices.contains(index), order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        settings.time.dropdownSectionOrder = order
        settingsStore.settings = settings
    }

    private func addTimeZone(_ identifier: String) {
        var settings = settingsStore.settings
        settings.time.worldClockIdentifiers.append(identifier)
        settings.time.normalize()
        settingsStore.settings = settings
        timeZoneSearch = ""
    }

    private func removeTimeZone(_ identifier: String) {
        var settings = settingsStore.settings
        settings.time.worldClockIdentifiers.removeAll { $0 == identifier }
        settingsStore.settings = settings
    }

    private func timeBinding<Value>(_ keyPath: WritableKeyPath<TimeSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.time[keyPath: keyPath] },
            set: { value in
                var settings = settingsStore.settings
                settings.time[keyPath: keyPath] = value
                settingsStore.settings = settings
            }
        )
    }

    private func menuBarBinding<Value>(
        _ keyPath: WritableKeyPath<TimeMenuBarConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { menuBarConfiguration[keyPath: keyPath] },
            set: { value in
                var configuration = menuBarConfiguration
                configuration[keyPath: keyPath] = value
                settingsStore.stageTimeMenuBarConfiguration(configuration)
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ModuleSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: moduleSettings[keyPath: keyPath]) ?? .controlAccentColor) },
            set: { color in
                guard let components = NSColor(color).usingColorSpace(.sRGB) else { return }
                var appSettings = settingsStore.settings
                var settings = appSettings.modules[.time] ?? ModuleSettings(mode: "custom", interval: 60)
                settings[keyPath: keyPath] = String(
                    format: "#%02X%02X%02X",
                    Int(components.redComponent * 255),
                    Int(components.greenComponent * 255),
                    Int(components.blueComponent * 255)
                )
                appSettings.modules[.time] = settings
                settingsStore.settings = appSettings
            }
        )
    }
}
