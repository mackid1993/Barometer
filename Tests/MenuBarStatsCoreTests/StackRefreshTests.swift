import Testing
@testable import MenuBarStatsCore

@Test("A CPU/GPU stack ignores unrelated source updates and disabled stacks")
func stackRefreshSources() {
    var settings = StacksSettings(stacks: [
        StackSettings(id: 1, metrics: [.cpuTotal, .gpuUtilization]),
        StackSettings(id: 2, isEnabled: false, metrics: [.weatherTemperature])
    ])
    #expect(settings.needsSample(from: .cpu))
    #expect(settings.needsSample(from: .gpu))
    for module in [ModuleID.memory, .network, .disks, .sensors, .battery, .time, .weather] {
        #expect(!settings.needsSample(from: module))
    }
    settings.stacks[1].isEnabled = true
    #expect(settings.needsSample(from: .weather))
}
