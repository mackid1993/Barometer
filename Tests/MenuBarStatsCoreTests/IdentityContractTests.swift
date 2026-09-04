import Testing
@testable import MenuBarStatsCore

@Suite("IdentityContractTests")
struct IdentityContractTests {
    @Test("module autosave names remain fixed")
    func moduleAutosaveNamesRemainFixed() {
        let expectedAutosaveNames = [
            "Barometer.CPU",
            "Barometer.GPU",
            "Barometer.Memory",
            "Barometer.Disks",
            "Barometer.Network",
            "Barometer.Sensors",
            "Barometer.Battery",
            "Barometer.Weather",
            "Barometer.Time",
            "Barometer.Combined",
        ]

        #expect(ModuleID.allCases.map(\.autosaveName) == expectedAutosaveNames)
        #expect(ModuleID.sensors.autosaveName(instance: 2) == "Barometer.Sensors.2")
        #expect(StatusItemIdentity(module: .sensors, instance: 3).displayName == "Sensors 3")
    }
}
