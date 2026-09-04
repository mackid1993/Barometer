import MenuBarStatsCore
import Testing

@Suite("CombinedTests")
struct CombinedTests {
    @Test("membership normalization removes duplicates and recursive Combined membership")
    func membershipNormalization() {
        var settings = CombinedSettings(members: [.cpu, .combined, .cpu, .memory])
        settings.normalize()

        #expect(settings.members == [.cpu, .memory])
    }

    @Test("production defaults preserve individual status items")
    func defaults() {
        let settings = CombinedSettings()

        #expect(settings.members == [.cpu, .memory])
        #expect(!settings.hidesIndividualMembers)
        #expect(settings.showsSeparators)
    }
}
