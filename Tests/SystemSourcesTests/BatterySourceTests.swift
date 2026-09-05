import Foundation
import Testing

@testable import SystemSources

@Suite("BatterySourceTests")
struct BatterySourceTests {
    @Test
    func decodesUnsignedSignedAmperage() {
        #expect(BatterySource.signedMilliamps(raw: 0) == 0)
        #expect(BatterySource.signedMilliamps(raw: UInt64(UInt32.max) - 557) == -558)
        #expect(BatterySource.signedMilliamps(raw: 1_250) == 1_250)
    }

    @Test
    func rejectsCalculatingTimeEstimateSentinels() {
        #expect(BatterySource.minutes(NSNumber(value: 495)) == 495)
        // IOPS publishes -1 and AppleSmartBattery publishes 65535 while no estimate exists.
        #expect(BatterySource.minutes(NSNumber(value: -1)) == nil)
        #expect(BatterySource.minutes(NSNumber(value: 65_535)) == nil)
        #expect(BatterySource.minutes(NSNumber(value: 0)) == nil)
        #expect(BatterySource.minutes(nil) == nil)
        #expect(BatterySource.minutes("495") == nil)
    }

    @Test
    func normalizesTemperatureAndHealth() {
        #expect(BatterySource.celsius(raw: 3_129) == 31.29)
        #expect(BatterySource.celsius(raw: 0) == nil)
        #expect(BatterySource.celsius(raw: 65_535) == nil)
        #expect(BatterySource.healthPercent(fullChargeCapacity: 8_571, designCapacity: 8_579) == 99.90674903834946)
        #expect(BatterySource.healthPercent(fullChargeCapacity: 8_571, designCapacity: 0) == nil)
    }

    @Test
    func normalizesBatteryConditionFromPublishedAndFallbackSignals() {
        #expect(condition(publishedHealth: "Good", healthPercent: nil) == "Normal")
        #expect(condition(publishedHealth: "Fair", healthPercent: nil) == "Service Recommended")
        #expect(condition(publishedHealth: nil, healthPercent: 100) == "Normal")
        #expect(condition(publishedHealth: nil, healthPercent: 79.9) == "Service Recommended")
        #expect(condition(publishedHealth: nil, permanentFailureStatus: 1, healthPercent: 100) == "Service Recommended")
        #expect(condition(publishedHealth: nil, healthPercent: nil) == nil)
    }

    @Test
    func readsLiveLaptopWhenAvailable() throws {
        let source = BatterySource()
        guard source.isAvailable else {
            return
        }

        let sample = try source.read()

        #expect((0...100).contains(sample.chargePercent))
        #expect(sample.voltageVolts.map { $0 > 0 } ?? true)
        #expect(sample.temperatureCelsius.map { (0...60).contains($0) } ?? true)
        #expect(sample.cycleCount.map { $0 >= 0 } ?? true)
        if sample.healthPercent != nil {
            #expect(sample.condition != nil)
        }
    }

    private func condition(
        publishedHealth: String?,
        publishedCondition: String? = nil,
        hasFailureModes: Bool = false,
        permanentFailureStatus: Int? = nil,
        healthPercent: Double?
    ) -> String? {
        BatterySource.condition(
            publishedHealth: publishedHealth,
            publishedCondition: publishedCondition,
            hasFailureModes: hasFailureModes,
            permanentFailureStatus: permanentFailureStatus,
            healthPercent: healthPercent
        )
    }
}
