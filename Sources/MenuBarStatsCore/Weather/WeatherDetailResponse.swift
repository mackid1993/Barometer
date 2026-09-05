import Foundation

/// Decodes the optional metric catalog without making older cached/provider payloads invalid.
struct WeatherDetailResponse<Metric: RawRepresentable & CaseIterable & Hashable>: Decodable
where Metric.RawValue == String {
    private let metrics: [Metric: [Double?]]
    let moonrise: [String?]?
    let moonset: [String?]?
    let hasMoonEvents: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WeatherDetailKey.self)
        var metrics: [Metric: [Double?]] = [:]
        for metric in Metric.allCases {
            if let values = try container.decodeIfPresent([Double?].self, forKey: WeatherDetailKey(metric.rawValue)) {
                metrics[metric] = values
            }
        }
        self.metrics = metrics
        moonrise = try container.decodeIfPresent([String?].self, forKey: WeatherDetailKey("moonrise"))
        moonset = try container.decodeIfPresent([String?].self, forKey: WeatherDetailKey("moonset"))
        hasMoonEvents = moonrise != nil && moonset != nil
    }

    /// Extracts one forecast point, skipping null/short arrays and normalizing length fields to meters.
    func values(at index: Int, units: [String: String]?, meterFields: Set<Metric>) -> [Metric: Double] {
        var result: [Metric: Double] = [:]
        for (metric, values) in metrics {
            guard values.indices.contains(index), let value = values[index], value.isFinite else { continue }
            result[metric] = meterFields.contains(metric) && units?[metric.rawValue] == "ft" ? value * 0.3048 : value
        }
        return result
    }
}

private struct WeatherDetailKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
