import MenuBarStatsCore
import SwiftUI

/// Additional day details grouped by the questions people ask about the forecast.
struct WeatherDayExtraSections: View {
    let day: DailyPoint
    let section: WeatherDetailSection
    let units: WeatherUnits
    let accent: ModuleAccent
    let preferences: WeatherDetailSettings

    var body: some View {
        if let values = day.details {
            WeatherDetailCard(section: section, preferences: preferences,
                                  tint: section == .precipitation ? accent.primary : nil) {
                WeatherDetailGrid(rows: rows(values), units: units)
            }
        }
    }

    private func rows(_ values: DailyWeatherDetails) -> [(String, Double?, WeatherDetailUnit)] {
        switch section {
        case .precipitation:
            return [
                ("Rain", values[.rainSum], .precipitation),
                ("Showers", values[.showersSum], .precipitation),
                ("Snowfall", values[.snowfallSum], .snowfall),
                ("Precipitation hours", values[.precipitationHours], .hours),
                ("Sunshine", values[.sunshineDuration], .duration),
                ("Clear-sky UV maximum", values[.uvIndexClearSkyMax], .number)
            ]
        case .airComfort:
            return [
                ("Average temperature", values[.temperatureMean], .temperature),
                ("Average feels like", values[.apparentTemperatureMean], .temperature),
                ("Average humidity", values[.humidityMean], .percent),
                ("Minimum humidity", values[.humidityMin], .percent),
                ("Maximum humidity", values[.humidityMax], .percent),
                ("Average dew point", values[.dewPointMean], .temperature),
                ("Average cloud cover", values[.cloudCoverMean], .percent),
                ("Prevailing wind", values[.windDirectionDominant], .direction),
                ("Average visibility", values[.visibilityMean], .visibility),
                ("Minimum visibility", values[.visibilityMin], .visibility),
                ("Average pressure", values[.pressureMean], .pressure)
            ]
        case .atmosphere:
            return [
                ("Surface pressure", values[.surfacePressureMean], .pressure),
                ("Average wet-bulb temperature", values[.wetBulbTemperatureMean], .temperature),
                ("Maximum CAPE", values[.capeMax], .cape),
                ("Maximum vapor pressure deficit", values[.vaporPressureDeficitMax], .kilopascals),
                ("Solar energy", values[.shortwaveRadiationSum], .solarEnergy),
                ("Reference evapotranspiration", values[.referenceEvapotranspiration], .precipitation)
            ]
        default: return []
        }
    }
}

/// The additional model fields are disclosed by subject so every hour stays easy to scan.
struct WeatherHourExtraSections: View {
    let point: HourlyPoint
    let units: WeatherUnits
    let preferences: WeatherDetailSettings

    var body: some View {
        if let values = point.details {
            VStack(alignment: .leading, spacing: 10) {
                group(.hourlyPrecipitation, rows: [
                    ("Rain", values[.rain], .precipitation),
                    ("Showers", values[.showers], .precipitation),
                    ("Snowfall", values[.snowfall], .snowfall),
                    ("Snow depth", values[.snowDepth], .snowDepth),
                    ("Wind gusts", values[.windGusts], .wind)
                ])
                group(.hourlyAtmosphere, rows: [
                    ("Low clouds", values[.cloudCoverLow], .percent),
                    ("Middle clouds", values[.cloudCoverMid], .percent),
                    ("High clouds", values[.cloudCoverHigh], .percent),
                    ("Sea-level pressure", values[.seaLevelPressure], .pressure),
                    ("Surface pressure", values[.surfacePressure], .pressure),
                    ("Wet-bulb temperature", values[.wetBulbTemperature], .temperature),
                    ("Freezing level", values[.freezingLevelHeight], .height),
                    ("CAPE", values[.cape], .cape),
                    ("Vapor pressure deficit", values[.vaporPressureDeficit], .kilopascals)
                ])
                group(.hourlySunlight, rows: [
                    ("Sunshine", values[.sunshineDuration], .duration),
                    ("Clear-sky UV", values[.uvIndexClearSky], .number),
                    ("Solar radiation", values[.shortwaveRadiation], .radiation),
                    ("Direct radiation", values[.directRadiation], .radiation),
                    ("Diffuse radiation", values[.diffuseRadiation], .radiation),
                    ("Direct normal irradiance", values[.directNormalIrradiance], .radiation)
                ])
                group(.hourlyGround, rows: [
                    ("Surface soil temperature", values[.soilTemperature0cm], .temperature),
                    ("Soil temperature · 6 cm", values[.soilTemperature6cm], .temperature),
                    ("Soil temperature · 18 cm", values[.soilTemperature18cm], .temperature),
                    ("Soil temperature · 54 cm", values[.soilTemperature54cm], .temperature),
                    ("Soil moisture · 0–1 cm", values[.soilMoisture0To1cm], .soilMoisture),
                    ("Soil moisture · 1–3 cm", values[.soilMoisture1To3cm], .soilMoisture),
                    ("Soil moisture · 3–9 cm", values[.soilMoisture3To9cm], .soilMoisture),
                    ("Soil moisture · 9–27 cm", values[.soilMoisture9To27cm], .soilMoisture),
                    ("Soil moisture · 27–81 cm", values[.soilMoisture27To81cm], .soilMoisture),
                    ("Evapotranspiration", values[.evapotranspiration], .precipitation),
                    ("Reference evapotranspiration", values[.referenceEvapotranspiration], .precipitation)
                ])
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func group(_ section: WeatherDetailSection, rows: [(String, Double?, WeatherDetailUnit)]) -> some View {
        if preferences.isVisible(section) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title).fontWeight(.semibold)
                WeatherDetailGrid(rows: rows, units: units).padding(.top, 8)
            }
        }
    }
}

private struct WeatherDetailGrid: View {
    let rows: [(String, Double?, WeatherDetailUnit)]
    let units: WeatherUnits

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(row.2.format(row.1, units: units))
                        .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Units that are fixed by the provider stay explicit even with mixed user unit preferences.
enum WeatherDetailUnit {
    case temperature, precipitation, snowfall, hours, duration, number, percent, direction, visibility, pressure
    case cape, kilopascals, solarEnergy, radiation, height, snowDepth, soilMoisture, wind

    func format(_ value: Double?, units: WeatherUnits) -> String {
        guard let value, value.isFinite else { return "—" }
        switch self {
        case .temperature: return WeatherValue.temperature(value, units: units)
        case .precipitation: return String(format: "%.2f %@", value, units.precipitation.symbol)
        case .snowfall: return String(format: "%.1f %@", value, units.precipitation == .inches ? "in" : "cm")
        case .hours: return String(format: "%.1f hr", value)
        case .duration:
            guard (0...86_400).contains(value) else { return "—" }
            return "\(Int(value) / 3_600) hr \(Int(value) % 3_600 / 60) min"
        case .number: return String(format: "%.1f", value)
        case .percent: return String(format: "%.0f%%", value)
        case .direction: return WeatherValue.compassDirection(value)
        case .visibility: return WeatherDayDetailView.visibility(value, units: units)
        case .pressure: return WeatherValue.pressure(value, units: units)
        case .cape: return String(format: "%.0f J/kg", value)
        case .kilopascals: return String(format: "%.2f kPa", value)
        case .solarEnergy: return String(format: "%.1f MJ/m²", value)
        case .radiation: return String(format: "%.0f W/m²", value)
        case .height:
            return units.temperature == .fahrenheit
                ? String(format: "%.0f ft", value / 0.3048) : String(format: "%.0f m", value)
        case .snowDepth:
            return units.precipitation == .inches
                ? String(format: "%.1f in", value / 0.0254) : String(format: "%.1f cm", value * 100)
        case .soilMoisture: return String(format: "%.3f m³/m³", value)
        case .wind: return WeatherValue.wind(value, direction: nil, units: units)
        }
    }
}
