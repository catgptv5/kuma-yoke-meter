import CoreLocation
import Foundation

enum SightingEventKind: Equatable {
    case damage
    case sighting
    case camera
    case trace
    case possible
    case other

    var displayName: String {
        switch self {
        case .damage:
            return "被害・接触"
        case .sighting:
            return "目撃"
        case .camera:
            return "カメラ確認"
        case .trace:
            return "痕跡"
        case .possible:
            return "らしき情報"
        case .other:
            return "その他"
        }
    }

    var symbolName: String {
        switch self {
        case .damage:
            return "exclamationmark.triangle.fill"
        case .sighting:
            return "eye.fill"
        case .camera:
            return "camera.fill"
        case .trace:
            return "pawprint.fill"
        case .possible:
            return "questionmark.circle.fill"
        case .other:
            return "mappin"
        }
    }

    var score: Int {
        switch self {
        case .damage:
            return 6
        case .sighting:
            return 3
        case .camera:
            return 2
        case .trace:
            return 2
        case .possible:
            return 1
        case .other:
            return 1
        }
    }
}

enum SightingFreshness: Equatable {
    case withinThreeDays
    case withinSevenDays
    case withinThirtyDays
    case older
    case unknown

    var displayName: String {
        switch self {
        case .withinThreeDays:
            return "3日以内"
        case .withinSevenDays:
            return "7日以内"
        case .withinThirtyDays:
            return "30日以内"
        case .older:
            return "31日以上前"
        case .unknown:
            return "日付不明"
        }
    }

    var score: Int {
        switch self {
        case .withinThreeDays:
            return 5
        case .withinSevenDays:
            return 4
        case .withinThirtyDays:
            return 2
        case .older:
            return 0
        case .unknown:
            return 0
        }
    }
}

enum MapRiskGrade: Equatable {
    case cancelRecommended
    case high
    case caution
    case reference

    var displayName: String {
        switch self {
        case .cancelRecommended:
            return "中止推奨"
        case .high:
            return "高リスク"
        case .caution:
            return "注意"
        case .reference:
            return "参考"
        }
    }
}

struct SightingMapAssessment: Equatable {
    let kind: SightingEventKind
    let freshness: SightingFreshness
    let daysAgo: Int?
    let distanceKm: Double?
    let score: Int
    let grade: MapRiskGrade

    var daysAgoLabel: String? {
        guard let daysAgo else {
            return nil
        }

        if daysAgo == 0 {
            return "今日"
        }
        if daysAgo <= 99 {
            return "\(daysAgo)日"
        }
        return nil
    }

    var detailText: String {
        var parts = [kind.displayName, freshness.displayName]
        if let distanceKm {
            parts.append(String(format: "%.1fkm", distanceKm))
        }
        return parts.joined(separator: " / ")
    }
}

struct SightingMapAssessor {
    static func assess(
        sighting: BearSighting,
        target: TripTarget?,
        referenceDate: Date = Date()
    ) -> SightingMapAssessment {
        let kind = eventKind(for: sighting.detail)
        let daysAgo = daysAgo(for: sighting, referenceDate: referenceDate)
        let freshness = freshness(for: daysAgo)
        let distanceKm = distanceKm(from: target, to: sighting)
        let score = kind.score + freshness.score + distanceScore(distanceKm)
        let grade = grade(for: score, freshness: freshness, kind: kind, distanceKm: distanceKm)

        return SightingMapAssessment(
            kind: kind,
            freshness: freshness,
            daysAgo: daysAgo,
            distanceKm: distanceKm,
            score: score,
            grade: grade
        )
    }

    private static func eventKind(for detail: String) -> SightingEventKind {
        if containsAny(detail, keywords: ["被害", "負傷", "襲", "接触", "侵入", "食害"]) {
            return .damage
        }
        if containsAny(detail, keywords: ["足跡", "フン", "糞", "痕跡", "爪痕", "掘り返し"]) {
            return .trace
        }
        if containsAny(detail, keywords: ["カメラ", "撮影"]) {
            return .camera
        }
        if containsAny(detail, keywords: ["らしき"]) {
            return .possible
        }
        if containsAny(detail, keywords: ["目撃", "確認"]) {
            return .sighting
        }
        return .other
    }

    private static func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.localizedStandardContains($0) }
    }

    private static func daysAgo(for sighting: BearSighting, referenceDate: Date) -> Int? {
        guard let observedAt = sighting.observedAt else {
            return nil
        }

        let days = RiskEvaluator.daysBetween(observedAt, and: referenceDate)
        guard days.isFinite else {
            return nil
        }
        return max(0, Int(floor(days)))
    }

    private static func freshness(for daysAgo: Int?) -> SightingFreshness {
        guard let daysAgo else {
            return .unknown
        }

        if daysAgo <= 3 {
            return .withinThreeDays
        }
        if daysAgo <= 7 {
            return .withinSevenDays
        }
        if daysAgo <= 30 {
            return .withinThirtyDays
        }
        return .older
    }

    private static func distanceKm(from target: TripTarget?, to sighting: BearSighting) -> Double? {
        guard let target else {
            return nil
        }

        let targetLocation = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
        let sightingLocation = CLLocation(latitude: sighting.latitude, longitude: sighting.longitude)
        return targetLocation.distance(from: sightingLocation) / 1_000
    }

    private static func distanceScore(_ distanceKm: Double?) -> Int {
        guard let distanceKm else {
            return 0
        }

        if distanceKm <= 1 {
            return 4
        }
        if distanceKm <= 3 {
            return 2
        }
        if distanceKm <= 5 {
            return 1
        }
        return 0
    }

    private static func grade(
        for score: Int,
        freshness: SightingFreshness,
        kind: SightingEventKind,
        distanceKm: Double?
    ) -> MapRiskGrade {
        if kind == .damage && freshness != .older {
            return .cancelRecommended
        }
        if let distanceKm, distanceKm <= 1, freshness == .withinThreeDays {
            return .cancelRecommended
        }
        if score >= 10 {
            return .cancelRecommended
        }
        if score >= 7 {
            return .high
        }
        if score >= 4 {
            return .caution
        }
        return .reference
    }
}

