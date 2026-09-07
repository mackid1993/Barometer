import AppKit
import Foundation
import Observation
import SystemSources

/// State presented by Barometer's Now Playing menu bar pill and popup.
public enum NowPlayingControllerState: Equatable {
    case loading
    case unavailable
    case idle
    case active(NowPlayingSnapshot)
}

/// Visible-only Now Playing reader and transport controller.
///
/// `start()` is called only while the module is enabled. The controller samples slowly for the
/// menu bar pill and more quickly while its popup is visible. `stop()` cancels all sampling.
@MainActor
@Observable
public final class NowPlayingController {
    /// Current availability and playback state.
    public private(set) var state: NowPlayingControllerState = .loading

    /// The command currently awaiting MediaRemote, if any.
    public private(set) var pendingCommand: NowPlayingCommand?

    /// Actionable transport error shown in the popup.
    public private(set) var commandError: String?

    /// Current item when a player has supplied metadata.
    public var snapshot: NowPlayingSnapshot? {
        guard case let .active(snapshot) = state else { return nil }
        return snapshot
    }

    private let source: NowPlayingSource?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var isDropdownVisible = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRefreshing = false

    /// Creates a controller over the system Now Playing source.
    public init(source: NowPlayingSource = NowPlayingSource()) {
        self.source = source
    }

    /// Creates a controller with fixed state and no MediaRemote access for previews and screen tests.
    public init(preset state: NowPlayingControllerState, commandError: String? = nil) {
        source = nil
        self.state = state
        self.commandError = commandError
    }

    /// Starts visible-only sampling. Repeated calls keep the existing task.
    public func start() {
        guard let source, updateTask == nil else { return }
        generation += 1
        let startedGeneration = generation
        state = .loading
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.refreshAndInterval(generation: startedGeneration) else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Stops all reads while the module is disabled or hidden.
    public func stop() {
        generation += 1
        updateTask?.cancel()
        updateTask = nil
        isDropdownVisible = false
        pendingCommand = nil
        commandError = nil
        state = .idle
    }

    /// Switches to faster refreshes while the controls popup is open.
    public func setDropdownVisible(_ visible: Bool) {
        isDropdownVisible = visible
        guard visible, updateTask != nil else { return }
        let currentGeneration = generation
        Task { [weak self] in await self?.refresh(generation: currentGeneration) }
    }

    /// Refreshes once without changing the controller's running state.
    public func refresh() async {
        await refresh(generation: generation)
    }

    /// Sends one native transport command and refreshes the displayed state after acceptance.
    public func perform(_ command: NowPlayingCommand) async {
        guard pendingCommand == nil else { return }
        guard let source else {
            commandError = "System media controls are unavailable in this preview."
            return
        }
        let commandGeneration = generation
        pendingCommand = command
        commandError = nil
        let result = await source.send(command)
        guard commandGeneration == generation else { return }
        pendingCommand = nil
        switch result {
        case .accepted:
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, commandGeneration == generation else { return }
            await refresh(generation: commandGeneration)
        case .unavailable:
            state = .unavailable
            commandError = "System media controls are unavailable on this macOS version."
        case .failed:
            commandError = "macOS did not accept the media command. Try the control in the player."
        }
    }

    /// Opens the application that owns the current Now Playing item when it is installed.
    @discardableResult
    public func openPlayer() -> Bool {
        guard let bundleIdentifier = snapshot?.applicationBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            commandError = "The current player application could not be opened."
            return false
        }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    private func refreshAndInterval(generation: Int) async -> Duration? {
        await refresh(generation: generation)
        guard generation == self.generation else { return nil }
        return isDropdownVisible ? .seconds(1) : .seconds(3)
    }

    private func refresh(generation: Int) async {
        guard let source, generation == self.generation, !isRefreshing else { return }
        isRefreshing = true
        let result = await source.read()
        isRefreshing = false
        guard generation == self.generation, !Task.isCancelled else { return }
        switch result {
        case let .current(snapshot):
            state = .active(snapshot)
        case .idle:
            state = .idle
        case .unavailable:
            state = .unavailable
        }
    }
}
