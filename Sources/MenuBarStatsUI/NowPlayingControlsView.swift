import AppKit
import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Compact popup controls for Barometer's independent Now Playing menu bar pill.
public struct NowPlayingControlsView: View {
    /// Preferred hosted popup size.
    public static let contentSize = CGSize(width: 320, height: 108)

    private let controller: NowPlayingController
    private let settingsStore: SettingsStore?

    /// Creates controls bound to a visible-only Now Playing controller.
    public init(controller: NowPlayingController, settingsStore: SettingsStore) {
        self.controller = controller
        self.settingsStore = settingsStore
    }

    /// Creates controls with the standard Now Playing accent for previews and deterministic tests.
    public init(controller: NowPlayingController) {
        self.controller = controller
        settingsStore = nil
    }

    public var body: some View {
        let accent = settingsStore.map { ModuleAccent.resolve($0.settings, module: .nowPlaying) }
            ?? ModuleAccent.signature(for: .nowPlaying)
        DropdownScaffold(size: Self.contentSize) {
            switch controller.state {
            case .loading:
                status("Reading Now Playing…", symbol: "waveform", accent: accent)
            case .unavailable:
                status("macOS supplied no playback information.", symbol: "exclamationmark.triangle", accent: accent)
            case .idle:
                status("Nothing is playing.", symbol: "play.slash", accent: accent)
            case let .active(snapshot):
                activeContent(snapshot, accent: accent)
            }
            if let error = controller.commandError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .topLeading)
        .onAppear { controller.setDropdownVisible(true) }
        .onDisappear { controller.setDropdownVisible(false) }
    }

    @ViewBuilder
    private func activeContent(_ snapshot: NowPlayingSnapshot, accent: ModuleAccent) -> some View {
        GlassCard(tint: accent.primary, padding: 8) {
            HStack(spacing: 10) {
                artwork(snapshot.artworkData)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .help(snapshot.title)
                    if let subtitle = snapshot.artist ?? snapshot.album {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 16) {
                        commandButton(.previous, symbol: "backward.fill", label: "Previous")
                        commandButton(
                            .togglePlayPause,
                            symbol: snapshot.playbackState == .playing ? "pause.fill" : "play.fill",
                            label: snapshot.playbackState == .playing ? "Pause" : "Play"
                        )
                        commandButton(.next, symbol: "forward.fill", label: "Next")
                        Spacer(minLength: 0)
                        if snapshot.applicationBundleIdentifier != nil {
                            Button { controller.openPlayer() } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.plain)
                            .help("Open Player")
                            .accessibilityLabel("Open Player")
                        }
                    }
                    if let elapsed = snapshot.elapsedTime, let duration = snapshot.duration, duration > 0 {
                        ProgressView(value: max(0, min(elapsed, duration)), total: duration)
                            .progressViewStyle(.linear)
                            .tint(accent.primary)
                            .accessibilityLabel("Playback progress")
                            .accessibilityValue("\(Int(elapsed)) of \(Int(duration)) seconds")
                    }
                }
            }
        }
    }

    private func status(_ text: String, symbol: String, accent: ModuleAccent) -> some View {
        GlassCard(tint: accent.primary) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(accent.primary)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commandButton(_ command: NowPlayingCommand, symbol: String, label: String) -> some View {
        Button {
            Task { await controller.perform(command) }
        } label: {
            if controller.pendingCommand == command {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: symbol)
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.pendingCommand != nil)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func artwork(_ data: Data?) -> some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}
