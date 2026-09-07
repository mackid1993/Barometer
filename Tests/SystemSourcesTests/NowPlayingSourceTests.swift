import Foundation
import Testing

@testable import SystemSources

@Suite("NowPlayingSourceTests")
struct NowPlayingSourceTests {
    @Test("metadata is normalized and elapsed time stays inside duration")
    func decodesMetadata() throws {
        let snapshot = try #require(NowPlayingSource.decode([
            "kMRMediaRemoteNowPlayingInfoTitle": "  Song  ",
            "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
            "kMRMediaRemoteNowPlayingInfoAlbum": "Album",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1,
            "kMRMediaRemoteNowPlayingInfoDuration": 180,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": 240,
        ], applicationIdentifier: " com.example.player "))

        #expect(snapshot.title == "Song")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.album == "Album")
        #expect(snapshot.applicationBundleIdentifier == "com.example.player")
        #expect(snapshot.playbackState == .playing)
        #expect(snapshot.duration == 180)
        #expect(snapshot.elapsedTime == 180)
        #expect(snapshot.artworkData == nil)
    }

    @Test("missing title falls back safely and oversized artwork is discarded")
    func boundsArtwork() throws {
        let oversized = Data(repeating: 0, count: NowPlayingSource.maximumArtworkBytes + 1)
        let snapshot = try #require(NowPlayingSource.decode([
            "kMRMediaRemoteNowPlayingInfoArtist": "Radio Station",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 0,
            "kMRMediaRemoteNowPlayingInfoDuration": -1,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": Double.nan,
            "kMRMediaRemoteNowPlayingInfoArtworkData": oversized,
        ], applicationIdentifier: nil))

        #expect(snapshot.title == "Radio Station")
        #expect(snapshot.artist == nil)
        #expect(snapshot.playbackState == .paused)
        #expect(snapshot.duration == nil)
        #expect(snapshot.elapsedTime == nil)
        #expect(snapshot.artworkData == nil)
        #expect(NowPlayingSource.decode([:], applicationIdentifier: nil) == nil)
    }

    @Test("missing and empty MediaRemote callbacks report unavailable instead of idle")
    func unavailableCallbackClassification() {
        #expect(NowPlayingSource.readResult(for: nil, applicationIdentifier: nil) == .unavailable)
        #expect(NowPlayingSource.readResult(for: [:], applicationIdentifier: nil) == .unavailable)
        #expect(NowPlayingSource.readResult(
            for: ["kMRMediaRemoteNowPlayingInfoPlaybackRate": 0],
            applicationIdentifier: nil
        ) == .unavailable)
    }

    @Test("a callback containing usable metadata reports the decoded current item")
    func currentCallbackClassification() throws {
        let result = NowPlayingSource.readResult(
            for: [
                "kMRMediaRemoteNowPlayingInfoTitle": "Song",
                "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
                "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1,
            ],
            applicationIdentifier: "com.example.player"
        )
        guard case let .current(snapshot) = result else {
            Issue.record("Expected usable callback metadata to produce a current item")
            return
        }
        #expect(snapshot.title == "Song")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.applicationBundleIdentifier == "com.example.player")
        #expect(snapshot.playbackState == .playing)
    }

    @Test("injected source reads and sends commands without touching live playback")
    func injectedOperations() async throws {
        let expected = NowPlayingSnapshot(
            title: "Song",
            artist: "Artist",
            album: nil,
            applicationBundleIdentifier: "com.example.player",
            playbackState: .paused,
            duration: nil,
            elapsedTime: nil,
            artworkData: nil
        )
        let recorder = CommandRecorder()
        let source = NowPlayingSource(
            read: { .current(expected) },
            command: { await recorder.send($0) }
        )

        #expect(await source.isAvailable)
        #expect(await source.read() == .current(expected))
        #expect(await source.current() == expected)
        #expect(await source.send(.previous) == .accepted)
        #expect(await source.send(.togglePlayPause) == .accepted)
        #expect(await source.send(.next) == .accepted)
        #expect(await recorder.commands == [.previous, .togglePlayPause, .next])
    }
}

private actor CommandRecorder {
    private(set) var commands: [NowPlayingCommand] = []

    func send(_ command: NowPlayingCommand) -> NowPlayingCommandResult {
        commands.append(command)
        return .accepted
    }
}
