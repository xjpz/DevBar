import CoreLocation
import Foundation
import NetworkExtension

@MainActor
protocol IOSWiFiSSIDProviding: AnyObject {
    func currentSSID(requestAuthorization: Bool) async -> String?
}

@MainActor
final class IOSWiFiSSIDProvider: NSObject, IOSWiFiSSIDProviding, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func currentSSID(requestAuthorization: Bool) async -> String? {
        if locationManager.authorizationStatus == .notDetermined {
            guard requestAuthorization else { return nil }
            await requestLocationAuthorization()
        }

        let network = await NEHotspotNetwork.fetchCurrent()
        let ssid = network?.ssid.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ssid.isEmpty ? nil : ssid
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func requestLocationAuthorization() async {
        await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            if authorizationWaiters.count == 1 {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }
}
