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
    @State private var hotCornerSetupMessage: String?
    @State private var isConfiguringHotCorner = false
    @State private var chosenCorner = NotificationCenterOpening.preferredCorner
    /// Which corners the user has left free. Read once rather than five times per body evaluation: each check
    /// builds a preferences suite and asks the running Dock.
    @State private var freeCorners: Set<String> = []

    private var moduleSettings: ModuleSettings {
        settingsStore.settings.modules[.time] ?? ModuleSettings(mode: "custom", interval: 60)
    }

    private var menuBarConfiguration: TimeMenuBarConfiguration {
        settingsStore.timeMenuBarConfiguration
    }

    var body: some View {
        let now = store.latestSample?.timestamp ?? Date()
        ScrollViewReader { proxy in
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
                Text("If you use a menu bar manager, leave this setting off and hide the clock through your "
                    + "menu bar manager instead. Enabling both can interfere with system menu bar items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Removes the macOS clock from the menu bar so this clock can take its place, and gives its "
                    + "width back. Control Center and everything inside it stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settingsStore.settings.time.hidesSystemClock {
                    clockHiderStatusView
                }
            }
            .task(id: settingsStore.settings.time.hidesSystemClock) {
                await watchAccessibilityAccess()
            }
            Section("System Controls") {
                Toggle("Enable Focus", isOn: settingsStore.menuBarVisibilityBinding(for: .focus))
                Toggle("Enable Now Playing", isOn: settingsStore.menuBarVisibilityBinding(for: .nowPlaying))
                Picker("Show Now Playing", selection: timeBinding(\.nowPlayingVisibility)) {
                    ForEach(NowPlayingVisibility.allCases, id: \.self) { visibility in
                        Text(visibility.displayName).tag(visibility)
                    }
                }
                Text("Focus appears only while a system Focus is active. Now Playing can appear only during "
                    + "playback or remain visible. Select Apply Changes to enable or disable either item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Dropdown") {
                Toggle("Show seconds in dropdown clock", isOn: timeBinding(\.showsDropdownSeconds))
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
                    + "doesn't prevent access. Follows macOS notification visibility settings. Clicking and "
                    + "clearing require Accessibility access; banners keep arriving normally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settingsStore.settings.time.showsNotifications {
                    notificationAccessView
                }
            }
            .task(id: settingsStore.settings.time.showsNotifications) {
                await watchNotificationAccess()
            }
            Section("Open Notification Center") {
                Text("With the system clock hidden, a screen corner assigned to Notification Center is the only "
                    + "thing left that opens the panel from an app. Barometer's button fires that corner: the "
                    + "pointer is hidden for the instant it takes and ends up where it was. Swiping in from the "
                    + "right edge of the trackpad opens the panel too, and needs no corner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let corner = NotificationCenterOpening.assignedCornerKey {
                    Label("The \(Self.cornerTitle(corner).lowercased()) corner opens Notification Center",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if NotificationCenterOpening.barometerOwnedCorner != nil {
                        Button("Give the Corner Back") {
                            NotificationCenterOpening.releaseCorner()
                            hotCornerSetupMessage = "The corner is yours again, and the Dock restarted."
                        }
                        .help("Restores the corner exactly as it was and restarts the Dock once")
                    }
                } else {
                    Picker("Pick the hot corner you want", selection: $chosenCorner) {
                        ForEach(DockHotCorners.cornerKeys, id: \.self) { key in
                            Text(freeCorners.contains(key)
                                ? Self.cornerTitle(key)
                                : "\(Self.cornerTitle(key)) — already yours")
                                .tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: chosenCorner) { _, corner in
                        NotificationCenterOpening.preferredCorner = corner
                    }
                    Text("Choose a corner your pointer does not travel to. Whichever you choose opens "
                        + "Notification Center whenever the pointer reaches it — macOS gives no way to limit "
                        + "that to Barometer. A corner already carrying one of your own actions is never taken.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(isConfiguringHotCorner
                        ? "Assigning and restarting the Dock…"
                        : "Assign the \(Self.cornerTitle(chosenCorner).lowercased()) corner and restart the Dock") {
                        Task { await configureHotCorner(chosenCorner) }
                    }
                    .disabled(isConfiguringHotCorner || !freeCorners.contains(chosenCorner))
                    .help("Writes the corner into the Dock's settings and restarts the Dock once, which is the "
                        + "only way the assignment takes effect")
                }

                Text("You can also set it yourself in System Settings > Desktop & Dock > Hot Corners…, which "
                    + "applies at once with nothing to restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Hot Corner Settings…") { NotificationCenterOpening.openHotCornerSettings() }
                if let message = hotCornerSetupMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .id(SettingsFocus.hotCornerInstructions)
            .task { freeCorners = Set(DockHotCorners.cornerKeys.filter(DockHotCorners.isFree)) }
        }
        .formStyle(.grouped)
        .settingsPane(module: .time, settings: settingsStore.settings, preview: previewImage)
        .onAppear { scrollToPendingAnchor(proxy) }
        .onChange(of: SettingsFocus.shared.pendingAnchor) { _, _ in scrollToPendingAnchor(proxy) }
        }
    }

    /// The clock as the menu bar will draw it, from the format waiting for Apply Changes rather than the saved
    /// one, so the preview shows the choice being made.
    private var previewImage: NSImage {
        let appSettings = settingsStore.settingsIncludingPendingMenuBarChanges
        let module = appSettings.modules[.time] ?? ModuleSettings()
        let color = NSColor(hex: appSettings.darkColor(for: module)) ?? .white
        let staged = settingsStore.timeMenuBarConfiguration
        var context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: color, dark: color),
            fontSize: appSettings.effectiveMenuBarFontSize,
            isMonochrome: appSettings.isMonochrome,
            scale: appSettings.effectiveMenuBarScale,
            fontWeight: appSettings.fontWeight
        )
        if let size = staged.fontSize { context = context.withFontSize(CGFloat(size)) }
        let text = TimeFormatEngine.render(
            date: Date(timeIntervalSince1970: 1_735_735_845),
            timeZone: .current,
            template: staged.template,
            showsSeconds: staged.showsSeconds
        )
        let reserved = TimeFormatEngine.menuBarPlaceholder(
            template: staged.template, showsSeconds: staged.showsSeconds)
        return TextRenderer(text: text, reservedText: staged.usesFixedWidth ? reserved : nil)
            .render(in: context)
    }

    /// The name of a corner as a person would say it, rather than the Dock's preference key.
    private static func cornerTitle(_ key: String) -> String {
        switch key {
        case "tl": "Top left"
        case "tr": "Top right"
        case "bl": "Bottom left"
        default: "Bottom right"
        }
    }

    /// Assigns the chosen corner and restarts the Dock so it takes effect.
    private func configureHotCorner(_ corner: String) async {
        isConfiguringHotCorner = true
        hotCornerSetupMessage = nil
        defer { isConfiguringHotCorner = false }
        switch await NotificationCenterOpening.configure(corner: corner) {
        case let .alreadyAssignedTo(existing):
            hotCornerSetupMessage = "The \(Self.cornerTitle(existing)) corner was already assigned to "
                + "Notification Center, so nothing was changed."
        case let .assigned(assigned):
            hotCornerSetupMessage = "The \(Self.cornerTitle(assigned)) corner now opens Notification Center. "
                + "Try the button in the clock dropdown."
        case .cornerInUse:
            hotCornerSetupMessage = "That corner already has one of your own actions, so Barometer left it alone."
        case let .failed(reason):
            hotCornerSetupMessage = reason
        }
    }

    /// Lands on the section the flyout sent the user to, then clears the request.
    private func scrollToPendingAnchor(_ proxy: ScrollViewProxy) {
        guard let anchor = SettingsFocus.shared.pendingAnchor else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
            SettingsFocus.shared.pendingAnchor = nil
        }
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
    private var clockHiderStatusView: some View {
        switch SystemClockHider.shared.state {
        case .off:
            Text("Turning on…").font(.caption).foregroundStyle(.secondary)
        case .removed:
            Label("The system clock is removed from the menu bar", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .covered, .coverNeedsAccessibility:
            Text("This macOS build cannot remove the clock, so Barometer covers it instead. The covered strip "
                + "keeps its width, and a click on it does nothing. Finding the clock needs Accessibility access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if accessibilityAllowed {
                Label("Accessibility access allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open Accessibility Settings…") { SystemClockCover.openAccessibilitySettings() }
            }
            ColorPicker("Cover color", selection: coverColorBinding, supportsOpacity: false)
            Text("Pick the menu bar's own color with the eyedropper so the cover disappears into the bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Text("The menu bar refused: \(reason)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hideSystemClockBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.time.hidesSystemClock },
            set: { isOn in
                var settings = settingsStore.settings
                settings.time.hidesSystemClock = isOn
                settingsStore.settings = settings
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
            SystemClockHider.shared.refreshCoverAccess()
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
        if accessibilityAllowed {
            Label("Accessibility allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text("Allow Accessibility so Barometer can ask Notification Center to open or clear notifications.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Allow Accessibility…") { NotificationAccessSettings.requestAccessibility() }
        }
    }

    /// Tracks the Full Disk Access grant while the option is on, so the pane updates as soon as it is allowed.
    private func watchNotificationAccess() async {
        notificationAccess = NotificationCenterSource.accessState()
        accessibilityAllowed = NotificationAccessSettings.accessibilityAllowed
        guard settingsStore.settings.time.showsNotifications else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            notificationAccess = NotificationCenterSource.accessState()
            accessibilityAllowed = NotificationAccessSettings.accessibilityAllowed
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
