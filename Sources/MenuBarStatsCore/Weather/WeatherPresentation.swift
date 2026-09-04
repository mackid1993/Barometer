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
    /// Formats one sample using the persisted renderer mode and custom template.
    public static func menuBar(
        sample: WeatherSample,
        mode: String,
        template: String
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
        case "template":
            return WeatherMenuBarPresentation(
                symbolName: nil,
                text: customTemplate(sample: sample, template: template) + staleMarker
            )
        default:
            return WeatherMenuBarPresentation(symbolName: conditionSymbol, text: temperature + staleMarker)
        }
    }

    /// Expands supported custom Weather tokens, leaving unknown tokens intact.
    public static func customTemplate(sample: WeatherSample, template: String) -> String {
        let forecast = sample.forecast
        let today = forecast.daily.first
        let precipitationProbability = forecast.hourly.first?.precipitationProbability
            ?? today?.precipitationProbability
        return template
            .replacingOccurrences(
                of: "{temp}",
                with: measurement(forecast.current.temperature, unit: forecast.units.temperature.symbol)
            )
            .replacingOccurrences(of: "{cond}", with: forecast.current.code.description)
            .replacingOccurrences(of: "{hi}", with: degree(today?.high))
            .replacingOccurrences(of: "{lo}", with: degree(today?.low))
            .replacingOccurrences(of: "{pop}", with: percentage(precipitationProbability))
            .replacingOccurrences(
                of: "{wind}",
                with: forecast.current.windSpeed.map {
                    measurement($0, unit: forecast.units.windSpeed.symbol, separator: " ")
                } ?? "—"
            )
            .replacingOccurrences(of: "{aqi}", with: sample.airQuality?.usAQI.map(String.init) ?? "—")
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
