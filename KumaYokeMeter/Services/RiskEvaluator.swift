import CoreLocation
import Foundation

enum RiskLevel: String, Equatable {
    case cancelRecommended
    case highRisk
    case caution
    case normalCaution
    case noRecentInformation

    var displayName: String {
        switch self {
        case .cancelRecommended:
            return "中止推奨"
        case .highRisk:
            return "高リスク"
        case .caution:
            return "注意"
        case .normalCaution:
            return "通常注意"
        case .noRecentInformation:
            return "通常警戒"
        }
    }

    var guidance: String {
        switch self {
        case .cancelRecommended:
            return "直近7日・1km以内に情報があります。予定の中止か、街中ルートへの変更を強く検討してください。"
        case .highRisk:
            return "直近7日・3km以内に情報があります。山道・農道・川沿いは避ける判断が現実的です。"
        case .caution:
            return "直近30日・3km以内に情報があります。目的地や時間帯を見直してください。"
        case .normalCaution:
            return "直近30日・5km以内に情報があります。通常より警戒して、単独行動を避けてください。"
        case .noRecentInformation:
            return "近い範囲の同梱データには直近情報がありません。ただし安全を保証するものではありません。"
        }
    }
}

struct RiskBandCount: Identifiable, Equatable {
    let radiusKm: Double
    let sevenDayCount: Int
    let thirtyDayCount: Int

    var id: Double {
        radiusKm
    }
}

struct NearbySighting: Identifiable, Equatable {
    let sighting: BearSighting
    let distanceKm: Double

    var id: String {
        sighting.id
    }
}

struct RiskSummary: Equatable {
    let targetName: String
    let level: RiskLevel
    let counts: [RiskBandCount]
    let nearbyWithin30Days: [NearbySighting]
    let latestSightingDate: Date?
    let referenceDate: Date
}

struct RiskEvaluator {
    static let radiiKm = [1.0, 3.0, 5.0]

    static func evaluate(
        sightings: [BearSighting],
        target: TripTarget,
        referenceDate: Date = Date()
    ) -> RiskSummary {
        let targetLocation = CLLocation(
            latitude: target.coordinate.latitude,
            longitude: target.coordinate.longitude
        )

        let measuredSightings = sightings.compactMap { sighting -> (BearSighting, Date, Double)? in
            guard let observedAt = sighting.observedAt else {
                return nil
            }
            guard let latitude = sighting.latitude,
                  let longitude = sighting.longitude else {
                return nil
            }

            let location = CLLocation(latitude: latitude, longitude: longitude)
            let distanceKm = targetLocation.distance(from: location) / 1_000
            return (sighting, observedAt, distanceKm)
        }

        let latestSightingDate = measuredSightings.map(\.1).max()

        let counts = radiiKm.map { radiusKm in
            RiskBandCount(
                radiusKm: radiusKm,
                sevenDayCount: measuredSightings.count {
                    $0.2 <= radiusKm && daysBetween($0.1, and: referenceDate) <= 7
                },
                thirtyDayCount: measuredSightings.count {
                    $0.2 <= radiusKm && daysBetween($0.1, and: referenceDate) <= 30
                }
            )
        }

        let level: RiskLevel
        if count(in: counts, radiusKm: 1.0, window: .sevenDays) > 0 {
            level = .cancelRecommended
        } else if count(in: counts, radiusKm: 3.0, window: .sevenDays) > 0 {
            level = .highRisk
        } else if count(in: counts, radiusKm: 3.0, window: .thirtyDays) > 0 {
            level = .caution
        } else if count(in: counts, radiusKm: 5.0, window: .thirtyDays) > 0 {
            level = .normalCaution
        } else {
            level = .noRecentInformation
        }

        let nearby = measuredSightings
            .filter { daysBetween($0.1, and: referenceDate) <= 30 && $0.2 <= 5.0 }
            .sorted {
                if abs($0.2 - $1.2) < 0.001 {
                    return $0.1 > $1.1
                }
                return $0.2 < $1.2
            }
            .map { NearbySighting(sighting: $0.0, distanceKm: $0.2) }

        return RiskSummary(
            targetName: target.name,
            level: level,
            counts: counts,
            nearbyWithin30Days: nearby,
            latestSightingDate: latestSightingDate,
            referenceDate: referenceDate
        )
    }

    static func daysBetween(_ sightingDate: Date, and referenceDate: Date) -> Double {
        let interval = referenceDate.timeIntervalSince(sightingDate)
        guard interval >= 0 else {
            return .infinity
        }
        return interval / 86_400
    }

    private enum Window {
        case sevenDays
        case thirtyDays
    }

    private static func count(in counts: [RiskBandCount], radiusKm: Double, window: Window) -> Int {
        guard let count = counts.first(where: { $0.radiusKm == radiusKm }) else {
            return 0
        }

        switch window {
        case .sevenDays:
            return count.sevenDayCount
        case .thirtyDays:
            return count.thirtyDayCount
        }
    }
}
