import AppKit
import MenuBarStatsCore

/// Converts Network samples and preferences into stable image-only status-item content.
@MainActor
enum NetworkMenuBarPresenter {
    static func content(
        sample: NetworkSample?,
        history: [HistoryEntry<NetworkSample.GraphValue>],
        moduleSettings: ModuleSettings,
        networkSettings: NetworkSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let placeholder = NetworkRateFormatter.compactPlaceholder(
            unit: networkSettings.rateUnit,
            decimalPlaces: networkSettings.decimalPlaces
        )
        let interface = sample?.interface(named: networkSettings.selectedInterfaceName)
        let download = interface.map {
            NetworkRateFormatter.compactString(
                bytesPerSecond: $0.downloadBytesPerSecond,
                unit: networkSettings.rateUnit,
                decimalPlaces: networkSettings.decimalPlaces
            )
        } ?? "—"
        let upload = interface.map {
            NetworkRateFormatter.compactString(
                bytesPerSecond: $0.uploadBytesPerSecond,
                unit: networkSettings.rateUnit,
                decimalPlaces: networkSettings.decimalPlaces
            )
        } ?? "—"
        let renderer: any MenuBarRenderer
        let uploadFirst = networkSettings.rateOrder == .uploadThenDownload
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
            let orderedText = uploadFirst
                ? "↑\(upload) ↓\(download)"
                : "↓\(download) ↑\(upload)"
            let orderedPlaceholder = uploadFirst
                ? "↑\(placeholder) ↓\(placeholder)"
                : "↓\(placeholder) ↑\(placeholder)"
            renderer = TextRenderer(
                text: orderedText,
                reservedText: moduleSettings.usesFixedWidth ? orderedPlaceholder : nil
            )
        case "stacked":
            renderer = StackedLabelRenderer(label: "NET", value: download, reservedValue: placeholder)
        default:
            renderer = uploadFirst
                ? NetworkRateStackRenderer(
                    top: "↑\(upload)",
                    bottom: "↓\(download)",
                    reservedTop: "↑\(placeholder)",
                    reservedBottom: "↓\(placeholder)"
                )
                : NetworkRateStackRenderer(download: download, upload: upload, reservedValue: placeholder)
        }

        guard let interface else {
            return StatusItemContent(
                image: renderer.render(in: context),
                accessibilityValue: "Network unavailable"
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
        history: [HistoryEntry<NetworkSample.GraphValue>],
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
