import Foundation

/// Formats battery time estimates for the menu bar and the dropdown.
///
/// Menu bar strings stay as short as the value allows while every possible value reserves one
/// stable width, so a status item never changes size as the estimate moves.
public enum BatteryTimeFormatter {
    /// Widest menu bar string any estimate can produce.
    ///
    /// Apple silicon routinely reports more than ten hours on battery, so the reservation covers
    /// two leading digits rather than the one a short estimate needs.
    public static let reservedCompact = "99:99"

    /// Compact `H:MM` menu bar string, or a dash when there is no estimate.
    public static func compact(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else {
            return "—"
        }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Spoken and dropdown string such as `8 hr 15 min`, or `nil` when there is no estimate.
    public static func long(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else {
            return nil
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 {
            return "\(remainder) min"
        }
        if remainder == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainder) min"
    }

    /// Dropdown string that distinguishes "no estimate yet" from "nothing to estimate".
    public static func detail(minutes: Int?, isEstimating: Bool) -> String {
        long(minutes: minutes) ?? (isEstimating ? "Calculating…" : "—")
    }
}
