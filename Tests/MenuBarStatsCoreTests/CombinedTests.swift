import Foundation
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

    @Test("a deleted stack never releases its identity for reuse")
    func stackIdentityDiscipline() {
        var settings = StacksSettings()
        #expect(settings.stacks.isEmpty)

        for _ in 0..<3 {
            let id = settings.allocateID()
            settings.stacks.append(StackSettings(id: id))
        }
        #expect(settings.stacks.map(\.id) == [1, 2, 3])

        // Deleting the middle stack must not hand id 2 out again: a new stack given the same
        // autosave name would inherit the deleted item's saved menu bar position.
        settings.remove(id: 2)
        #expect(settings.stacks.map(\.id) == [1, 3])
        #expect(settings.allocateID() == 4)

        settings.remove(id: 1)
        settings.remove(id: 3)
        settings.remove(id: 4)
        #expect(settings.stacks.isEmpty)
        #expect(settings.allocateID() == 5)

        #expect(StacksSettings(stacks: [StackSettings(id: 1), StackSettings(id: 1)]).stacks.count == 1)
    }

    @Test("a new stack starts empty rather than prefilled")
    func newStacksStartEmpty() {
        #expect(StacksSettings().stacks.isEmpty)
        #expect(StackSettings(id: 1).metrics.isEmpty)
    }

    @Test("the high-water mark survives a settings round trip")
    func identityCounterRoundTrips() throws {
        var settings = StacksSettings()
        for _ in 0..<3 {
            let id = settings.allocateID()
            settings.stacks.append(StackSettings(id: id))
        }
        settings.remove(id: 3)

        var decoded = try JSONDecoder().decode(
            StacksSettings.self,
            from: try JSONEncoder().encode(settings)
        )

        #expect(decoded.stacks.map(\.id) == [1, 2])
        #expect(decoded.allocateID() == 4)
    }

    @Test("stacks migrate an enabled Combined item into the first stack")
    func migratesCombinedMembership() {
        let combined = CombinedSettings(members: [.gpu, .network], hidesIndividualMembers: true)
        let stacks = StacksSettings.migrating(from: combined, isCombinedEnabled: true)

        #expect(stacks.stacks.count == 1)
        #expect(stacks.stacks[0].id == 1)
        #expect(stacks.stacks[0].isEnabled)
        #expect(stacks.stacks[0].metrics == [.gpuUtilization, .networkDownload])
        #expect(stacks.stacks[0].hidesSourceItems)
        #expect(stacks.hiddenSourceModules == [.gpu, .network])

        // Someone who never turned Combined on gets no stacks rather than a prefilled one.
        #expect(StacksSettings.migrating(from: combined, isCombinedEnabled: false).stacks.isEmpty)
    }

    @Test("every stack metric names exactly one owning module")
    func metricsNameOneModule() {
        for metric in StackMetric.allCases {
            #expect(metric.module != .combined)
            #expect(!metric.label.isEmpty)
            #expect(!metric.displayName.isEmpty)
        }
        #expect(StackMetric.primary(for: .combined) == nil)
        #expect(StackMetric.byModule.allSatisfy { !$0.metrics.isEmpty })
    }
}
