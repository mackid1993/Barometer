import Testing
@testable import SystemSources

@Test func systemSourcesLayerLoads() {
    #expect(SystemSourcesAvailability.isAvailable)
}
