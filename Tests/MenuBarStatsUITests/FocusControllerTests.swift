import SystemSources
import Testing
@testable import MenuBarStatsUI

@Suite("FocusControllerTests")
@MainActor
struct FocusControllerTests {
    private let work = FocusMode(id: "work", name: "Work", symbolName: "briefcase.fill")

    @Test("refresh publishes the real source snapshot")
    func refresh() async {
        let expected = FocusSnapshot.active(mode: work, availableModes: [work])
        let controller = FocusController(
            readOperation: { expected },
            activateOperation: { _ in .unavailable },
            deactivateOperation: { .unavailable }
        )

        await controller.refresh()

        #expect(controller.snapshot == expected)
    }

    @Test("a successful mode selection refreshes state after the native operation")
    func activate() async {
        var selected: [FocusMode] = []
        let expected = FocusSnapshot.active(mode: work, availableModes: [work])
        let controller = FocusController(
            snapshot: .inactive(availableModes: [work]),
            readOperation: { expected },
            activateOperation: {
                selected.append($0)
                return .applied
            },
            deactivateOperation: { .unavailable }
        )

        await controller.activate(work)

        #expect(selected == [work])
        #expect(controller.snapshot == expected)
        #expect(controller.controlError == nil)
        #expect(!controller.isChanging)
    }

    @Test("an unavailable native control reports the limitation without inventing state")
    func unavailableControl() async {
        let initial = FocusSnapshot.active(mode: work, availableModes: [work])
        let controller = FocusController(
            snapshot: initial,
            readOperation: { .unavailable },
            activateOperation: { _ in .unavailable },
            deactivateOperation: { .unavailable }
        )

        await controller.deactivate()

        #expect(controller.snapshot == initial)
        #expect(controller.controlError == "Native Focus controls are unavailable for Barometer.")
        #expect(!controller.isChanging)
    }

    @Test("a failed native attempt does not claim Focus changed")
    func failedControl() async {
        let initial = FocusSnapshot.inactive(availableModes: [work])
        let controller = FocusController(
            snapshot: initial,
            readOperation: { .unavailable },
            activateOperation: { _ in .failed },
            deactivateOperation: { .unavailable }
        )

        await controller.activate(work)

        #expect(controller.snapshot == initial)
        #expect(controller.controlError == "macOS could not apply the Focus change.")
    }

    @Test("a read finishing after stop cannot publish stale Focus state")
    func stoppedRead() async {
        let gate = FocusReadGate()
        let controller = FocusController(
            readOperation: { await gate.read() },
            activateOperation: { _ in .unavailable },
            deactivateOperation: { .unavailable }
        )
        controller.start()
        while !gate.hasStarted { await Task.yield() }

        controller.stop()
        gate.resume(with: .active(mode: work, availableModes: [work]))
        await Task.yield()

        #expect(controller.snapshot == .unavailable)
    }
}

@MainActor
private final class FocusReadGate {
    private var continuation: CheckedContinuation<FocusSnapshot, Never>?
    private(set) var hasStarted = false

    func read() async -> FocusSnapshot {
        hasStarted = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume(with snapshot: FocusSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}
