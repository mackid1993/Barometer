import Foundation

/// Weather service operations used by monitors and search interfaces.
public protocol WeatherClient: Sendable {
    /// Fetches a detailed forecast for one location.
    func forecast(for location: Location, units: WeatherUnits) async throws -> Forecast

    /// Searches for saved-location candidates.
    func geocode(_ query: String) async throws -> [GeocodingResult]

    /// Fetches current air quality for one location.
    func airQuality(for location: Location) async throws -> AirQuality
}

/// Errors surfaced by the Open-Meteo HTTP client.
public enum OpenMeteoError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, reason: String)
    case invalidTime(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Unable to construct the Open-Meteo request URL."
        case .invalidResponse: "Open-Meteo returned an invalid response."
        case .server(let statusCode, let reason): "Open-Meteo returned HTTP \(statusCode): \(reason)"
        case .invalidTime(let value): "Open-Meteo returned an invalid local time: \(value)"
        }
    }
}

/// Async client for Open-Meteo forecast, geocoding, and air-quality APIs.
public actor OpenMeteoClient: WeatherClient {
    private static let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast")
    private static let geocodingURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search")
    private static let airQualityURL = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
    private static let userAgent = "Barometer/0.1.0 (com.barometer.app)"

    private let session: URLSession

    /// Creates a client, optionally using an injected URL session for tests.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 15
            configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Fetches a detailed 10-day forecast for a saved location.
    public func forecast(for location: Location, units: WeatherUnits) async throws -> Forecast {
        let current = [
            "temperature_2m", "relative_humidity_2m", "apparent_temperature", "is_day", "precipitation",
            "rain", "showers", "snowfall", "weather_code", "cloud_cover", "pressure_msl", "surface_pressure",
            "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
        ]
        let hourly =
            [
                "temperature_2m", "apparent_temperature", "precipitation_probability", "precipitation",
                "weather_code", "wind_speed_10m", "wind_direction_10m", "uv_index", "is_day",
                "relative_humidity_2m", "dew_point_2m", "visibility", "cloud_cover",
            ] + HourlyWeatherMetric.allCases.map(\.rawValue)
        let daily =
            [
                "weather_code", "temperature_2m_max", "temperature_2m_min", "apparent_temperature_max",
                "apparent_temperature_min", "sunrise", "sunset", "uv_index_max", "precipitation_sum",
                "precipitation_probability_max", "wind_speed_10m_max", "wind_gusts_10m_max",
            ] + DailyWeatherMetric.allCases.map(\.rawValue) + ["moonrise", "moonset"]
        let url = try Self.url(
            base: Self.forecastURL,
            items: [
                URLQueryItem(name: "latitude", value: String(location.latitude)),
                URLQueryItem(name: "longitude", value: String(location.longitude)),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "forecast_days", value: "10"),
                URLQueryItem(name: "temperature_unit", value: units.temperature.rawValue),
                URLQueryItem(name: "wind_speed_unit", value: units.windSpeed.rawValue),
                URLQueryItem(name: "precipitation_unit", value: units.precipitation.queryValue),
                URLQueryItem(name: "current", value: current.joined(separator: ",")),
                URLQueryItem(name: "hourly", value: hourly.joined(separator: ",")),
                URLQueryItem(name: "daily", value: daily.joined(separator: ",")),
            ])
        let forecast = try Self.decodeForecast(try await data(from: url), for: location, units: units)
        guard
            let current = await currentConsensus(
                for: location,
                units: units,
                fallback: forecast.current
            )
        else {
            return forecast
        }
        return Forecast(
            location: forecast.location,
            units: forecast.units,
            timeZone: forecast.timeZone,
            current: current,
            hourly: forecast.hourly,
            daily: forecast.daily,
            fetchedAt: forecast.fetchedAt
        )
    }

    /// Searches Open-Meteo's geocoding index.
    public func geocode(_ query: String) async throws -> [GeocodingResult] {
        let url = try Self.url(
            base: Self.geocodingURL,
            items: [
                URLQueryItem(name: "name", value: query),
                URLQueryItem(name: "count", value: "10"),
                URLQueryItem(name: "language", value: "en"),
                URLQueryItem(name: "format", value: "json"),
            ])
        return try Self.decodeGeocoding(try await data(from: url))
    }

    /// Fetches current U.S. AQI and principal pollutant measurements.
    public func airQuality(for location: Location) async throws -> AirQuality {
        let url = try Self.url(
            base: Self.airQualityURL,
            items: [
                URLQueryItem(name: "latitude", value: String(location.latitude)),
                URLQueryItem(name: "longitude", value: String(location.longitude)),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10,ozone"),
            ])
        return try Self.decodeAirQuality(try await data(from: url), for: location)
    }

    static func decodeForecast(_ data: Data, for location: Location, units: WeatherUnits) throws -> Forecast {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let timeZone = TimeZone(identifier: response.timezone) ?? .gmt
        let currentTime = try parse(response.current.time, timeZone: timeZone, includesTime: true)
        let current = CurrentConditions(
            time: currentTime,
            temperature: response.current.temperature,
            apparentTemperature: response.current.apparentTemperature,
            humidity: response.current.humidity,
            precipitation: response.current.precipitation,
            rain: response.current.rain,
            showers: response.current.showers,
            snowfall: response.current.snowfall,
            code: WMOCode(rawValue: response.current.weatherCode),
            isDay: response.current.isDay == 1,
            cloudCover: response.current.cloudCover,
            pressureMSL: response.current.pressureMSL,
            surfacePressure: response.current.surfacePressure,
            windSpeed: response.current.windSpeed,
            windDirection: response.current.windDirection,
            windGusts: response.current.windGusts
        )
        let hourly = try response.hourly.time.indices.map { index in
            HourlyPoint(
                time: try parse(response.hourly.time[index], timeZone: timeZone, includesTime: true),
                temperature: response.hourly.temperature[safe: index] ?? nil,
                apparentTemperature: response.hourly.apparentTemperature[safe: index] ?? nil,
                precipitationProbability: response.hourly.precipitationProbability[safe: index] ?? nil,
                precipitation: response.hourly.precipitation[safe: index] ?? nil,
                code: (response.hourly.weatherCode[safe: index] ?? nil).map(WMOCode.init(rawValue:)),
                windSpeed: response.hourly.windSpeed[safe: index] ?? nil,
                windDirection: response.hourly.windDirection[safe: index] ?? nil,
                uvIndex: response.hourly.uvIndex[safe: index] ?? nil,
                isDay: (response.hourly.isDay[safe: index] ?? nil).map { $0 == 1 },
                humidity: response.hourly.humidity[safe: index] ?? nil,
                dewPoint: response.hourly.dewPoint[safe: index] ?? nil,
                visibility: Self.meters(
                    response.hourly.visibility[safe: index] ?? nil, unit: response.hourlyUnits?["visibility"]
                ),
                cloudCover: response.hourly.cloudCover[safe: index] ?? nil,
                details: HourlyWeatherDetails(
                    values: response.hourlyDetails.values(
                        at: index, units: response.hourlyUnits,
                        meterFields: [.snowDepth, .freezingLevelHeight]
                    ))
            )
        }
        let daily = try response.daily.time.indices.map { index in
            DailyPoint(
                date: try parse(response.daily.time[index], timeZone: timeZone, includesTime: false),
                code: (response.daily.weatherCode[safe: index] ?? nil).map(WMOCode.init(rawValue:)),
                high: response.daily.high[safe: index] ?? nil,
                low: response.daily.low[safe: index] ?? nil,
                apparentHigh: response.daily.apparentHigh[safe: index] ?? nil,
                apparentLow: response.daily.apparentLow[safe: index] ?? nil,
                sunrise: try optionalTime(response.daily.sunrise[safe: index] ?? nil, timeZone: timeZone),
                sunset: try optionalTime(response.daily.sunset[safe: index] ?? nil, timeZone: timeZone),
                uvIndexMax: response.daily.uvIndexMax[safe: index] ?? nil,
                precipitation: response.daily.precipitation[safe: index] ?? nil,
                precipitationProbability: response.daily.precipitationProbability[safe: index] ?? nil,
                windSpeedMax: response.daily.windSpeedMax[safe: index] ?? nil,
                windGustsMax: response.daily.windGustsMax[safe: index] ?? nil,
                details: DailyWeatherDetails(
                    values: response.dailyDetails.values(
                        at: index, units: response.dailyUnits, meterFields: [.visibilityMean, .visibilityMin]
                    ),
                    moonrise: try optionalTime(
                        response.dailyDetails.moonrise?[safe: index] ?? nil, timeZone: timeZone
                    ),
                    moonset: try optionalTime(
                        response.dailyDetails.moonset?[safe: index] ?? nil, timeZone: timeZone
                    ),
                    moonEventsAvailable: response.dailyDetails.hasMoonEvents
                )
            )
        }
        return Forecast(
            location: location,
            units: units,
            timeZone: timeZone,
            current: current,
            hourly: hourly,
            daily: daily,
            fetchedAt: Date()
        )
    }

    private static func meters(_ value: Double?, unit: String?) -> Double? {
        value.map { unit == "ft" ? $0 * 0.3048 : $0 }
    }

    static func decodeGeocoding(_ data: Data) throws -> [GeocodingResult] {
        try JSONDecoder().decode(GeocodingResponse.self, from: data).results?.map { result in
            GeocodingResult(
                id: result.id,
                name: result.name,
                admin: result.admin,
                country: result.country,
                latitude: result.latitude,
                longitude: result.longitude,
                timeZone: result.timeZone,
                population: result.population
            )
        } ?? []
    }

    static func decodeAirQuality(_ data: Data, for location: Location) throws -> AirQuality {
        let response = try JSONDecoder().decode(AirQualityResponse.self, from: data)
        let timeZone = TimeZone(identifier: response.timezone) ?? .gmt
        return AirQuality(
            location: location,
            time: try parse(response.current.time, timeZone: timeZone, includesTime: true),
            usAQI: response.current.usAQI,
            pm25: response.current.pm25,
            pm10: response.current.pm10,
            ozone: response.current.ozone
        )
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenMeteoError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let reason =
                (try? JSONDecoder().decode(APIErrorResponse.self, from: data).reason)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenMeteoError.server(statusCode: httpResponse.statusCode, reason: reason)
        }
        return data
    }

    private func currentConsensus(
        for location: Location,
        units: WeatherUnits,
        fallback: CurrentConditions
    ) async -> CurrentConditions? {
        let models = ["ncep_nbm_conus", "ecmwf_ifs025", "gem_seamless"]
        let session = self.session
        let readings = await withTaskGroup(of: CurrentConditions?.self, returning: [CurrentConditions].self) {
            group in
            for model in models {
                group.addTask {
                    try? await Self.fetchCurrent(
                        for: location,
                        units: units,
                        model: model,
                        session: session
                    )
                }
            }
            var values: [CurrentConditions] = []
            for await reading in group {
                if let reading {
                    values.append(reading)
                }
            }
            return values
        }
        return Self.consensusCurrent(readings, fallback: fallback)
    }

    private static func fetchCurrent(
        for location: Location,
        units: WeatherUnits,
        model: String,
        session: URLSession
    ) async throws -> CurrentConditions {
        let fields = [
            "temperature_2m", "relative_humidity_2m", "apparent_temperature", "is_day", "precipitation",
            "rain", "showers", "snowfall", "weather_code", "cloud_cover", "pressure_msl", "surface_pressure",
            "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
        ]
        let url = try url(
            base: forecastURL,
            items: [
                URLQueryItem(name: "latitude", value: String(location.latitude)),
                URLQueryItem(name: "longitude", value: String(location.longitude)),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "temperature_unit", value: units.temperature.rawValue),
                URLQueryItem(name: "wind_speed_unit", value: units.windSpeed.rawValue),
                URLQueryItem(name: "precipitation_unit", value: units.precipitation.queryValue),
                URLQueryItem(name: "current", value: fields.joined(separator: ",")),
                URLQueryItem(name: "models", value: model),
            ])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw OpenMeteoError.invalidResponse
        }
        return try decodeCurrent(data)
    }

    static func decodeCurrent(_ data: Data) throws -> CurrentConditions {
        let response = try JSONDecoder().decode(CurrentForecastResponse.self, from: data)
        let timeZone = TimeZone(identifier: response.timezone) ?? .gmt
        return try currentConditions(from: response.current, timeZone: timeZone)
    }

    static func consensusCurrent(
        _ readings: [CurrentConditions],
        fallback: CurrentConditions
    ) -> CurrentConditions? {
        guard !readings.isEmpty else {
            return nil
        }
        return CurrentConditions(
            time: readings.map(\.time).max() ?? readings[0].time,
            temperature: median(readings.map(\.temperature)) ?? readings[0].temperature,
            apparentTemperature: median(readings.compactMap(\.apparentTemperature)),
            humidity: median(readings.compactMap(\.humidity)),
            precipitation: median(readings.compactMap(\.precipitation)),
            rain: median(readings.compactMap(\.rain)),
            showers: median(readings.compactMap(\.showers)),
            snowfall: median(readings.compactMap(\.snowfall)),
            code: consensusCode(readings.map(\.code)) ?? fallback.code,
            isDay: consensusDaylight(readings.map(\.isDay)) ?? fallback.isDay,
            cloudCover: median(readings.compactMap(\.cloudCover)),
            pressureMSL: median(readings.compactMap(\.pressureMSL)),
            surfacePressure: median(readings.compactMap(\.surfacePressure)),
            windSpeed: median(readings.compactMap(\.windSpeed)),
            windDirection: median(readings.compactMap(\.windDirection)),
            windGusts: median(readings.compactMap(\.windGusts))
        )
    }

    private static func currentConditions(from response: CurrentResponse, timeZone: TimeZone) throws
        -> CurrentConditions
    {
        CurrentConditions(
            time: try parse(response.time, timeZone: timeZone, includesTime: true),
            temperature: response.temperature,
            apparentTemperature: response.apparentTemperature,
            humidity: response.humidity,
            precipitation: response.precipitation,
            rain: response.rain,
            showers: response.showers,
            snowfall: response.snowfall,
            code: WMOCode(rawValue: response.weatherCode),
            isDay: response.isDay == 1,
            cloudCover: response.cloudCover,
            pressureMSL: response.pressureMSL,
            surfacePressure: response.surfacePressure,
            windSpeed: response.windSpeed,
            windDirection: response.windDirection,
            windGusts: response.windGusts
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func consensusCode(_ values: [WMOCode]) -> WMOCode? {
        let counts = Dictionary(grouping: values, by: \WMOCode.rawValue).mapValues(\.count)
        guard
            let winner = counts.max(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }), winner.value >= 2
        else {
            return nil
        }
        return WMOCode(rawValue: winner.key)
    }

    private static func consensusDaylight(_ values: [Bool]) -> Bool? {
        let daylightCount = values.filter { $0 }.count
        guard daylightCount * 2 != values.count else {
            return nil
        }
        return daylightCount * 2 > values.count
    }

    private static func url(base: URL?, items: [URLQueryItem]) throws -> URL {
        guard let base, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw OpenMeteoError.invalidURL
        }
        components.queryItems = items
        guard let url = components.url else { throw OpenMeteoError.invalidURL }
        return url
    }

    private static func optionalTime(_ value: String?, timeZone: TimeZone) throws -> Date? {
        guard let value else { return nil }
        return try parse(value, timeZone: timeZone, includesTime: true)
    }

    private static func parse(_ value: String, timeZone: TimeZone, includesTime: Bool) throws -> Date {
        let configuration = DateFormatterCache.Configuration(
            pattern: .format(includesTime ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"),
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX"),
            calendarIdentifier: .gregorian
        )
        guard let date = DateFormatterCache.date(from: value, configuration) else {
            throw OpenMeteoError.invalidTime(value)
        }
        return date
    }
}

private struct ForecastResponse: Decodable {
    let timezone: String
    let current: CurrentResponse
    let hourly: HourlyResponse
    let daily: DailyResponse
    let hourlyDetails: WeatherDetailResponse<HourlyWeatherMetric>
    let dailyDetails: WeatherDetailResponse<DailyWeatherMetric>
    let hourlyUnits: [String: String]?
    let dailyUnits: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case timezone, current, hourly, daily
        case hourlyUnits = "hourly_units"
        case dailyUnits = "daily_units"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try values.decode(String.self, forKey: .timezone)
        current = try values.decode(CurrentResponse.self, forKey: .current)
        hourly = try values.decode(HourlyResponse.self, forKey: .hourly)
        daily = try values.decode(DailyResponse.self, forKey: .daily)
        hourlyDetails = try values.decode(WeatherDetailResponse<HourlyWeatherMetric>.self, forKey: .hourly)
        dailyDetails = try values.decode(WeatherDetailResponse<DailyWeatherMetric>.self, forKey: .daily)
        hourlyUnits = try values.decodeIfPresent([String: String].self, forKey: .hourlyUnits)
        dailyUnits = try values.decodeIfPresent([String: String].self, forKey: .dailyUnits)
    }
}

private struct CurrentForecastResponse: Decodable {
    let timezone: String
    let current: CurrentResponse
}

private struct CurrentResponse: Decodable {
    let time: String
    let temperature: Double
    let humidity: Double?
    let apparentTemperature: Double?
    let isDay: Int
    let precipitation: Double?
    let rain: Double?
    let showers: Double?
    let snowfall: Double?
    let weatherCode: Int
    let cloudCover: Double?
    let pressureMSL: Double?
    let surfacePressure: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let windGusts: Double?

    private enum CodingKeys: String, CodingKey {
        case time, precipitation, rain, showers, snowfall
        case temperature = "temperature_2m"
        case humidity = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case isDay = "is_day"
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
        case pressureMSL = "pressure_msl"
        case surfacePressure = "surface_pressure"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case windGusts = "wind_gusts_10m"
    }
}

private struct HourlyResponse: Decodable {
    let time: [String]
    let temperature: [Double?]
    let apparentTemperature: [Double?]
    let precipitationProbability: [Double?]
    let precipitation: [Double?]
    let weatherCode: [Int?]
    let windSpeed: [Double?]
    let windDirection: [Double?]
    let uvIndex: [Double?]
    let isDay: [Int?]
    let humidity: [Double?]
    let dewPoint: [Double?]
    let visibility: [Double?]
    let cloudCover: [Double?]

    private enum CodingKeys: String, CodingKey {
        case time, precipitation, visibility
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case uvIndex = "uv_index"
        case isDay = "is_day"
        case humidity = "relative_humidity_2m"
        case dewPoint = "dew_point_2m"
        case cloudCover = "cloud_cover"
    }
}

private struct DailyResponse: Decodable {
    let time: [String]
    let weatherCode: [Int?]
    let high: [Double?]
    let low: [Double?]
    let apparentHigh: [Double?]
    let apparentLow: [Double?]
    let sunrise: [String?]
    let sunset: [String?]
    let uvIndexMax: [Double?]
    let precipitation: [Double?]
    let precipitationProbability: [Double?]
    let windSpeedMax: [Double?]
    let windGustsMax: [Double?]

    private enum CodingKeys: String, CodingKey {
        case time, sunrise, sunset
        case weatherCode = "weather_code"
        case high = "temperature_2m_max"
        case low = "temperature_2m_min"
        case apparentHigh = "apparent_temperature_max"
        case apparentLow = "apparent_temperature_min"
        case uvIndexMax = "uv_index_max"
        case precipitation = "precipitation_sum"
        case precipitationProbability = "precipitation_probability_max"
        case windSpeedMax = "wind_speed_10m_max"
        case windGustsMax = "wind_gusts_10m_max"
    }
}

private struct GeocodingResponse: Decodable {
    let results: [GeocodingResponseItem]?
}

private struct GeocodingResponseItem: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String
    let admin: String?
    let timeZone: String
    let population: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, country, population
        case admin = "admin1"
        case timeZone = "timezone"
    }
}

private struct AirQualityResponse: Decodable {
    let timezone: String
    let current: AirQualityCurrentResponse
}

private struct AirQualityCurrentResponse: Decodable {
    let time: String
    let usAQI: Int?
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?

    private enum CodingKeys: String, CodingKey {
        case time, pm10, ozone
        case usAQI = "us_aqi"
        case pm25 = "pm2_5"
    }
}

private struct APIErrorResponse: Decodable {
    let reason: String
}

extension Collection {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
