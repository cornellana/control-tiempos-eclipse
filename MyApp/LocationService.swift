/// LocationService.swift — One-shot CoreLocation wrapper with @Observable state.
///
/// Requests a single location fix using `CLLocationManager.requestLocation()`.
/// Handles authorization flow automatically.

import CoreLocation
import Observation

/// Provides a single geographic location reading.
///
/// Usage: create an instance with `@State`, call `requestOnce()` on button tap,
/// then observe `coordinate`, `isLoading`, and `locationError`.
@Observable final class LocationService: NSObject {

    // MARK: - Observable state

    /// The most recent coordinate returned by Core Location.
    var coordinate: CLLocationCoordinate2D?

    /// `true` while a request is in flight.
    var isLoading: Bool = false

    /// The most recent Core Location error, if any.
    var locationError: Error?

    /// Current authorization status.
    var authorizationStatus: CLAuthorizationStatus

    // MARK: - Private

    private let manager = CLLocationManager()

    // MARK: - Init

    override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    /// Requests a single location fix. Asks for When-In-Use authorization when needed.
    func requestOnce() {
        locationError = nil
        isLoading = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            isLoading = false
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        isLoading  = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error
        isLoading     = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse ||
           authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else {
            isLoading = false
        }
    }
}
