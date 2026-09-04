import Foundation
@testable import MenuBarStatsCore
import Testing

@Suite("DiskTests")
struct DiskTests {
    @Test("disk rates use elapsed time and reject counter resets")
    func calculatesRates() {
        #expect(DiskMonitor.rate(from: 100, to: 300, elapsed: 2) == 100)
        #expect(DiskMonitor.rate(from: nil, to: 300, elapsed: 2) == 0)
        #expect(DiskMonitor.rate(from: 300, to: 10, elapsed: 2) == 0)
        #expect(DiskMonitor.rate(from: 100, to: 300, elapsed: 0) == 0)
    }

    @Test("disk values support binary and decimal units")
    func formatsValues() {
        #expect(DiskValueFormatter.capacity(1_073_741_824, unitSystem: .binary) == "1.0 GiB")
        #expect(DiskValueFormatter.capacity(1_000_000_000, unitSystem: .decimal) == "1.0 GB")
        #expect(DiskValueFormatter.rate(1_048_576, unitSystem: .binary) == "1.0 MiB/s")
        #expect(DiskValueFormatter.rate(-1, unitSystem: .decimal) == "0 B/s")
    }

    @Test("system volumes hide without losing the startup volume")
    func filtersVolumes() {
        let startup = volume(id: "startup", name: "Macintosh HD", mountPoint: "/")
        let preboot = volume(id: "preboot", name: "Preboot", mountPoint: "/System/Volumes/Preboot")
        let external = volume(id: "external", name: "Backup", mountPoint: "/Volumes/Backup")
        let sample = DiskSample(
            timestamp: Date(timeIntervalSince1970: 0),
            volumes: [preboot, external, startup],
            devices: []
        )

        #expect(sample.visibleVolumes(settings: DiskSettings()).map(\.id) == ["external", "startup"])
        #expect(sample.selectedVolume(settings: DiskSettings()) == startup)
        #expect(
            sample.visibleVolumes(settings: DiskSettings(hiddenVolumeIDs: ["external"])).map(\.id) == ["startup"]
        )
        #expect(
            sample.selectedVolume(settings: DiskSettings(selectedVolumeID: "external")) == external
        )
    }

    @Test("older Disk settings gain an empty hidden-volume set")
    func migratesHiddenVolumes() throws {
        let data = Data(#"{"hidesSystemVolumes":false,"unitSystem":"decimal"}"#.utf8)
        let settings = try JSONDecoder().decode(DiskSettings.self, from: data)

        #expect(settings.selectedVolumeID == nil)
        #expect(!settings.hidesSystemVolumes)
        #expect(settings.unitSystem == .decimal)
        #expect(settings.hiddenVolumeIDs.isEmpty)
    }

    private func volume(id: String, name: String, mountPoint: String) -> DiskVolumeSample {
        DiskVolumeSample(
            id: id,
            name: name,
            mountPoint: mountPoint,
            bsdName: nil,
            physicalBSDName: nil,
            totalBytes: 100,
            usedBytes: 60,
            availableBytes: 40,
            kind: .internalDisk,
            isEjectable: false,
            isRemovable: false,
            isReadOnly: false
        )
    }
}
