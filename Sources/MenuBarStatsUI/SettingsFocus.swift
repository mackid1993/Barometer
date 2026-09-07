import Observation

/// A section the Settings window should scroll to when it opens next, set by whoever sends the user there.
@MainActor
@Observable
final class SettingsFocus {
    static let shared = SettingsFocus()

    /// Scroll target for the Time and Notifications pane: the Open Notification Center instructions.
    static let hotCornerInstructions = "time.hotCornerInstructions"

    var pendingAnchor: String?

    private init() {}
}
