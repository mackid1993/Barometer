import Foundation
import Testing

@testable import MenuBarStatsUI
@testable import SystemSources

@Suite("NowPlayingControllerTests")
@MainActor
struct NowPlayingControllerTests {
    @Test("refresh distinguishes an active item from no current player")
    func refreshState() async {
        let snapshot = Self.snapshot(state: .playing)
        let reads = ReadSequence([.current(snapshot), .idle])
        let source = NowPlayingSource(
            read: { await reads.next() },
            command: { _ in .accepted }
        )
        let controller = NowPlayingController(source: source)

        await controller.refresh()
        #expect(controller.state == .active(snapshot))
        #expect(controller.snapshot == snapshot)

        await controller.refresh()
        #expect(controller.state == .idle)
        #expect(controller.snapshot == nil)
    }

    @Test("failed commands preserve current metadata and expose an actionable error")
    func commandFailure() async {
        let snapshot = Self.snapshot(state: .paused)
        let recorder = FailedCommandRecorder()
        let source = NowPlayingSource(
            read: { .current(snapshot) },
            command: { await recorder.send($0) }
        )
        let controller = NowPlayingController(source: source)
        await controller.refresh()

        await controller.perform(.next)

        #expect(await recorder.commands == [.next])
        #expect(controller.snapshot == snapshot)
        #expect(controller.pendingCommand == nil)
        #expect(controller.commandError?.contains("player") == true)
    }

    @Test("stop clears transient controller state")
    func stopClearsState() async {
        let snapshot = Self.snapshot(state: .playing)
        let source = NowPlayingSource(read: { .current(snapshot) }, command: { _ in .accepted })
        let controller = NowPlayingController(source: source)
        await controller.refresh()

        controller.stop()

        #expect(controller.state == .idle)
        #expect(controller.snapshot == nil)
        #expect(controller.pendingCommand == nil)
        #expect(controller.commandError == nil)
    }

    @Test("a read completed after stop cannot resurrect playback state")
    func stopInvalidatesPendingRead() async {
        let blockedRead = BlockingRead()
        let source = NowPlayingSource(read: { await blockedRead.read() }, command: { _ in .accepted })
        let controller = NowPlayingController(source: source)

        let refresh = Task { await controller.refresh() }
        while !(await blockedRead.hasStarted) {
            await Task.yield()
        }
        controller.stop()
        await blockedRead.finish(with: .current(Self.snapshot(state: .playing)))
        await refresh.value

        #expect(controller.state == .idle)
        #expect(controller.snapshot == nil)
    }

    private static func snapshot(state: NowPlayingPlaybackState) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: "Song",
            artist: "Artist",
            album: "Album",
            applicationBundleIdentifier: "com.example.player",
            playbackState: state,
            duration: 200,
            elapsedTime: 40,
            artworkData: nil
        )
    }
}

private actor ReadSequence {
    private var results: [NowPlayingReadResult]

    init(_ results: [NowPlayingReadResult]) {
        self.results = results
    }

    func next() -> NowPlayingReadResult {
        results.removeFirst()
    }
}

private actor BlockingRead {
    private(set) var hasStarted = false
    private var continuation: CheckedContinuation<NowPlayingReadResult, Never>?

    func read() async -> NowPlayingReadResult {
        hasStarted = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with result: NowPlayingReadResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor FailedCommandRecorder {
    private(set) var commands: [NowPlayingCommand] = []

    func send(_ command: NowPlayingCommand) -> NowPlayingCommandResult {
        commands.append(command)
        return .failed
    }
}
