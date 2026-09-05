import AppKit
import MenuBarStatsCore
import SwiftUI

/// Live rates, interfaces, addresses, and Wi-Fi details for the Network status item.
public struct NetworkDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 560)

    private let store: ModuleStore<NetworkSample>
    private let settingsStore: SettingsStore
    private let locationAccess: @MainActor () -> LocationAccessState
    private let locationAction: @MainActor () -> Void

    /// Creates a Network dropdown backed by the supplied observable store.
    public init(
        store: ModuleStore<NetworkSample>,
        settingsStore: SettingsStore,
        locationAccess: @escaping @MainActor () -> LocationAccessState,
        locationAction: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.locationAccess = locationAccess
        self.locationAction = locationAction
    }

    public var body: some View {
        let sample = store.latestSample
        let settings = settingsStore.settings.network
        let moduleSettings = settingsStore.settings.modules[.network] ?? ModuleSettings(mode: "twoLine")
        let interface = sample?.interface(named: settings.selectedInterfaceName)
        let _ = store.revision
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .network)
        let downloadAccent = ModuleAccent(primary: accent.primary, secondary: accent.primary.opacity(0.7))
        let uploadAccent = ModuleAccent(primary: accent.secondary, secondary: accent.secondary.opacity(0.7))

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "network",
                title: "Network",
                subtitle: subtitle(sample: sample, interface: interface),
                value: nil,
                accent: accent
            ) {
                VStack(alignment: .trailing, spacing: 1) {
                    HeroRate(
                        arrow: "arrow.down",
                        value: interface.map { rate($0.downloadBytesPerSecond, unit: settings.rateUnit) } ?? "—",
                        color: accent.primary
                    )
                    HeroRate(
                        arrow: "arrow.up",
                        value: interface.map { rate($0.uploadBytesPerSecond, unit: settings.rateUnit) } ?? "—",
                        color: accent.secondary
                    )
                }
            }

            GlassCard(tint: accent.primary) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Activity") {
                        if let sample {
                            interfacePicker(sample: sample)
                        }
                    }
                    HStack(spacing: 8) {
                        RateTile(
                            symbol: "arrow.down.circle.fill",
                            label: "Download",
                            value: interface.map { rate($0.downloadBytesPerSecond, unit: settings.rateUnit) } ?? "—",
                            color: accent.primary
                        )
                        RateTile(
                            symbol: "arrow.up.circle.fill",
                            label: "Upload",
                            value: interface.map { rate($0.uploadBytesPerSecond, unit: settings.rateUnit) } ?? "—",
                            color: accent.secondary
                        )
                    }
                    NetworkHistoryGraph(
                        samples: store.history.recent(300),
                        selectedInterfaceName: settings.selectedInterfaceName,
                        settings: settings,
                        downloadAccent: downloadAccent,
                        uploadAccent: uploadAccent
                    )
                    .frame(height: 84)
                    if let interface {
                        HStack(spacing: 6) {
                            Chip(
                                text: interface.name, color: accent.primary,
                                symbol: interface.isVPN ? "lock.shield.fill" : "cable.connector")
                            if interface.isVPN {
                                Chip(text: "VPN", color: .purple, symbol: "lock.fill")
                            }
                            if sample?.primary?.name == interface.name {
                                Chip(text: "Primary", color: accent.secondary, symbol: "star.fill")
                            }
                            Spacer()
                            Text(
                                "\(Self.bytes(interface.receivedBytes)) received  ·  "
                                    + "\(Self.bytes(interface.sentBytes)) sent"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                }
            }

            if moduleSettings.showsProcesses, let sample {
                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Top network activity")
                        processActivity(
                            sample: sample,
                            limit: moduleSettings.processCount,
                            unit: settings.rateUnit,
                            decimalPlaces: settings.decimalPlaces,
                            rateOrder: settings.rateOrder,
                            accent: accent
                        )
                    }
                }
            }

            if let sample, let interface {
                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Connection") {
                            if interface.inputErrors > 0 || interface.outputErrors > 0 {
                                Chip(
                                    text: "\(interface.inputErrors) in · \(interface.outputErrors) out errors",
                                    color: .orange, symbol: "exclamationmark.triangle.fill")
                            }
                        }
                        ForEach(interface.ipv4Addresses, id: \.self) { address in
                            CopyableNetworkValue(label: "IPv4", value: address)
                        }
                        ForEach(interface.ipv6Addresses, id: \.self) { address in
                            CopyableNetworkValue(label: "IPv6", value: address)
                        }
                        if let router = sample.router {
                            CopyableNetworkValue(label: "Router", value: router)
                        }
                        ForEach(sample.dnsServers, id: \.self) { address in
                            CopyableNetworkValue(label: "DNS", value: address)
                        }
                        if settings.showsPublicIP {
                            if let ipv4 = sample.publicIP?.ipv4 {
                                CopyableNetworkValue(label: "Public", value: ipv4)
                            }
                            if let ipv6 = sample.publicIP?.ipv6 {
                                CopyableNetworkValue(label: "Public", value: ipv6)
                            }
                            if sample.publicIP?.ipv4 == nil, sample.publicIP?.ipv6 == nil {
                                MetricRow(
                                    label: "Public address", value: "Lookup unavailable", symbol: "globe",
                                    tint: accent.primary)
                            }
                        }
                    }
                }
            }

            if let wifi = sample?.wifi {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Wi-Fi") {
                            if wifi.ssid == nil {
                                Button(Self.locationActionTitle(for: locationAccess())) {
                                    locationAction()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if let rssi = wifi.rssi {
                                Chip(text: "\(rssi) dBm", color: signalColor(rssi), symbol: "wifi")
                            }
                        }
                        MetricRow(
                            label: "Network",
                            value: Self.networkName(ssid: wifi.ssid, access: locationAccess()),
                            symbol: "wifi",
                            tint: accent.primary
                        )
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            if let noise = wifi.noise {
                                StatTile(
                                    symbol: "waveform", label: "Noise", value: "\(noise) dBm", tint: accent.secondary)
                            }
                            if let channel = wifi.channel {
                                StatTile(
                                    symbol: "dot.radiowaves.left.and.right", label: "Channel",
                                    value: "\(channel) · \(wifi.band ?? "—")", tint: accent.primary)
                            }
                            if let transmitRate = wifi.transmitRateMbps {
                                StatTile(
                                    symbol: "speedometer", label: "Transmit rate",
                                    value: String(format: "%.0f Mbps", transmitRate), tint: accent.primary)
                            }
                            if let security = wifi.security {
                                StatTile(
                                    symbol: "lock.fill", label: "Security", value: security, tint: accent.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    static func networkName(ssid: String?, access: LocationAccessState) -> String {
        if let ssid, !ssid.isEmpty {
            return ssid
        }
        return switch access {
        case .notDetermined:
            "Location access required"
        case .authorized:
            "Name unavailable"
        case .denied:
            "Location access is off"
        case .restricted:
            "Location access is restricted"
        case .unavailable:
            "Name unavailable"
        }
    }

    static func locationActionTitle(for access: LocationAccessState) -> String {
        switch access {
        case .notDetermined:
            "Allow Location"
        case .authorized, .unavailable:
            "Retry"
        case .denied, .restricted:
            "Review Access"
        }
    }

    private func subtitle(sample: NetworkSample?, interface: NetworkInterfaceSample?) -> String {
        guard let interface else {
            return sample == nil ? "Waiting for the first sample" : "No active interface"
        }
        var parts = [interface.name]
        if let wifi = sample?.wifi, let ssid = wifi.ssid, sample?.primary?.name == interface.name {
            parts.append(ssid)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func rate(_ value: Double, unit: NetworkRateUnit) -> String {
        NetworkRateFormatter.string(
            bytesPerSecond: value,
            unit: unit,
            decimalPlaces: settingsStore.settings.network.decimalPlaces
        )
    }

    private func signalColor(_ rssi: Int) -> Color {
        switch rssi {
        case ...(-80): .red
        case ...(-67): .orange
        default: .green
        }
    }

    private func interfacePicker(sample: NetworkSample) -> some View {
        Picker("Interface", selection: selectedInterfaceBinding) {
            Text("Automatic (\(sample.primary?.name ?? "unavailable"))").tag(String?.none)
            ForEach(Self.selectableInterfaces(sample), id: \.name) { interface in
                Text(interface.isVPN ? "\(interface.name) (VPN)" : interface.name)
                    .tag(Optional(interface.name))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 200)
    }

    @ViewBuilder
    private func processActivity(
        sample: NetworkSample,
        limit: Int,
        unit: NetworkRateUnit,
        decimalPlaces: Int,
        rateOrder: NetworkRateOrder,
        accent: ModuleAccent
    ) -> some View {
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
                ProcessRow(
                    icon: ProcessIconResolver.image(processIdentifier: process.processIdentifier, path: process.path),
                    name: process.name,
                    detail: "",
                    accent: accent
                ) {
                    VStack(alignment: .trailing, spacing: 1) {
                        if rateOrder == .uploadThenDownload {
                            processRate(
                                "↑", process.uploadBytesPerSecond, unit: unit, decimalPlaces: decimalPlaces,
                                color: accent.secondary)
                            processRate(
                                "↓", process.downloadBytesPerSecond, unit: unit, decimalPlaces: decimalPlaces,
                                color: accent.primary)
                        } else {
                            processRate(
                                "↓", process.downloadBytesPerSecond, unit: unit, decimalPlaces: decimalPlaces,
                                color: accent.primary)
                            processRate(
                                "↑", process.uploadBytesPerSecond, unit: unit, decimalPlaces: decimalPlaces,
                                color: accent.secondary)
                        }
                    }
                    .opacity(1)
                }
            }
        }
    }

    private func processRate(
        _ symbol: String,
        _ value: Double,
        unit: NetworkRateUnit,
        decimalPlaces: Int,
        color: Color
    ) -> some View {
        Text(symbol + NetworkRateFormatter.string(bytesPerSecond: value, unit: unit, decimalPlaces: decimalPlaces))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(.numericText())
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

    static func selectableInterfaces(_ sample: NetworkSample) -> [NetworkInterfaceSample] {
        sample.interfaces
            .filter { $0.isUp && !$0.isLoopback }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}

private struct HeroRate: View {
    let arrow: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.system(size: 11, weight: .bold))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

private struct RateTile: View {
    let symbol: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 22))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetPlate()
    }
}

private struct NetworkHistoryGraph: View {
    let samples: [HistoryEntry<NetworkSample.GraphValue>]
    let selectedInterfaceName: String?
    let settings: NetworkSettings
    let downloadAccent: ModuleAccent
    let uploadAccent: ModuleAccent

    var body: some View {
        let values = samples.suffix(300).compactMap { entry -> (Double, Double)? in
            guard let interface = entry.value.interface(named: selectedInterfaceName) else {
                return nil
            }
            return (interface.downloadBytesPerSecond, interface.uploadBytesPerSecond)
        }
        let observedMaximum = values.reduce(1.0) { maximum, value in max(maximum, value.0, value.1) }
        let ceiling =
            settings.graphScale == .fixed
            ? max(1, settings.fixedGraphMaximumBytesPerSecond)
            : observedMaximum * 1.1
        DualAreaGraph(
            primary: values.map { min(1, $0.0 / ceiling) },
            secondary: values.map { min(1, $0.1 / ceiling) },
            primaryAccent: downloadAccent,
            secondaryAccent: uploadAccent
        )
    }
}

private struct CopyableNetworkValue: View {
    let label: String
    let value: String
    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(didCopy ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .opacity(isHovering || didCopy ? 1 : 0.4)
            .help("Copy \(label)")
        }
        .font(.callout)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
