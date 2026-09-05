import Foundation

/// Additional surface-weather fields requested from Open-Meteo for each forecast hour.
/// Raw values are the provider's exact parameter names, including its spelling of vapor.
public enum HourlyWeatherMetric: String, Codable, CaseIterable, Sendable {
    case rain, showers, snowfall
    case snowDepth = "snow_depth"
    case seaLevelPressure = "pressure_msl"
    case surfacePressure = "surface_pressure"
    case windGusts = "wind_gusts_10m"
    case cloudCoverLow = "cloud_cover_low"
    case cloudCoverMid = "cloud_cover_mid"
    case cloudCoverHigh = "cloud_cover_high"
    case wetBulbTemperature = "wet_bulb_temperature_2m"
    case sunshineDuration = "sunshine_duration"
    case uvIndexClearSky = "uv_index_clear_sky"
    case freezingLevelHeight = "freezing_level_height"
    case cape
    case vaporPressureDeficit = "vapour_pressure_deficit"
    case evapotranspiration
    case referenceEvapotranspiration = "et0_fao_evapotranspiration"
    case shortwaveRadiation = "shortwave_radiation"
    case directRadiation = "direct_radiation"
    case diffuseRadiation = "diffuse_radiation"
    case directNormalIrradiance = "direct_normal_irradiance"
    case soilTemperature0cm = "soil_temperature_0cm"
    case soilTemperature6cm = "soil_temperature_6cm"
    case soilTemperature18cm = "soil_temperature_18cm"
    case soilTemperature54cm = "soil_temperature_54cm"
    case soilMoisture0To1cm = "soil_moisture_0_to_1cm"
    case soilMoisture1To3cm = "soil_moisture_1_to_3cm"
    case soilMoisture3To9cm = "soil_moisture_3_to_9cm"
    case soilMoisture9To27cm = "soil_moisture_9_to_27cm"
    case soilMoisture27To81cm = "soil_moisture_27_to_81cm"
}

/// Additional daily summaries, in provider units consistent with the forecast's unit selection.
public enum DailyWeatherMetric: String, Codable, CaseIterable, Sendable {
    case rainSum = "rain_sum"
    case showersSum = "showers_sum"
    case snowfallSum = "snowfall_sum"
    case precipitationHours = "precipitation_hours"
    case daylightDuration = "daylight_duration"
    case sunshineDuration = "sunshine_duration"
    case windDirectionDominant = "wind_direction_10m_dominant"
    case shortwaveRadiationSum = "shortwave_radiation_sum"
    case referenceEvapotranspiration = "et0_fao_evapotranspiration"
    case uvIndexClearSkyMax = "uv_index_clear_sky_max"
    case temperatureMean = "temperature_2m_mean"
    case apparentTemperatureMean = "apparent_temperature_mean"
    case humidityMean = "relative_humidity_2m_mean"
    case humidityMin = "relative_humidity_2m_min"
    case humidityMax = "relative_humidity_2m_max"
    case dewPointMean = "dew_point_2m_mean"
    case cloudCoverMean = "cloud_cover_mean"
    case pressureMean = "pressure_msl_mean"
    case surfacePressureMean = "surface_pressure_mean"
    case visibilityMean = "visibility_mean"
    case visibilityMin = "visibility_min"
    case capeMax = "cape_max"
    case wetBulbTemperatureMean = "wet_bulb_temperature_2m_mean"
    case vaporPressureDeficitMax = "vapour_pressure_deficit_max"
    case moonPhase = "moon_phase"
}

/// Optional hourly details; missing or model-unavailable values remain absent.
public struct HourlyWeatherDetails: Codable, Equatable, Sendable {
    private let values: [HourlyWeatherMetric: Double]

    /// Creates details from the values actually returned by the provider.
    public init(values: [HourlyWeatherMetric: Double]) {
        self.values = values.filter { $0.value.isFinite }
    }

    /// A value in the provider's units, or nil when no forecast value was returned.
    public subscript(_ metric: HourlyWeatherMetric) -> Double? { values[metric] }
}

/// Optional daily details and location-specific lunar rise/set events.
public struct DailyWeatherDetails: Codable, Equatable, Sendable {
    private let values: [DailyWeatherMetric: Double]
    /// Moonrise in the selected location, or nil when no event was returned for that day.
    public let moonrise: Date?
    /// Moonset in the selected location, or nil when no event was returned for that day.
    public let moonset: Date?
    /// Distinguishes a provider's null event from an older forecast that never requested lunar events.
    public let moonEventsAvailable: Bool

    /// Creates daily details without substituting values for missing provider data.
    public init(
        values: [DailyWeatherMetric: Double], moonrise: Date? = nil, moonset: Date? = nil,
        moonEventsAvailable: Bool = false
    ) {
        self.values = values.filter { $0.value.isFinite }
        self.moonrise = moonrise
        self.moonset = moonset
        self.moonEventsAvailable = moonEventsAvailable
    }

    /// A value in the provider's units, or nil when no forecast value was returned.
    public subscript(_ metric: DailyWeatherMetric) -> Double? { values[metric] }
}
