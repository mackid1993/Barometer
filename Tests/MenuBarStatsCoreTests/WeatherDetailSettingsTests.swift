import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("WeatherDetailSettingsTests")
struct WeatherDetailSettingsTests {
    @Test("Legacy settings retain location and units and default to all detail sections")
    func legacySettings() throws {
        var original = WeatherSettings(units: .metric, refreshIntervalMinutes: 30)
        original.primaryLocationID = "saved-city"
        let encoded = try JSONEncoder().encode(original)
        var document = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        document.removeValue(forKey: "detailSections")
        let restored = try JSONDecoder().decode(
            WeatherSettings.self, from: JSONSerialization.data(withJSONObject: document))
        #expect(restored.units == .metric)
        #expect(restored.refreshIntervalMinutes == 30)
        #expect(restored.primaryLocationID == "saved-city")
        #expect(restored.detailSections.showsAll)
        #expect(WeatherDetailSection.allCases.allSatisfy(restored.detailSections.isVisible))
    }

    @Test("Custom choices survive all-details mode and persisted app settings")
    func modeRoundTrip() throws {
        var app = AppSettings()
        app.weather.detailSections.showsAll = false
        app.weather.detailSections.setSelected(false, for: .sunMoon)
        app.weather.detailSections.setSelected(false, for: .hourlyGround)
        #expect(!app.weather.detailSections.isVisible(.sunMoon))
        app.weather.detailSections.showsAll = true
        #expect(app.weather.detailSections.isVisible(.sunMoon))
        var restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(app))
        #expect(restored == app)
        restored.weather.detailSections.showsAll = false
        #expect(!restored.weather.detailSections.isVisible(.sunMoon))
        #expect(!restored.weather.detailSections.isVisible(.hourlyGround))
        #expect(restored.weather.detailSections.isVisible(.precipitation))
    }

    @Test("Hidden hourly parent suppresses child sections without losing their selections")
    func hourlyParent() {
        var preferences = WeatherDetailSettings(showsAll: false)
        preferences.setSelected(false, for: .hourly)
        #expect(!preferences.isVisible(.hourlyPrecipitation))
        #expect(preferences.isSelected(.hourlyPrecipitation))
        preferences.setSelected(true, for: .hourly)
        #expect(preferences.isVisible(.hourlyPrecipitation))
    }

    @Test("Practical weather starts expanded and advanced groups start collapsed")
    func expandedDefaults() {
        for section in [WeatherDetailSection.dayMetrics, .precipitation, .airComfort, .hourly, .sunMoon] {
            #expect(section.isExpandedByDefault)
        }
        for section in [WeatherDetailSection.atmosphere, .hourlyGround, .hourlyAtmosphere] {
            #expect(!section.isExpandedByDefault)
        }
    }

    @Test("New section keys and partial preferences do not erase saved settings")
    func forwardCompatibleKeys() throws {
        let data = Data(#"{"showsAll":false,"hiddenSections":["sunMoon","futureSection"]}"#.utf8)
        let preferences = try JSONDecoder().decode(WeatherDetailSettings.self, from: data)
        #expect(!preferences.isVisible(.sunMoon))
        #expect(preferences.isVisible(.hourly))
        let empty = try JSONDecoder().decode(WeatherDetailSettings.self, from: Data("{}".utf8))
        #expect(empty.showsAll)
    }
}
