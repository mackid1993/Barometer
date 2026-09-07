import AppKit
import ApplicationServices
import Foundation
import MenuBarStatsCore
import SwiftUI
import SystemSources

/// A stable application group in the Notification Center list.
struct NotificationApplicationGroup: Equatable, Identifiable, Sendable {
    /// Lowercased canonical bundle identifier, stable across source refreshes.
    let id: String
    /// Canonical bundle identifier used to resolve the application's name and icon.
    let applicationIdentifier: String
    /// Every notification from this application, newest first.
    let notifications: [DeliveredNotification]

    var latest: DeliveredNotification { notifications[0] }
}

/// Deterministic application grouping for the notification list.
enum NotificationGrouping {
    static func groups(_ notifications: [DeliveredNotification]) -> [NotificationApplicationGroup] {
        let ordered = notifications.enumerated().sorted { left, right in
            if left.element.date != right.element.date { return left.element.date > right.element.date }
            return left.offset < right.offset
        }
        var positions: [String: Int] = [:]
        var applications: [String] = []
        var groupedNotifications: [[DeliveredNotification]] = []

        for entry in ordered {
            let application = canonicalApplicationIdentifier(entry.element.applicationIdentifier)
            let key = application.lowercased()
            if let position = positions[key] {
                groupedNotifications[position].append(entry.element)
            } else {
                positions[key] = applications.count
                applications.append(application)
                groupedNotifications.append([entry.element])
            }
        }

        return applications.indices.map { index in
            NotificationApplicationGroup(
                id: applications[index].lowercased(),
                applicationIdentifier: applications[index],
                notifications: groupedNotifications[index]
            )
        }
    }

    /// Daemon-sent system notifications carry this prefix before the real application bundle identifier.
    static func canonicalApplicationIdentifier(_ identifier: String) -> String {
        let prefix = "_SYSTEM_CENTER_:"
        guard identifier.hasPrefix(prefix) else { return identifier }
        let application = String(identifier.dropFirst(prefix.count))
        return application.isEmpty ? identifier : application
    }
}

/// The notifications waiting in Notification Center, grouped by application.
struct NotificationListView: View {
    let feed: NotificationFeed
    let accent: ModuleAccent
    let now: Date
    @Environment(\.menuDetailActions) private var menuDetailActions
    @State private var activationError: String?
    @State private var needsHotCorner = false
    @State private var expandedGroupIdentifiers: Set<String>

    init(
        feed: NotificationFeed,
        accent: ModuleAccent,
        now: Date,
        initiallyExpandedGroupIdentifiers: Set<String> = []
    ) {
        self.feed = feed
        self.accent = accent
        self.now = now
        _expandedGroupIdentifiers = State(initialValue: initiallyExpandedGroupIdentifiers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Notifications") {
                HStack(spacing: 8) {
                    if !feed.notifications.isEmpty {
                        Chip(text: "\(feed.notifications.count)", color: accent.secondary)
                    }
                }
            }
            if needsHotCorner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set a hot corner to Notification Center first. With the system clock hidden, that corner "
                        + "is what opens the panel. Time and Notifications settings has the steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings…") { menuDetailActions?.openSettings() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent.primary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            Button {
                guard NotificationCenterOpening.assignedCornerKey != nil else {
                    needsHotCorner = true
                    return
                }
                needsHotCorner = false
                menuDetailActions?.closeDropdown()
                NotificationCenterOpening.open()
            } label: {
                Label("Open Notification Center", systemImage: "bell.badge")
                    .foregroundStyle(Color.white)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.22, green: 0.30, blue: 0.65), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Open macOS Notification Center using your configured keyboard shortcut")
            .padding(.bottom, 4)
            if let error = activationError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
            notificationContent
        }
    }

    @ViewBuilder
    private var notificationContent: some View {
        switch feed.snapshot?.access {
        case nil:
            Text("Reading notifications…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case .fullDiskAccessRequired?:
            Text("Barometer needs Full Disk Access to list notifications. Allow it in System Settings > "
                + "Privacy & Security > Full Disk Access.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            Button("Open Full Disk Access Settings…") { NotificationAccessSettings.open() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent.primary)
                .padding(.horizontal, 4)
        case .unavailable?:
            Text(feed.snapshot?.unavailabilityReason ?? "Notifications are unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case .available?:
            notificationRows
        }
        if feed.snapshot?.access != .available, !feed.notifications.isEmpty {
            Text("Showing the last available notifications. Retrying while open.")
                .font(.caption)
                .foregroundStyle(.secondary)
            notificationRows
        }
    }

    @ViewBuilder
    private var notificationRows: some View {
        let groups = NotificationGrouping.groups(feed.notifications)
        if groups.isEmpty {
            Text("No notifications")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } else {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    NotificationGroupView(
                        group: group,
                        accent: accent,
                        now: now,
                        isExpanded: expandedGroupIdentifiers.contains(group.id),
                        toggleExpansion: { toggleExpansion(group.id) },
                        activate: activate
                    )
                }
            }
            .onChange(of: Set(groups.map(\.id))) { _, currentIdentifiers in
                expandedGroupIdentifiers.formIntersection(currentIdentifiers)
            }
        }
    }

    private func toggleExpansion(_ identifier: String) {
        if expandedGroupIdentifiers.contains(identifier) {
            expandedGroupIdentifiers.remove(identifier)
        } else {
            expandedGroupIdentifiers.insert(identifier)
        }
    }

    private func activate(_ notification: DeliveredNotification) {
        activationError = nil
        Task {
            switch await NotificationRouter.route(notification) {
            case .nativeAccepted, .fallback:
                menuDetailActions?.closeDropdown()
            case .nativeFailed:
                activationError = "macOS could not open this notification. Try it in Notification Center."
            }
        }
    }
}

/// One collapsible application group with notification activation controls.
private struct NotificationGroupView: View {
    let group: NotificationApplicationGroup
    let accent: ModuleAccent
    let now: Date
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    let activate: (DeliveredNotification) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: toggleExpansion) {
                    HStack(spacing: 8) {
                        Image(nsImage: NotificationApplicationResolver.icon(
                            bundleIdentifier: group.applicationIdentifier
                        ))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(NotificationApplicationResolver.name(
                                bundleIdentifier: group.applicationIdentifier
                            ))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            if !isExpanded {
                                Text(group.latest.title.isEmpty ? "Notification" : group.latest.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Chip(text: "\(group.notifications.count)", color: accent.secondary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(applicationName), \(group.notifications.count) notifications")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Collapse notification group" : "Expand notification group")

            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)

            if isExpanded {
                Divider()
                    .overlay(accent.primary.opacity(0.22))
                    .padding(.horizontal, 6)
                ForEach(group.notifications) { notification in
                    NotificationRow(
                        notification: notification,
                        now: now,
                        activate: { activate(notification) }
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BarometerDesign.tileRadius, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BarometerDesign.tileRadius, style: .continuous)
                .stroke(accent.primary.opacity(0.14), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: BarometerDesign.tileRadius, style: .continuous))
    }

    private var applicationName: String {
        NotificationApplicationResolver.name(bundleIdentifier: group.applicationIdentifier)
    }
}

/// One notification's title, text, and age.
///
/// Clicking requests the notification's system action; clearing belongs to macOS Notification Center.
private struct NotificationRow: View {
    let notification: DeliveredNotification
    let now: Date
    let activate: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: activate) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(notification.title.isEmpty ? "Notification" : notification.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if !isHovering {
                            Text(NotificationAgeFormatter.string(from: notification.date, now: now))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if let subtitle = notification.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let body = notification.body {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isHovering ? 0.035 : 0))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help("Open using this notification's default action")
    }
}

/// Short ages for notification rows.
enum NotificationAgeFormatter {
    static func string(from date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

/// Opens the Full Disk Access pane of System Settings.
enum NotificationAccessSettings {
    @MainActor
    static var accessibilityAllowed: Bool { AXIsProcessTrusted() }

    /// Requests the existing Accessibility category only after the user chooses this action.
    @MainActor
    static func requestAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Icons and names for the applications behind notifications, cached per bundle identifier.
@MainActor
enum NotificationApplicationResolver {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func applicationBundleIdentifier(_ identifier: String) -> String {
        NotificationGrouping.canonicalApplicationIdentifier(identifier)
    }

    static func icon(bundleIdentifier rawIdentifier: String) -> NSImage {
        let bundleIdentifier = applicationBundleIdentifier(rawIdentifier)
        if let cached = icons[bundleIdentifier] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? (bundleIdentifier.hasPrefix("com.apple.")
                ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
                : nil)
            ?? NSImage(systemSymbolName: "app.badge", accessibilityDescription: "Application")
            ?? NSImage()
        let thumbnail = ProcessIconResolver.thumbnail(icon, side: 18)
        if icons.count > 64 { icons.removeAll() }
        icons[bundleIdentifier] = thumbnail
        return thumbnail
    }

    static func name(bundleIdentifier rawIdentifier: String) -> String {
        let bundleIdentifier = applicationBundleIdentifier(rawIdentifier)
        if let cached = names[bundleIdentifier] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
            ?? bundleIdentifier
        names[bundleIdentifier] = name
        return name
    }

    static func open(bundleIdentifier rawIdentifier: String) {
        let bundleIdentifier = applicationBundleIdentifier(rawIdentifier)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            if let settings = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(settings) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
