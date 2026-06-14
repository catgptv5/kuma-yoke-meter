import Combine
import Foundation

@MainActor
final class TripPlanner: ObservableObject {
    @Published var useCurrentLocation = false
    @Published var selectedDestination = TripDestination.presets[0]

    func target(using locationManager: UserLocationManager) -> TripTarget? {
        if useCurrentLocation {
            guard let coordinate = locationManager.coordinate else {
                return nil
            }
            return TripTarget(name: "現在地", coordinate: coordinate)
        }

        return TripTarget(
            name: selectedDestination.name,
            coordinate: selectedDestination.coordinate
        )
    }
}

