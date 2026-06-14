import CoreLocation
import Foundation

struct TripDestination: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let presets: [TripDestination] = [
        TripDestination(
            id: "maruyama-park",
            name: "円山公園",
            note: "散歩・低山の前に確認",
            latitude: 43.0553,
            longitude: 141.3051
        ),
        TripDestination(
            id: "moiwa",
            name: "藻岩山",
            note: "登山口周辺の確認",
            latitude: 43.0234,
            longitude: 141.3224
        ),
        TripDestination(
            id: "takino",
            name: "滝野すずらん丘陵公園",
            note: "郊外散策の確認",
            latitude: 42.9187,
            longitude: 141.3832
        ),
        TripDestination(
            id: "jyozankei",
            name: "定山渓",
            note: "川沿い・山道の確認",
            latitude: 42.9669,
            longitude: 141.1668
        ),
        TripDestination(
            id: "sapporo-station",
            name: "札幌駅",
            note: "街中比較用",
            latitude: 43.0687,
            longitude: 141.3508
        )
    ]
}
