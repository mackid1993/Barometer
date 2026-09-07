import AppKit
import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Playback controls for Barometer's Now Playing menu bar pill, built from the same pieces as every
/// other dropdown: a hero row with the artwork in the icon tile's place, and one glass card holding the
/// gradient progress capsule and the transport buttons.
public struct NowPlayingControlsView: View {
    /// Fixed canvas of the hosted panel.
    public static let contentSize = CGSize(width: 340, height: 196)

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
        GlassEffectContainer(spacing: BarometerDesign.sectionSpacing) {
            VStack(alignment: .leading, spacing: BarometerDesign.sectionSpacing) {
                switch controller.state {
                case .loading:
                    statusCard("Reading Now Playing…", symbol: "waveform", accent: accent)
                case .unavailable:
                    statusCard("macOS supplied no playback information.", symbol: "exclamationmark.triangle",
                               accent: accent)
                case .idle:
                    statusCard("Nothing is playing.", symbol: "play.slash", accent: accent)
                case let .active(snapshot):
                    heroRow(snapshot, accent: accent)
                    transportCard(snapshot, accent: accent)
                }
            }
        }
        .padding(BarometerDesign.panelPadding)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .topLeading)
        .onAppear { controller.setDropdownVisible(true) }
        .onDisappear { controller.setDropdownVisible(false) }
    }

    // MARK: - Active

    private func heroRow(_ snapshot: NowPlayingSnapshot, accent: ModuleAccent) -> some View {
        HStack(alignment: .center, spacing: 12) {
            artworkTile(snapshot.artworkData, accent: accent)
            VStack(alignment: .leading, spacing: 2) {
                OverflowMarquee(text: snapshot.title, font: BarometerDesign.titleFont, nsFont: Self.titleNSFont)
                    .id(snapshot.title)
                    .help(snapshot.title)
                if let subtitle = Self.subtitle(for: snapshot) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let bundleIdentifier = snapshot.applicationBundleIdentifier {
                Button { controller.openPlayer() } label: {
                    Chip(
                        text: NotificationApplicationResolver.name(bundleIdentifier: bundleIdentifier),
                        color: accent.secondary,
                        symbol: "arrow.up.forward.app"
                    )
                }
                .buttonStyle(.plain)
                .help("Open the player")
                .accessibilityLabel("Open Player")
            }
        }
        .padding(.horizontal, 2)
    }

    private func transportCard(_ snapshot: NowPlayingSnapshot, accent: ModuleAccent) -> some View {
        GlassCard(tint: accent.primary) {
            VStack(spacing: 12) {
                if let elapsed = snapshot.elapsedTime, let duration = snapshot.duration, duration > 0 {
                    let clamped = max(0, min(elapsed, duration))
                    HStack(spacing: 8) {
                        Text(Self.clock(clamped))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        CapsuleBar(fraction: clamped / duration, gradient: accent.horizontalGradient,
                                   glowColor: accent.primary)
                        Text("-" + Self.clock(duration - clamped))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Playback progress")
                    .accessibilityValue("\(Int(clamped)) of \(Int(duration)) seconds")
                }
                HStack(spacing: 18) {
                    Spacer(minLength: 0)
                    transportButton(.previous, symbol: "backward.fill", label: "Previous", accent: accent)
                    transportButton(
                        .togglePlayPause,
                        symbol: snapshot.playbackState == .playing ? "pause.fill" : "play.fill",
                        label: snapshot.playbackState == .playing ? "Pause" : "Play",
                        accent: accent,
                        prominent: true
                    )
                    transportButton(.next, symbol: "forward.fill", label: "Next", accent: accent)
                    Spacer(minLength: 0)
                }
                if let error = controller.commandError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(error)
                }
            }
        }
    }

    /// A round transport control; the play button carries the module gradient like an icon tile.
    private func transportButton(
        _ command: NowPlayingCommand, symbol: String, label: String, accent: ModuleAccent, prominent: Bool = false
    ) -> some View {
        let size: CGFloat = prominent ? 44 : 34
        return Button {
            Task { await controller.perform(command) }
        } label: {
            ZStack {
                if prominent {
                    Circle().fill(accent.gradient)
                    Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.75)
                } else {
                    Circle().fill(Color.primary.opacity(0.08))
                }
                if controller.pendingCommand == command {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: prominent ? 18 : 13, weight: .semibold))
                        .foregroundStyle(prominent ? Color.white : Color.primary)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: prominent ? accent.primary.opacity(0.35) : .clear, radius: 8, y: 3)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(controller.pendingCommand != nil)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func artworkTile(_ data: Data?, accent: ModuleAccent) -> some View {
        let size: CGFloat = 52
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.75))
                .shadow(color: accent.primary.opacity(0.35), radius: 8, y: 3)
                .accessibilityHidden(true)
        } else {
            IconTile(symbolName: "music.note", accent: accent, size: size)
        }
    }

    // MARK: - Status

    private func statusCard(_ text: String, symbol: String, accent: ModuleAccent) -> some View {
        GlassCard(tint: accent.primary) {
            HStack(spacing: 12) {
                IconTile(symbolName: symbol, accent: accent)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Formatting

    private static let titleNSFont = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize,
                                                       weight: .semibold)

    static func subtitle(for snapshot: NowPlayingSnapshot) -> String? {
        let parts = [snapshot.artist, snapshot.album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// One-line title that scrolls to reveal an overflowing string, then rests at each end.
private struct OverflowMarquee: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var availableWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    let text: String
    let font: Font
    let nsFont: NSFont

    private var textWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: nsFont]).width)
    }

    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset)
                .onAppear {
                    availableWidth = geometry.size.width
                    restartAnimation()
                }
                .onChange(of: geometry.size.width) { _, width in
                    guard abs(width - availableWidth) > 0.5 else { return }
                    availableWidth = width
                    restartAnimation()
                }
        }
        .frame(height: ceil(nsFont.ascender - nsFont.descender) + 2)
        .clipped()
        .onChange(of: reduceMotion) { _, _ in restartAnimation() }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            offset = 0
        }
        .accessibilityLabel(text)
    }

    private func restartAnimation() {
        animationTask?.cancel()
        animationTask = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0 }
        let overflow = textWidth - availableWidth
        guard overflow > 1, availableWidth > 0, !reduceMotion else { return }
        let distance = overflow + 6
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let travelDuration = max(2.5, Double(distance / 28))
            while !Task.isCancelled {
                withAnimation(.linear(duration: travelDuration)) { offset = -distance }
                try? await Task.sleep(for: .seconds(travelDuration))
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: travelDuration)) { offset = 0 }
                try? await Task.sleep(for: .seconds(travelDuration))
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(1_500))
            }
        }
    }
}
