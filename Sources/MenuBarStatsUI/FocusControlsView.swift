import AppKit
import SwiftUI
import SystemSources

/// Native Focus choices shown from Barometer's Focus menu bar pill.
public struct FocusControlsView: View {
    public static let contentSize = CGSize(width: 260, height: 280)

    private let controller: FocusController

    /// Creates Focus controls backed by the shared controller.
    public init(controller: FocusController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            controls
            if let error = controller.controlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Open Focus Settings…", action: Self.openFocusSettings)
                .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        switch controller.snapshot {
        case .unavailable:
            Label("Focus unavailable", systemImage: "moon.slash")
        case .inactive:
            Label("Focus off", systemImage: "moon")
        case let .active(mode, _):
            Label(mode?.name ?? "Focus on", systemImage: mode?.symbolName ?? "moon.fill")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch controller.snapshot {
        case .unavailable:
            Text("macOS is not exposing Focus state or controls to Barometer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .inactive(modes), let .active(_, modes):
            if modes.isEmpty {
                Text("Mode selection is unavailable, but Focus state is current.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(modes) { mode in
                            Button {
                                Task { await controller.activate(mode) }
                            } label: {
                                Label(mode.name, systemImage: mode.symbolName ?? "moon.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(controller.isChanging || controller.snapshot.activeMode?.id == mode.id)
                        }
                    }
                }
                if controller.snapshot.isActive == true {
                    Button("Turn Focus Off") {
                        Task { await controller.deactivate() }
                    }
                    .disabled(controller.isChanging)
                }
            }
        }
    }

    private static func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
