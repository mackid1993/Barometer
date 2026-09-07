import Intents
import Testing
@testable import SystemSources

@Suite("FocusSourceTests")
struct FocusSourceTests {
    private let work = FocusMode(id: "work", name: "Work", symbolName: "briefcase.fill")

    @Test("the public API is used only after the user has already authorized Focus sharing")
    func publicAuthorization() {
        #expect(FocusSource.publicSnapshot(authorizationStatus: .notDetermined, isFocused: true) == .unavailable)
        #expect(FocusSource.publicSnapshot(authorizationStatus: .denied, isFocused: true) == .unavailable)
        #expect(FocusSource.publicSnapshot(authorizationStatus: .authorized, isFocused: nil) == .unavailable)
        #expect(FocusSource.publicSnapshot(authorizationStatus: .authorized, isFocused: false)
            == .inactive(availableModes: []))
        #expect(FocusSource.publicSnapshot(authorizationStatus: .authorized, isFocused: true)
            == .active(mode: nil, availableModes: []))
    }

    @Test("snapshots distinguish unavailable, inactive, and mode-withheld active state")
    func snapshotAccessors() {
        #expect(FocusSnapshot.unavailable.isActive == nil)
        #expect(FocusSnapshot.inactive(availableModes: [work]).isActive == false)
        #expect(FocusSnapshot.active(mode: work, availableModes: [work]).isActive == true)
        #expect(FocusSnapshot.active(mode: work, availableModes: [work]).activeMode == work)
        #expect(FocusSnapshot.active(mode: nil, availableModes: []).activeMode == nil)
        #expect(FocusSnapshot.inactive(availableModes: [work]).availableModes == [work])
    }

    @Test("the Focus database distinguishes current assertions from invalidation history")
    func databaseSnapshots() throws {
        let configurations = Data("""
        {"data":[{"modeConfigurations":{"work":{"mode":{"modeIdentifier":"work","name":"Work",\
        "symbolImageName":"briefcase.fill"}},"sleep":{"mode":{"modeIdentifier":"sleep","name":"Sleep",\
        "symbolImageName":"bed.double.fill"}}}}],"header":{"version":3}}
        """.utf8)
        let inactiveAssertions = Data("""
        {"data":[{"storeInvalidationRecords":[{"invalidationAssertion":{"assertionDetails":{\
        "assertionDetailsModeIdentifier":"work"}}}]}],"header":{"version":8}}
        """.utf8)
        let activeAssertions = Data("""
        {"data":[{"storeAssertionRecords":[{"assertion":{"assertionDetails":{\
        "assertionDetailsModeIdentifier":"work"}}}]}],"header":{"version":8}}
        """.utf8)
        #expect(FocusSource.databaseSnapshot(
            configurationsData: configurations,
            assertionsData: inactiveAssertions
        ) == .inactive(availableModes: []))
        #expect(FocusSource.databaseSnapshot(
            configurationsData: configurations,
            assertionsData: activeAssertions
        ) == .active(mode: work, availableModes: []))
    }

    @Test("an assertion for a mode missing from configurations still proves Focus is active")
    func unknownActiveMode() {
        let configurations = Data("""
        {"data":[{"modeConfigurations":{}}],"header":{"version":3}}
        """.utf8)
        let assertions = Data("""
        {"data":[{"storeAssertionRecords":[{"assertionDetails":{\
        "assertionDetailsModeIdentifier":"future-mode"}}]}],"header":{"version":8}}
        """.utf8)

        #expect(FocusSource.databaseSnapshot(
            configurationsData: configurations,
            assertionsData: assertions
        ) == .active(mode: nil, availableModes: []))
    }

    @Test("unknown or malformed current assertion fields do not claim Focus is off")
    func rejectsUnknownAssertionSchema() {
        let configurations = Data("""
        {"data":[{"modeConfigurations":{}}],"header":{"version":3}}
        """.utf8)
        let unknown = Data("""
        {"data":[{"futureAssertionRecords":[]}],"header":{"version":8}}
        """.utf8)
        let malformed = Data("""
        {"data":[{"storeAssertionRecords":[{"assertionDetails":{}}]}],"header":{"version":8}}
        """.utf8)

        #expect(FocusSource.databaseSnapshot(configurationsData: configurations, assertionsData: unknown) == nil)
        #expect(FocusSource.databaseSnapshot(configurationsData: configurations, assertionsData: malformed) == nil)
    }

    @Test("all database partitions contribute configured modes")
    func configurationPartitions() {
        let configurations = Data("""
        {"data":[{"modeConfigurations":{"work":{"mode":{"modeIdentifier":"work","name":"Work",\
        "symbolImageName":"briefcase.fill"}}}},{"modeConfigurations":{"personal":{"mode":{\
        "modeIdentifier":"personal","name":"Personal","symbolImageName":"person.fill"}}}}],\
        "header":{"version":3}}
        """.utf8)
        let assertions = Data("""
        {"data":[{"storeInvalidationRecords":[]},{"storeAssertionRecords":[{"assertionDetails":{\
        "assertionDetailsModeIdentifier":"personal"}}]}],"header":{"version":8}}
        """.utf8)
        let personal = FocusMode(id: "personal", name: "Personal", symbolName: "person.fill")

        #expect(FocusSource.databaseSnapshot(
            configurationsData: configurations,
            assertionsData: assertions
        ) == .active(mode: personal, availableModes: []))
    }
}
