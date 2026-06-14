import Combine
import CoreLocation
import Foundation

@MainActor
final class UserLocationManager: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationError: String?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation() {
        locationError = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            locationError = "現在地の利用が許可されていません。設定アプリで位置情報を許可してください。"
        @unknown default:
            locationError = "現在地の権限状態を確認できません。"
        }
    }
}

extension UserLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            coordinate = locations.last?.coordinate
            locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationError = "現在地を取得できませんでした: \(error.localizedDescription)"
        }
    }
}

extension UserLocationManager {
    static var preview: UserLocationManager {
        let manager = UserLocationManager()
        manager.coordinate = CLLocationCoordinate2D(latitude: 43.0553, longitude: 141.3051)
        return manager
    }
}
