import CoreLocation
import Foundation
import NetworkExtension

@MainActor
final class CurrentWiFiSSIDReader: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Error: Swift.Error {
        case locationServicesDisabled
        case locationPermissionDenied
        case networkUnavailable

        var localizationKey: String {
            switch self {
            case .locationServicesDisabled:
                "Turn on Location Services to read the current iPhone Wi-Fi network."
            case .locationPermissionDenied:
                "Allow precise location access for EspBluFi to read the current iPhone Wi-Fi network."
            case .networkUnavailable:
                "The current iPhone Wi-Fi network is unavailable."
            }
        }
    }

    static let shared = CurrentWiFiSSIDReader()

    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func readSSID() async throws -> String {
        guard CLLocationManager.locationServicesEnabled() else {
            throw Error.locationServicesDisabled
        }

        let authorizationStatus = await requestLocationAuthorizationIfNeeded()
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw Error.locationPermissionDenied
        }
        guard locationManager.accuracyAuthorization == .fullAccuracy else {
            throw Error.locationPermissionDenied
        }

        guard let network = await NEHotspotNetwork.fetchCurrent(), !network.ssid.isEmpty else {
            throw Error.networkUnavailable
        }
        return network.ssid
    }

    private func requestLocationAuthorizationIfNeeded() async -> CLAuthorizationStatus {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        default:
            return locationManager.authorizationStatus
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationContinuation?.resume(returning: manager.authorizationStatus)
        authorizationContinuation = nil
    }
}
