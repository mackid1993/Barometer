import AppKit
import MenuBarStatsCore
import SwiftUI

/// Live rates, interfaces, addresses, and Wi-Fi details for the Network status item.
public struct NetworkDropdownView: View {
    private let store: ModuleStore<NetworkSample>
    private let settingsStore: SettingsStore

    /// Creates a Network dropdown backed by the supplied observable store.
    public init(store: ModuleStore<NetworkSample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let sample = store.latestSample
        let settings = settingsStore.settings.network
        let moduleSettings = settingsStore.settings.modules[.network] ?? ModuleSettings(mode: "twoLine")
        let interface = sample?.interface(named: settings.selectedInterfaceName)
        let _ = store.revision

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(interface: interface, unit: settings.rateUnit)

                Text("ACTIVITY").networkSectionLabel()
                NetworkHistoryGraph(
                    samples: store.history.entries,
                    selectedInterfaceName: settings.selectedInterfaceName,
                    settings: settings,
                    downloadColor: AppearanceColorResolver.graph(settingsStore.settings, module: .network),
                    uploadColor: AppearanceColorResolver.fill(settingsStore.settings, module: .network)
                )
                .frame(height: 86)

                if moduleSettings.showsProcesses, let sample {
                    processActivity(
                        sample: sample,
                        limit: moduleSettings.processCount,
                        unit: settings.rateUnit,
                        decimalPlaces: settings.decimalPlaces
                    )
                }

                if let sample {
                    interfacePicker(sample: sample)
                }

                if let interface {
                    Divider()
                    totals(interface: interface)
                    addresses(interface: interface)
                }

                if let sample {
                    connection(sample: sample)
                    wiFi(sample: sample)
                    publicAddresses(sample: sample, settings: settings)
                }
            }
            .padding(14)
        }
        .frame(width: 380, height: 540)
    }

    private func header(interface: NetworkInterfaceSample?, unit: NetworkRateUnit) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Network").font(.headline)
                Spacer()
                Text(interface?.name ?? "Unavailable")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                rateSummary(
                    symbol: "arrow.down",
                    label: "Download",
                    value: interface?.downloadBytesPerSecond,
                    unit: unit,
                    color: AppearanceColorResolver.graph(settingsStore.settings, module: .network)
                )
                rateSummary(
                    symbol: "arrow.up",
                    label: "Upload",
                    value: interface?.uploadBytesPerSecond,
                    unit: unit,
                    color: AppearanceColorResolver.fill(settingsStore.settings, module: .network)
                )
            }
        }
    }

    private func rateSummary(
        symbol: String,
        label: String,
        value: Double?,
        unit: NetworkRateUnit,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(
                value.map {
                    NetworkRateFormatter.string(
                        bytesPerSecond: $0,
                        unit: unit,
                        decimalPlaces: settingsStore.settings.network.decimalPlaces
                    )
                } ?? "Unavailable"
            )
                .font(.system(.title3, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interfacePicker(sample: NetworkSample) -> some View {
        Picker("Interface", selection: selectedInterfaceBinding) {
            Text("Automatic (\(sample.primary?.name ?? "unavailable"))").tag(String?.none)
            ForEach(selectableInterfaces(sample), id: \.name) { interface in
                HStack {
                    Text(interface.name)
                    if interface.isVPN {
                        Text("VPN")
                    }
                }
                .tag(Optional(interface.name))
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
    }

    @ViewBuilder
    private func processActivity(
        sample: NetworkSample,
        limit: Int,
        unit: NetworkRateUnit,
        decimalPlaces: Int
    ) -> some View {
        Text("TOP NETWORK ACTIVITY").networkSectionLabel()
        if !sample.isProcessActivityAvailable {
            Text("Per-process activity unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if sample.topProcesses.isEmpty {
            Text("No recent external network activity")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(sample.topProcesses.prefix(limit), id: \.processIdentifier) { process in
                HStack(spacing: 7) {
                    ProcessIcon(processIdentifier: process.processIdentifier, path: process.path)
                    Text(process.name).lineLimit(1)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        processRate(
                            symbol: "↓",
                            value: process.downloadBytesPerSecond,
                            unit: unit,
                            decimalPlaces: decimalPlaces,
                            color: AppearanceColorResolver.graph(settingsStore.settings, module: .network)
                        )
                        processRate(
                            symbol: "↑",
                            value: process.uploadBytesPerSecond,
                            unit: unit,
                            decimalPlaces: decimalPlaces,
                            color: AppearanceColorResolver.fill(settingsStore.settings, module: .network)
                        )
                    }
                }
                .font(.caption)
            }
        }
    }

    private func processRate(
        symbol: String,
        value: Double,
        unit: NetworkRateUnit,
        decimalPlaces: Int,
        color: Color
    ) -> some View {
        Text(
            symbol + NetworkRateFormatter.string(
                bytesPerSecond: value,
                unit: unit,
                decimalPlaces: decimalPlaces
            )
        )
        .font(.caption2.monospacedDigit())
        .foregroundStyle(color)
    }

    private func totals(interface: NetworkInterfaceSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTALS SINCE BOOT").networkSectionLabel()
            NetworkMetricRow(label: "Received", value: Self.bytes(interface.receivedBytes))
            NetworkMetricRow(label: "Sent", value: Self.bytes(interface.sentBytes))
            if interface.inputErrors > 0 || interface.outputErrors > 0 {
                NetworkMetricRow(
                    label: "Errors",
                    value: "\(interface.inputErrors) in · \(interface.outputErrors) out"
                )
            }
        }
    }

    @ViewBuilder
    private func addresses(interface: NetworkInterfaceSample) -> some View {
        if !interface.ipv4Addresses.isEmpty || !interface.ipv6Addresses.isEmpty {
            Text("LOCAL ADDRESSES").networkSectionLabel()
            ForEach(interface.ipv4Addresses, id: \.self) { address in
                CopyableNetworkValue(label: "IPv4", value: address)
            }
            ForEach(interface.ipv6Addresses, id: \.self) { address in
                CopyableNetworkValue(label: "IPv6", value: address)
            }
        }
    }

    @ViewBuilder
    private func connection(sample: NetworkSample) -> some View {
        if sample.router != nil || !sample.dnsServers.isEmpty {
            Text("CONNECTION").networkSectionLabel()
            if let router = sample.router {
                CopyableNetworkValue(label: "Router", value: router)
            }
            ForEach(sample.dnsServers, id: \.self) { address in
                CopyableNetworkValue(label: "DNS", value: address)
            }
        }
    }

    @ViewBuilder
    private func wiFi(sample: NetworkSample) -> some View {
        if let wifi = sample.wifi {
            Text("WI-FI").networkSectionLabel()
            NetworkMetricRow(
                label: "Network",
                value: wifi.ssid ?? "Name requires Location access"
            )
            if let rssi = wifi.rssi {
                NetworkMetricRow(label: "Signal", value: "\(rssi) dBm")
            }
            if let noise = wifi.noise {
                NetworkMetricRow(label: "Noise", value: "\(noise) dBm")
            }
            if let channel = wifi.channel {
                NetworkMetricRow(
                    label: "Channel",
                    value: "\(channel) · \(wifi.band ?? "Unknown band")"
                )
            }
            if let transmitRate = wifi.transmitRateMbps {
                NetworkMetricRow(label: "Transmit Rate", value: String(format: "%.0f Mbps", transmitRate))
            }
            if let security = wifi.security {
                NetworkMetricRow(label: "Security", value: security)
            }
        }
    }

    @ViewBuilder
    private func publicAddresses(sample: NetworkSample, settings: NetworkSettings) -> some View {
        if settings.showsPublicIP {
            Text("PUBLIC ADDRESSES").networkSectionLabel()
            if let ipv4 = sample.publicIP?.ipv4 {
                CopyableNetworkValue(label: "IPv4", value: ipv4)
            }
            if let ipv6 = sample.publicIP?.ipv6 {
                CopyableNetworkValue(label: "IPv6", value: ipv6)
            }
            if sample.publicIP?.ipv4 == nil, sample.publicIP?.ipv6 == nil {
                Text("Lookup unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedInterfaceBinding: Binding<String?> {
        Binding(
            get: { settingsStore.settings.network.selectedInterfaceName },
            set: { name in
                var settings = settingsStore.settings
                settings.network.selectedInterfaceName = name
                settingsStore.settings = settings
            }
        )
    }

    private func selectableInterfaces(_ sample: NetworkSample) -> [NetworkInterfaceSample] {
        sample.interfaces
            .filter { $0.isUp && !$0.isLoopback }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}

private struct NetworkHistoryGraph: View {
    let samples: [HistoryEntry<NetworkSample>]
    let selectedInterfaceName: String?
    let settings: NetworkSettings
    let downloadColor: Color
    let uploadColor: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.suffix(300).compactMap { entry -> (Double, Double)? in
                guard let interface = entry.value.interface(named: selectedInterfaceName) else {
                    return nil
                }
                return (interface.downloadBytesPerSecond, interface.uploadBytesPerSecond)
            }
            guard values.count > 1 else {
                return
            }
            let observedMaximum = values.reduce(1.0) { maximum, value in
                max(maximum, value.0, value.1)
            }
            let ceiling = settings.graphScale == .fixed
                ? max(1, settings.fixedGraphMaximumBytesPerSecond)
                : observedMaximum * 1.1
            draw(values.map(\.0), ceiling: ceiling, color: downloadColor, context: &context, size: size)
            draw(values.map(\.1), ceiling: ceiling, color: uploadColor, context: &context, size: size)
        }
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private func draw(
        _ values: [Double],
        ceiling: Double,
        color: Color,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) / CGFloat(max(1, values.count - 1)) * size.width
            let normalized = min(1, max(0, value / ceiling))
            let point = CGPoint(x: x, y: (1 - normalized) * size.height)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}

private struct CopyableNetworkValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Text(label).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
            Text(value).font(.caption.monospaced()).lineLimit(1)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy \(label)")
        }
        .font(.caption)
    }
}

private struct NetworkMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

private extension View {
    func networkSectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
