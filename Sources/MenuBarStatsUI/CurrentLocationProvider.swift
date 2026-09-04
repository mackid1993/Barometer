@preconcurrency import CoreLocation
import Foundation

/// Tracks the current location and reports authorization failures without making location mandatory.
@MainActor
final class CurrentLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    typealias Update = @MainActor (CLLocation) -> Void
    typealias Failure = @MainActor (Error) -> Void

    static let shared = CurrentLocationProvider()

    private let manager = CLLocationManager()
    private var update: Update?
    private var failure: Failure?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 5_000
    }

    func start(update: @escaping Update, failure: @escaping Failure) {
        self.update = update
        self.failure = failure
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
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
