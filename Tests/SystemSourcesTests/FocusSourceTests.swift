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
}
