//
//  LocationProvider.swift
//  WearLoop
//
//  A single coordinate, asked for only when the user taps a fetch button. There
//  is no background tracking and nothing is stored: the coordinate is used for
//  one request and thrown away.
//

import CoreLocation

protocol LocationProviderProtocol: AnyObject {
    var isAuthorised: Bool { get }
    var isDenied: Bool { get }
    /// Asks for permission if needed, then returns one fix.
    func currentCoordinate() async throws -> CLLocationCoordinate2D
}

final class LocationProvider: NSObject, LocationProviderProtocol, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authorisationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorised: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        var status = manager.authorizationStatus

        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authorisationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw WeatherError.noLocation
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Only one request is ever in flight.
            if let existing = self.continuation {
                existing.resume(throwing: WeatherError.noLocation)
            }
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorisationContinuation?.resume(returning: manager.authorizationStatus)
        authorisationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else {
            continuation?.resume(throwing: WeatherError.noLocation)
            continuation = nil
            return
        }
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: WeatherError.noLocation)
        continuation = nil
    }
}
