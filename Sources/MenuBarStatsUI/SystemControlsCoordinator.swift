import AppKit
import MenuBarStatsCore
import Observation
import SwiftUI
import SystemSources

/// Connects native system controls to the registry's permanent Focus and Now Playing items.
@MainActor
final class SystemControlsCoordinator {
    private let focus = FocusController()
    private let nowPlaying = NowPlayingController()
    private let focusStore = ModuleStore<SystemControlSample>(historyCapacity: 1)
    private let nowPlayingStore = ModuleStore<SystemControlSample>(historyCapacity: 1)
    private let settingsStore: SettingsStore
    private var focusItem: StatusItemController<SystemControlSample>?
    private var nowPlayingItem: StatusItemController<SystemControlSample>?
    private var nowPlayingDropdown: DropdownController?
    private var isSleeping = false
    private var isStopped = false

    init(registry: StatusItemRegistry, settingsStore: SettingsStore,
         settingsAction: @escaping @MainActor (ModuleID) -> Void,
         quitAction: @escaping @MainActor () -> Void) {
        self.settingsStore = settingsStore
        updateSamples()
        focusItem = StatusItemController(
            module: .focus, statusItem: registry.item(for: .focus), store: focusStore,
            settingsStore: settingsStore,
            isPresented: { sample, _, _ in Self.shouldPresentFocus(sample) },
            render: { sample, _, _, context in
                SystemControlPillRenderer.renderFocus(sample ?? Self.focusUnavailable, in: context)
            }
        )
        nowPlayingItem = StatusItemController(
            module: .nowPlaying, statusItem: registry.item(for: .nowPlaying), store: nowPlayingStore,
            settingsStore: settingsStore,
            isPresented: { sample, settings, _ in
                Self.shouldPresentNowPlaying(sample, visibility: settings.time.nowPlayingVisibility)
            },
            render: { sample, _, _, context in
                SystemControlPillRenderer.render(sample ?? Self.mediaUnavailable, in: context, symbolPointSize: 18)
            }
        )
        nowPlayingDropdown = DropdownController(
            moduleName: ModuleID.nowPlaying.displayName, statusItem: registry.item(for: .nowPlaying),
            rootView: AnyView(NowPlayingControlsView(controller: nowPlaying, settingsStore: settingsStore)),
            contentHeight: NowPlayingControlsView.contentSize.height,
            contentWidth: NowPlayingControlsView.contentSize.width,
            usesAttachedPanel: true,
            compactFooter: true,
            tickAction: {},
            settingsAction: { settingsAction(.time) }, quitAction: quitAction
        )
        observeStates()
        applyActivity()
    }

    // MARK: - Item lifecycle

    func activateVisibility(for module: ModuleID) {
        if module == .focus { focusItem?.activateVisibility() }
        if module == .nowPlaying { nowPlayingItem?.activateVisibility() }
    }

    func attach(_ statusItem: NSStatusItem, for module: ModuleID, activate: Bool) {
        if module == .focus {
            focusItem?.attach(statusItem: statusItem)
        } else if module == .nowPlaying {
            nowPlayingDropdown?.attach(statusItem: statusItem)
            nowPlayingItem?.attach(statusItem: statusItem)
        }
        if activate { activateVisibility(for: module) }
    }

    func applyActivity() {
        guard !isStopped else { return }
        if !isSleeping && settingsStore.settings.modules[.focus]?.isEnabled == true {
            focus.start()
        } else {
            focus.stop()
        }
        if !isSleeping && settingsStore.settings.modules[.nowPlaying]?.isEnabled == true {
            nowPlaying.start()
        } else {
            nowPlaying.stop()
        }
    }

    func setSleeping(_ sleeping: Bool) {
        isSleeping = sleeping
        applyActivity()
    }

    func stop() {
        isStopped = true
        focus.stop()
        nowPlaying.stop()
    }

    // MARK: - Presentation

    private static let focusUnavailable = SystemControlSample(
        symbolName: "moon", accessibilityValue: "Focus unavailable", isActive: false)
    private static let mediaUnavailable = SystemControlSample(
        symbolName: "play.fill", accessibilityValue: "Now Playing unavailable", isActive: false)

    static func shouldPresentFocus(_ sample: SystemControlSample?) -> Bool {
        sample?.isActive == true
    }

    static func shouldPresentNowPlaying(
        _ sample: SystemControlSample?,
        visibility: NowPlayingVisibility
    ) -> Bool {
        visibility == .always || sample?.isActive == true
    }

    private func updateSamples() {
        let focusSample: SystemControlSample
        switch focus.snapshot {
        case .unavailable:
            focusSample = Self.focusUnavailable
        case .inactive:
            focusSample = SystemControlSample(symbolName: "moon", accessibilityValue: "Focus off", isActive: false)
        case let .active(mode, _):
            focusSample = SystemControlSample(
                symbolName: "moon.fill",
                accessibilityValue: "Focus: \(mode?.name ?? "On")", isActive: true)
        }
        if focusStore.latestSample != focusSample { focusStore.receive(focusSample) }

        let mediaSample: SystemControlSample
        switch nowPlaying.state {
        case .loading, .unavailable:
            mediaSample = Self.mediaUnavailable
        case .idle:
            mediaSample = SystemControlSample(
                symbolName: "play.fill", accessibilityValue: "Now Playing: Nothing playing", isActive: false)
        case let .active(snapshot):
            let playing = snapshot.playbackState == .playing
            mediaSample = SystemControlSample(
                symbolName: "play.fill",
                accessibilityValue: "Now Playing: \(snapshot.title)\(snapshot.artist.map { " by \($0)" } ?? ""), "
                    + (playing ? "playing" : "paused"),
                isActive: playing)
        }
        if nowPlayingStore.latestSample != mediaSample { nowPlayingStore.receive(mediaSample) }
    }

    private func observeStates() {
        withObservationTracking {
            _ = focus.snapshot
            _ = nowPlaying.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isStopped else { return }
                self.updateSamples()
                self.observeStates()
            }
        }
    }
}
