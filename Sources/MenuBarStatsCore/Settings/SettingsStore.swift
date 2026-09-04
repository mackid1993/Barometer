import Foundation
import Observation
import OSLog

/// Observable, debounced persistence for application settings.
@MainActor
@Observable
public final class SettingsStore {
    /// The defaults key containing the encoded settings document.
    public static let defaultsKey = "settings"

    /// Current application settings.
    public var settings: AppSettings {
        didSet {
            scheduleSave()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.barometer.app",
        category: "settings"
    )

    /// Creates a settings store backed by the supplied defaults suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    deinit {
        saveTask?.cancel()
    }

    /// Replaces the current settings with a decoded JSON document.
    public func importJSON(_ data: Data) throws {
        settings = try JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// Encodes the current settings for export.
    public func exportJSON() throws -> Data {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// Immediately writes current settings, canceling any pending debounce.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            defaults.set(try encoder.encode(settings), forKey: Self.defaultsKey)
        } catch {
            let message = "Unable to encode settings: \(String(describing: error))"
            logger.error("\(message, privacy: .public)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            self?.saveNow()
        }
    }
}
