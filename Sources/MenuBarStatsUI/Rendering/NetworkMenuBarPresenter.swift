import AppKit
import MenuBarStatsCore

/// Converts Network samples and preferences into stable image-only status-item content.
@MainActor
enum NetworkMenuBarPresenter {
    static func content(
        sample: NetworkSample?,
        history: [HistoryEntry<NetworkSample>],
        moduleSettings: ModuleSettings,
        networkSettings: NetworkSettings,
        context: RenderContext
    ) -> StatusItemContent {
        guard let sample,
              let interface = sample.interface(named: networkSettings.selectedInterfaceName)
        else {
            return StatusItemContent(
                image: StackedLabelRenderer(label: "NET", value: "—").render(in: context),
                accessibilityValue: "Network unavailable"
            )
        }

        let download = NetworkRateFormatter.compactString(
            bytesPerSecond: interface.downloadBytesPerSecond,
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let upload = NetworkRateFormatter.compactString(
            bytesPerSecond: interface.uploadBytesPerSecond,
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let placeholder = NetworkRateFormatter.compactPlaceholder(
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let renderer: any MenuBarRenderer
        switch moduleSettings.mode {
        case "graph":
            renderer = GraphRenderer(
                values: graphValues(
                    history: history,
                    selectedInterfaceName: networkSettings.selectedInterfaceName,
                    settings: networkSettings
                ),
                style: moduleSettings.graphStyle
            )
        case "arrows":
            renderer = TextRenderer(
                text: "↓\(download) ↑\(upload)",
                reservedText: moduleSettings.usesFixedWidth ? "↓\(placeholder) ↑\(placeholder)" : nil
            )
        case "stacked":
            renderer = StackedLabelRenderer(label: "NET", value: download)
        default:
            renderer = NetworkRateStackRenderer(
                download: download,
                upload: upload,
                reservedValue: placeholder
            )
        }

        let fullDownload = NetworkRateFormatter.string(
            bytesPerSecond: interface.downloadBytesPerSecond,
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let fullUpload = NetworkRateFormatter.string(
            bytesPerSecond: interface.uploadBytesPerSecond,
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: "Network \(interface.name), download \(fullDownload), upload \(fullUpload)"
        )
    }

    private static func graphValues(
        history: [HistoryEntry<NetworkSample>],
        selectedInterfaceName: String?,
        settings: NetworkSettings
    ) -> [Double] {
        let rates = history.compactMap { entry -> Double? in
            guard let interface = entry.value.interface(named: selectedInterfaceName) else {
                return nil
            }
            return max(interface.downloadBytesPerSecond, interface.uploadBytesPerSecond)
        }
        let ceiling: Double
        switch settings.graphScale {
        case .automatic:
            ceiling = max(1, (rates.max() ?? 1) * 1.1)
        case .fixed:
            ceiling = max(1, settings.fixedGraphMaximumBytesPerSecond)
        }
        return rates.map { min(1, max(0, $0 / ceiling)) }
    }
}
