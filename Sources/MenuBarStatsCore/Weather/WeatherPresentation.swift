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
    /// Formats one sample using the persisted renderer mode.
    public static func menuBar(
        sample: WeatherSample,
        mode: String
    ) -> WeatherMenuBarPresentation {
        let forecast = sample.forecast
        let temperature = measurement(forecast.current.temperature, unit: forecast.units.temperature.symbol)
        let staleMarker = sample.isStale ? " ⚠︎" : ""
        let conditionSymbol = forecast.current.code.symbolName(isDay: forecast.current.isDay)

        switch mode {
        case "temperature":
            return WeatherMenuBarPresentation(symbolName: nil, text: temperature + staleMarker)
        case "conditions":
            return WeatherMenuBarPresentation(
                symbolName: conditionSymbol,
                text: "\(temperature) \(forecast.current.code.description)\(staleMarker)"
            )
        case "highLow":
            let today = forecast.daily.first
            let high = degree(today?.high)
            let low = degree(today?.low)
            return WeatherMenuBarPresentation(symbolName: nil, text: "H \(high)  L \(low)\(staleMarker)")
        case "precipitation":
            let probability = forecast.hourly.first?.precipitationProbability
                ?? forecast.daily.first?.precipitationProbability
            return WeatherMenuBarPresentation(
                symbolName: "drop",
                text: percentage(probability) + staleMarker
            )
        default:
            return WeatherMenuBarPresentation(symbolName: conditionSymbol, text: temperature + staleMarker)
        }
    }

    private static func measurement(_ value: Double, unit: String, separator: String = "") -> String {
        String(format: "%.0f%@%@", value, separator, unit)
    }

    private static func degree(_ value: Double?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "—"
    }

    private static func percentage(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }
}
