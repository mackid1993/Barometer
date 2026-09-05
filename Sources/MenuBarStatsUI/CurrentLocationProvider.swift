@preconcurrency import CoreLocation
import AppKit
import Foundation

/// Location authorization states used by features that do not need coordinates themselves.
public enum LocationAccessState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

/// Tracks the current location and reports authorization failures without making location mandatory.
@MainActor
final class CurrentLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    typealias Update = @MainActor (CLLocation) -> Void
    typealias Failure = @MainActor (Error) -> Void

    static let shared = CurrentLocationProvider()

    private let manager = CLLocationManager()
    private var update: Update?
    private var failure: Failure?
    var authorizationDidChange: (@MainActor (LocationAccessState) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 5_000
    }

    var accessState: LocationAccessState {
        Self.accessState(for: manager.authorizationStatus)
    }

    func requestAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else {
            return
        }
        // Core Location only presents its sheet while the requesting app is in the foreground.
        // LSUIElement applications do not become active merely because a menu or settings control
        // was clicked, so make the direct user action explicit before asking the system.
        NSApp.activate(ignoringOtherApps: true)
        manager.requestWhenInUseAuthorization()
    }

    func start(requestsAuthorization: Bool, update: @escaping Update, failure: @escaping Failure) {
        self.update = update
        self.failure = failure
        switch manager.authorizationStatus {
        case .notDetermined:
            if requestsAuthorization {
                requestAuthorizationIfNeeded()
            }
        case .authorized, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            failure(CurrentLocationError.permissionDenied)
        @unknown default:
            failure(CurrentLocationError.unavailable)
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        update = nil
        failure = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDidChange?(Self.accessState(for: manager.authorizationStatus))
        guard update != nil else {
            return
        }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            failure?(CurrentLocationError.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            failure?(CurrentLocationError.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            update?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        failure?(error)
    }

    private static func accessState(for status: CLAuthorizationStatus) -> LocationAccessState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized, .authorizedAlways:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }
}

private enum CurrentLocationError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Location access is off. Add a saved city, or allow Barometer in Privacy & Security."
        case .unavailable:
            "The current location is unavailable. Add a saved city instead."
        }
    }
}
