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
    @State private var accessibilityAllowed = NotificationCenterOpener.isTrusted

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
                MenuBarColorPickerRows(
                    lightColor: colorBinding(\.lightColor),
                    darkColor: colorBinding(\.darkColor),
                    isDisabled: settingsStore.settings.usesGlobalColors || settingsStore.settings.isMonochrome
                )
            }
            Section("Notification Center") {
                Toggle("Open Notification Center on click", isOn: notificationCenterBinding)
                Text("Clicking the clock opens macOS Notification Center, including its widgets. "
                    + "Right-click or Control-click the clock for the Barometer dropdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settingsStore.settings.time.opensNotificationCenterOnClick {
                    accessibilityStatusView
                }
            }
            .task(id: settingsStore.settings.time.opensNotificationCenterOnClick) {
                await watchAccessibilityAccess()
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
            Text("Barometer needs Accessibility access to open Notification Center. Until it is allowed in "
                + "System Settings > Privacy & Security > Accessibility, clicking the clock opens the dropdown.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Accessibility Settings…") { NotificationCenterOpener.openAccessibilitySettings() }
        }
    }

    /// Turning the option on asks macOS for Accessibility access, which is a direct user action.
    private var notificationCenterBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.time.opensNotificationCenterOnClick },
            set: { isOn in
                var settings = settingsStore.settings
                settings.time.opensNotificationCenterOnClick = isOn
                settingsStore.settings = settings
                if isOn {
                    accessibilityAllowed = NotificationCenterOpener.requestAccess()
                }
            }
        )
    }

    /// Tracks the Accessibility grant while the option is on, so the pane updates as soon as it is allowed.
    private func watchAccessibilityAccess() async {
        accessibilityAllowed = NotificationCenterOpener.isTrusted
        guard settingsStore.settings.time.opensNotificationCenterOnClick else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            accessibilityAllowed = NotificationCenterOpener.isTrusted
        }
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
