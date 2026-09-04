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
        // Stack 1 keeps the original Combined name so an upgrading user's item keeps its position.
        #expect(ModuleID.combined.autosaveName(instance: 1) == "Barometer.Combined")
        #expect(ModuleID.combined.autosaveName(instance: 2) == "Barometer.Combined.2")
        #expect(ModuleID.combined.autosaveName(instance: 4) == "Barometer.Combined.4")
        #expect(StatusItemIdentity(module: .combined, instance: 3).displayName == "Combined 3")
    }

    @Test("movable children retain distinct static labels")
    func movableChildrenRetainDistinctStaticLabels() {
        let labels = ModuleID.allCases.map(\.displayName)

        #expect(Set(labels).count == ModuleID.allCases.count)
        #expect(StatusItemIdentity(module: .network).displayName == "Network")
        #expect(StatusItemIdentity(module: .weather).displayName == "Weather")
        #expect(StatusItemIdentity(module: .sensors, instance: 2).displayName == "Sensors 2")
    }
}
