import AppKit
import MenuBarStatsCore
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

        #expect(abs(size.height - 14.5475) < 0.001)
        #expect(size.width == 22)
        #expect(metrics.iconTextGap == 4)
        #expect(metrics.centeredY(for: size.height) == 5)
        let symbolY = metrics.symbolY(
            for: size,
            nativeSize: NSSize(width: 18, height: 12),
            alignmentRect: NSRect(x: 0, y: 1, width: 18, height: 9)
        )
        #expect(abs(symbolY - 5.527) < 0.001)
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

    @Test
    func horizontalSpacingChangesImageWidthByExactlyTwoInsets() {
        let compact = TextRenderer(text: "42%").render(in: context)
        let spacedContext = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: context.scale,
            horizontalSpacing: 3
        )
        let spaced = TextRenderer(text: "42%").render(in: spacedContext)

        #expect(spaced.size.width == compact.size.width + 6)
    }

    @Test
    func graphicScaleDoesNotChangeTextSize() {
        let smallGraphics = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: 0.75
        )
        let largeGraphics = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: 1.35
        )

        let smallText = TextRenderer(text: "42%").render(in: smallGraphics)
        let largeText = TextRenderer(text: "42%").render(in: largeGraphics)
        let smallGraph = GraphRenderer(values: [0.2, 0.8], style: .line).render(in: smallGraphics)
        let largeGraph = GraphRenderer(values: [0.2, 0.8], style: .line).render(in: largeGraphics)

        #expect(smallText.size == largeText.size)
        #expect(smallGraph.size.width < largeGraph.size.width)
    }

    @Test
    func statusItemLengthMatchesRenderedCanvasWithoutAppKitInsets() {
        let image = TextRenderer(text: "CPU").render(in: context)

        #expect(StatusItemRendering.itemLength(for: image) == ceil(image.size.width))
    }

    @Test
    func networkPresentationSupportsEveryMenuBarMode() {
        let interface = NetworkInterfaceSample(
            name: "en0",
            isUp: true,
            isLoopback: false,
            isVPN: false,
            ipv4Addresses: ["192.0.2.10"],
            ipv6Addresses: [],
            downloadBytesPerSecond: 1_250_000,
            uploadBytesPerSecond: 82_000,
            receivedBytes: 10_000_000,
            sentBytes: 2_000_000,
            inputErrors: 0,
            outputErrors: 0
        )
        let sample = NetworkSample(
            timestamp: Date(timeIntervalSince1970: 10),
            interfaces: [interface],
            primaryInterface: "en0",
            router: "192.0.2.1",
            dnsServers: ["192.0.2.53"],
            wifi: nil,
            publicIP: nil
        )
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample)]

        for mode in ["twoLine", "arrows", "stacked", "graph"] {
            let content = NetworkMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: ModuleSettings(isEnabled: true, mode: mode),
                networkSettings: NetworkSettings(),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Network en0"))
        }
    }

    @Test
    func peerRowsKeepTheSameGeometryWhenSwapped() {
        let first = NetworkRateStackRenderer(
            download: "1.2MB",
            upload: "82.0KB",
            reservedValue: "999.9GB"
        ).render(in: context)
        let swapped = NetworkRateStackRenderer(
            download: "82.0KB",
            upload: "1.2MB",
            reservedValue: "999.9GB"
        ).render(in: context)

        #expect(first.size == swapped.size)
        #expect(first.size.height == context.thickness)
    }

    @Test
    func diskPresentationSupportsEveryMenuBarMode() {
        let volume = DiskVolumeSample(
            id: "startup",
            name: "Macintosh HD",
            mountPoint: "/",
            bsdName: "disk3s3s1",
            physicalBSDName: "disk0",
            totalBytes: 1_000,
            usedBytes: 650,
            availableBytes: 350,
            kind: .internalDisk,
            isEjectable: false,
            isRemovable: false,
            isReadOnly: true
        )
        let device = DiskDeviceSample(
            bsdName: "disk0",
            model: "Test SSD",
            readBytesPerSecond: 1_250_000,
            writeBytesPerSecond: 82_000,
            readOperationsPerSecond: 20,
            writeOperationsPerSecond: 5,
            bytesRead: 10_000_000,
            bytesWritten: 2_000_000,
            readOperations: 100,
            writeOperations: 50,
            readErrors: 0,
            writeErrors: 0
        )
        let sample = DiskSample(
            timestamp: Date(timeIntervalSince1970: 10),
            volumes: [volume],
            devices: [device]
        )
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample)]

        for mode in ["activityGraph", "freePercentage", "freeBytes", "rates"] {
            let content = DiskMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: ModuleSettings(isEnabled: true, mode: mode),
                diskSettings: DiskSettings(),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Disks read"))
        }
    }
}
