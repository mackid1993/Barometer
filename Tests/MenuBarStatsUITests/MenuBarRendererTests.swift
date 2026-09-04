import AppKit
@testable import MenuBarStatsUI
import Testing

@MainActor
struct MenuBarRendererTests {
    private let context = RenderContext(
        thickness: 24,
        appearance: .dark,
        palette: MenuBarPalette(light: .black, dark: .white),
        fontSize: 12.65,
        isMonochrome: true,
        scale: 1.15
    )

    @Test
    func stackedRowsShareOneLeadingEdge() {
        let metrics = MenuBarLayoutMetrics(context: context)
        let origins = metrics.stackedOrigins(labelHeight: 10, valueHeight: 12)

        #expect(origins.label.x == origins.value.x)
        #expect(origins.label.x == MenuBarLayoutMetrics.contentInset)
        #expect(origins.value.y == 1)
        #expect(origins.label.y == 13)
    }

    @Test
    func iconMatchesFontSizeAndUsesCanonicalGap() {
        let metrics = MenuBarLayoutMetrics(context: context)
        let size = metrics.symbolSize(nativeSize: NSSize(width: 18, height: 12), font: NSFont.systemFont(ofSize: 12.65))

        #expect(size.height == 12.65)
        #expect(size.width == 19)
        #expect(metrics.iconTextGap == 4)
        #expect(metrics.centeredY(for: size.height) == 5)
        #expect(metrics.symbolY(for: size.height, font: NSFont.systemFont(ofSize: 12.65)) == 7)
    }

    @Test
    func stackedRendererReservesTheWidestRowWithoutChangingAlignment() {
        let memory = StackedLabelRenderer(label: "MEM", value: "85%").render(in: context)
        let cpu = StackedLabelRenderer(label: "CPU", value: "24%").render(in: context)

        #expect(memory.size.height == context.thickness)
        #expect(cpu.size.height == context.thickness)
        #expect(memory.size.width > 0)
        #expect(cpu.size.width > 0)
    }
}
