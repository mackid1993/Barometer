import AppKit
import ApplicationServices
import EventKit
import Foundation
import OSLog
import SystemSources

/// The macOS permissions Barometer can ask for, what each one buys, and how to give them all back.
///
/// Barometer asks for as little as it can. Nothing is requested at launch: a permission is only requested by
/// the feature that needs it, at the moment it is used.
@MainActor
enum AppPermissions {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "permissions")

    /// One permission, as a person would need it explained.
    struct Entry: Identifiable {
        let id: String
        let name: String
        let symbolName: String
        /// The TCC service name `tccutil` knows it by, or nil when macOS does not keep it in TCC at all.
        let service: String?
        let purpose: String
        let status: String?
        /// Whether macOS has already granted it, so the row knows to offer it or not.
        let isGranted: Bool
        /// A settings list the row always offers, granted or not. Location has one because Reset All cannot
        /// touch it — macOS keeps it outside TCC — so the list is the only way to switch it back off.
        let settingsTitle: String?
    }

    /// The permissions whose status a running application cannot see change, and why.
    ///
    /// Full Disk Access is settled when the process starts and is not revisited while it runs, and EventKit
    /// answers the calendar question from a class method whose answer it keeps for just as long. Accessibility
    /// and Location both report a change as it happens: `AXIsProcessTrusted()` asks the system each time, and
    /// `CLLocationManager` has a delegate.
    static let relaunchNote = "Full Disk Access and Calendars only show a change here after you reopen "
        + "Barometer. macOS decides what an app may do when the app starts, and does not look again while it "
        + "is running. Accessibility and Location update straight away."

    /// Every permission Barometer can use, with what it is for and where it currently stands.
    static func entries() -> [Entry] {
        let notifications = NotificationCenterSource.accessState()
        return [
            Entry(
                id: "disk", name: "Full Disk Access", symbolName: "externaldrive.fill",
                service: "SystemPolicyAllFiles",
                purpose: "Reads the notifications waiting in Notification Center so the clock dropdown can list "
                    + "them. macOS keeps that list in a protected database and offers no narrower key to it. "
                    + "Barometer only reads, and only that database. Leave this off and every other module "
                    + "still works.",
                status: {
                    switch notifications {
                    case .available: "Granted"
                    case .fullDiskAccessRequired: "Not granted"
                    case .unavailable: "Not in use"
                    }
                }(),
                isGranted: notifications == .available, settingsTitle: nil),
            Entry(
                id: "accessibility", name: "Accessibility", symbolName: "hand.point.up.left.fill",
                service: "Accessibility",
                purpose: "Opens Notification Center. Barometer moves the hidden pointer into the screen corner "
                    + "assigned to it and reads whether the panel opened, then puts the pointer back. It is "
                    + "also what lets Barometer cover the system clock on Macs where the clock cannot be "
                    + "removed outright. Barometer does not read other applications' windows.",
                status: AXIsProcessTrusted() ? "Granted" : "Not granted",
                isGranted: AXIsProcessTrusted(), settingsTitle: nil),
            Entry(
                id: "calendars", name: "Calendars", symbolName: "calendar",
                service: "Calendar",
                purpose: "Lists today's events in the clock dropdown. Asked for only when calendar events are "
                    + "switched on under Time and Notifications.",
                status: calendarStatus(),
                isGranted: EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                settingsTitle: nil),
            Entry(
                id: "location", name: "Location", symbolName: "location.fill",
                // `tccutil` accepts the name and exits cleanly, but macOS keeps location grants in
                // locationd's own root-owned store rather than in TCC, so nothing is reset by asking. It is
                // left out of Reset All rather than reported as reset.
                service: nil,
                purpose: "Finds the weather where you are. Asked for only when \"Use current location\" is "
                    + "switched on under Weather, and never used for anything else. macOS keeps this one in "
                    + "Location Services rather than with the others, so only you can switch it off.",
                status: locationStatus(),
                isGranted: CurrentLocationProvider.shared.accessState == .authorized,
                settingsTitle: "Open Location Settings"),
        ]
    }

    /// Reading an authorization is not the same as requesting one: both of these report what macOS already
    /// decided and neither presents a prompt.
    ///
    /// EventKit answers this from a class method with no per-store variant, and it holds its answer inside the
    /// process, so granting Calendars while Barometer is running can leave this reporting the old value until
    /// Barometer is reopened. Building a store first is what sometimes shakes it loose, and the row says so
    /// when the answer is anything but granted.
    private static func calendarStatus() -> String {
        _ = EKEventStore()
        return switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: "Granted"
        case .writeOnly: "Partly granted"
        case .denied, .restricted: "Not granted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    private static func locationStatus() -> String {
        switch CurrentLocationProvider.shared.accessState {
        case .authorized: "Granted"
        case .denied, .restricted: "Not granted"
        case .notDetermined: "Not asked yet"
        case .unavailable: "Not available"
        }
    }

    /// Hands every permission back, so macOS asks again the next time a feature needs one.
    ///
    /// Resetting the grant Barometer is currently running on takes effect at once, so the app has to be
    /// reopened before the features behind these permissions work again.
    static func resetAll() async -> String {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return "Barometer could not identify itself to macOS."
        }
        var reset: [String] = []
        var refused: [String] = []
        for entry in entries() {
            guard let service = entry.service else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", service, bundleIdentifier]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                // `tccutil` is not instantaneous, and this is called from a dialog action on the main actor.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        task.waitUntilExit()
                        continuation.resume()
                    }
                }
                if task.terminationStatus == 0 { reset.append(entry.name) } else { refused.append(entry.name) }
            } catch {
                refused.append(entry.name)
                logger.error("could not reset \(service, privacy: .public)")
            }
        }
        if reset.isEmpty {
            return "macOS refused to reset these permissions. Remove Barometer from each list in System "
                + "Settings > Privacy & Security instead."
        }
        // Two things make a successful reset look like a failure, so both are said outright: macOS caches a
        // process's Accessibility trust for its lifetime, so this window keeps reporting Granted until
        // Barometer is reopened, and tccutil leaves an entry switched off rather than unset, so a feature is
        // refused rather than asking again.
        let cleared = "Gave back: \(reset.joined(separator: ", ")). Full Disk Access and Calendars go on "
            + "showing what they show now until you reopen Barometer. macOS also leaves these switched off "
            + "rather than forgotten, so it will not ask you again — switch back on whichever you want in "
            + "System Settings > Privacy & Security."
        let locationNote = " Location is not included: macOS keeps it in Location Services, where only you can "
            + "switch it off."
        let refusals = refused.isEmpty ? "" : " macOS refused: \(refused.joined(separator: ", "))."
        return cleared + refusals + locationNote
    }

    /// Asks for one permission, from the row that names it.
    ///
    /// macOS only presents a prompt for a permission it has never asked about. Once one has been refused, or
    /// switched off by hand, it stays refused and asking again produces nothing at all — the only route is the
    /// list in System Settings. Full Disk Access has no prompt at any point. So each of these prompts where
    /// prompting works and opens the right list where it does not, and says which of the two it did.
    static func grant(_ id: String) async -> String {
        switch id {
        case "disk":
            NotificationAccessSettings.open()
            return "macOS never asks for this one. Add Barometer to the list that just opened, then reopen "
                + "Barometer."
        case "accessibility":
            NotificationAccessSettings.requestAccessibility()
            return "Answer the Accessibility prompt. This row follows it as soon as you do."
        case "calendars":
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = try? await CalendarEventSource().requestFullAccess()
                // EventKit answers from a class method and keeps that answer for the life of the process, so
                // granting here does not change what this pane can see. Only a relaunch does.
                return "Answer the Calendars prompt, then reopen Barometer. Until you do, this row goes on "
                    + "showing what it shows now, even once you have said yes."
            }
            openCalendarSettings()
            return "macOS only asks once. Calendars has been turned off before, so it will not ask again — "
                + "switch Barometer on in the list that just opened."
        case "location":
            if CurrentLocationProvider.shared.accessState == .notDetermined {
                CurrentLocationProvider.shared.requestAuthorizationIfNeeded()
                return "Answer the Location prompt."
            }
            openLocationSettings()
            return "macOS only asks once. Location has been turned off before, so it will not ask again — "
                + "switch Barometer on in Location Services, which just opened."
        default:
            openPrivacySettings()
            return "Switch Barometer on in the list that just opened."
        }
    }

    /// Quits Barometer and opens it again.
    ///
    /// macOS decides what a process may do when the process starts. Accessibility and Full Disk Access are
    /// settled for the lifetime of the running application, so a permission granted or taken away only takes
    /// effect on the next launch, however often the state is re-read.
    static func relaunch() {
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c", "sleep 0.75; /usr/bin/open \"$1\"", "barometer-relaunch", Bundle.main.bundleURL.path,
        ]
        relauncher.standardOutput = FileHandle.nullDevice
        relauncher.standardError = FileHandle.nullDevice
        do {
            try relauncher.run()
        } catch {
            logger.error("could not schedule the reopen")
            return
        }
        NSApp.terminate(nil)
    }

    /// Opens the Calendars list, for a grant macOS will no longer prompt for.
    static func openCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens Location Services, the one list Barometer cannot change for the user.
    static func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the Privacy & Security pane, where the grants live.
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
