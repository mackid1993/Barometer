import Foundation

/// Text and optional symbol used by the Weather menu bar renderer.
public struct WeatherMenuBarPresentation: Equatable, Sendable {
    /// SF Symbol name, or `nil` for text-only modes.
    public let symbolName: String?

    /// Fully formatted menu bar text.
    public let text: String

    /// Creates a Weather menu bar presentation.
    public init(symbolName: String?, text: String) {
        self.symbolName = symbolName
        self.text = text
    }
}

/// Deterministic Weather text formatting shared by the UI and tests.
public enum WeatherPresentationFormatter {
    /// Widest menu bar string the single Weather presentation can produce.
    ///
    /// Three digits and a sign cover every temperature either unit can report.
    public static let reservedMenuBarText = "-99°"

    /// The one Weather menu bar presentation: current conditions and the current temperature.
    ///
    /// The unit letter is left off. The person reading it chose the unit, and dropping it buys a
    /// glyph of width back in a place where width is scarce.
    public static func menuBar(sample: WeatherSample) -> WeatherMenuBarPresentation {
        let current = sample.forecast.current
        return WeatherMenuBarPresentation(
            symbolName: current.code.symbolName(isDay: current.isDay),
            text: degree(current.temperature)
        )
    }

    /// A temperature with a degree sign and no unit letter.
    public static func degree(_ value: Double?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "—"
    }

}
