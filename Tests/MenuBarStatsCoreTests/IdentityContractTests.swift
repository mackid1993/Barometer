import Testing
@testable import MenuBarStatsCore

@Suite("IdentityContractTests")
struct IdentityContractTests {
    @Test("module autosave names remain fixed")
    func moduleAutosaveNamesRemainFixed() {
        let expectedAutosaveNames = [
            "MenuBarStats.CPU",
            "MenuBarStats.GPU",
            "MenuBarStats.Memory",
            "MenuBarStats.Disks",
            "MenuBarStats.Network",
            "MenuBarStats.Sensors",
            "MenuBarStats.Battery",
            "MenuBarStats.Weather",
            "MenuBarStats.Time",
            "MenuBarStats.Combined",
        ]

        #expect(ModuleID.allCases.map(\.autosaveName) == expectedAutosaveNames)
    }
}
