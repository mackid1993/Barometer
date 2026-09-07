import Foundation
import Observation
import SystemSources

/// Observable Focus state used by the menu bar pill and its controls.
@MainActor
@Observable
public final class FocusController {
    public private(set) var snapshot: FocusSnapshot = .unavailable
    public private(set) var isChanging = false
    public private(set) var controlError: String?

    @ObservationIgnored private let readOperation: @MainActor () async -> FocusSnapshot
    @ObservationIgnored private let activateOperation: @MainActor (FocusMode) async -> FocusControlResult
    @ObservationIgnored private let deactivateOperation: @MainActor () async -> FocusControlResult
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshSequence = 0

    /// Polling cadence while the Focus module is enabled.
    public static let refreshInterval: Duration = .seconds(2)

    /// Creates a controller over the system Focus source.
    public init(source: FocusSource = FocusSource()) {
        readOperation = { await source.read() }
        activateOperation = { mode in await source.activate(mode) }
        deactivateOperation = { await source.deactivate() }
    }

    init(
        snapshot: FocusSnapshot = .unavailable,
        readOperation: @escaping @MainActor () async -> FocusSnapshot,
        activateOperation: @escaping @MainActor (FocusMode) async -> FocusControlResult,
        deactivateOperation: @escaping @MainActor () async -> FocusControlResult
    ) {
        self.snapshot = snapshot
        self.readOperation = readOperation
        self.activateOperation = activateOperation
        self.deactivateOperation = deactivateOperation
    }

    /// Starts updates. Calling this again while running has no effect.
    public func start() {
        guard refreshTask == nil else { return }
        generation += 1
        let startedGeneration = generation
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh(generation: startedGeneration)
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// Stops updates while preserving the last real state for rendering.
    public func stop() {
        generation += 1
        refreshSequence += 1
        refreshTask?.cancel()
        refreshTask = nil
        isChanging = false
        controlError = nil
    }

    /// Reads Focus now.
    public func refresh() async {
        await refresh(generation: generation)
    }

    /// Activates a mode in response to a user selection.
    public func activate(_ mode: FocusMode) async {
        guard !isChanging else { return }
        isChanging = true
        controlError = nil
        let controlGeneration = generation
        let result = await activateOperation(mode)
        guard controlGeneration == generation else { return }
        await finish(result, generation: controlGeneration)
    }

    /// Turns Focus off in response to a user selection.
    public func deactivate() async {
        guard !isChanging else { return }
        isChanging = true
        controlError = nil
        let controlGeneration = generation
        let result = await deactivateOperation()
        guard controlGeneration == generation else { return }
        await finish(result, generation: controlGeneration)
    }

    private func finish(_ result: FocusControlResult, generation: Int) async {
        isChanging = false
        switch result {
        case .applied:
            await refresh(generation: generation)
        case .unavailable:
            controlError = "Native Focus controls are unavailable for Barometer."
        case .failed:
            controlError = "macOS could not apply the Focus change."
        }
    }

    private func refresh(generation: Int) async {
        guard generation == self.generation else { return }
        refreshSequence += 1
        let sequence = refreshSequence
        let updated = await readOperation()
        guard generation == self.generation, sequence == refreshSequence, !Task.isCancelled else { return }
        snapshot = updated
    }
}
