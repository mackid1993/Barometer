import AppKit
import SwiftUI
import SystemSources

/// Compact popup controls for Barometer's independent Now Playing menu bar pill.
public struct NowPlayingControlsView: View {
    /// Preferred hosted popup size.
    public static let contentSize = CGSize(width: 300, height: 210)

    private let controller: NowPlayingController

    /// Creates controls bound to a visible-only Now Playing controller.
    public init(controller: NowPlayingController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch controller.state {
            case .loading:
                status("Reading Now Playing…", symbol: "waveform")
            case .unavailable:
                status("macOS supplied no playback information.", symbol: "exclamationmark.triangle")
            case .idle:
                status("macOS supplied no playback information.", symbol: "play.slash")
            case let .active(snapshot):
                activeContent(snapshot)
            }
            if let error = controller.commandError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .topLeading)
        .onAppear { controller.setDropdownVisible(true) }
        .onDisappear { controller.setDropdownVisible(false) }
    }

    @ViewBuilder
    private func activeContent(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            artwork(snapshot.artworkData)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(1)
                if let artist = snapshot.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let album = snapshot.album {
                    Text(album)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        if let elapsed = snapshot.elapsedTime, let duration = snapshot.duration, duration > 0 {
            ProgressView(value: min(elapsed, duration), total: duration)
                .progressViewStyle(.linear)
                .accessibilityLabel("Playback progress")
                .accessibilityValue("\(Int(elapsed)) of \(Int(duration)) seconds")
        }
        HStack(spacing: 18) {
            commandButton(.previous, symbol: "backward.fill", label: "Previous")
            commandButton(
                .togglePlayPause,
                symbol: snapshot.playbackState == .playing ? "pause.fill" : "play.fill",
                label: snapshot.playbackState == .playing ? "Pause" : "Play"
            )
            commandButton(.next, symbol: "forward.fill", label: "Next")
            Spacer(minLength: 0)
            if snapshot.applicationBundleIdentifier != nil {
                Button("Open Player") { controller.openPlayer() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func status(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}
