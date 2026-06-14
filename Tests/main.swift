import CoreLocation
import Foundation

let referenceDate = SightingDateParser.date(dateString: "2026-06-14", timeString: "12:00")!
let target = TripTarget(
    name: "テスト地点",
    coordinate: CLLocationCoordinate2D(latitude: 43.0000, longitude: 141.0000)
)

let oneKmRecent = BearSighting(
    id: "one-km-recent",
    date: "2026-06-13",
    time: "08:00",
    ward: "南区",
    place: "テスト地点付近",
    latitude: 43.0040,
    longitude: 141.0000,
    detail: "ヒグマを目撃",
    sourceYear: 2026
)

let summary = RiskEvaluator.evaluate(
    sightings: [oneKmRecent],
    target: target,
    referenceDate: referenceDate
)

precondition(summary.level == .cancelRecommended, "1km・7日以内は中止推奨になるべきです")
precondition(summary.counts.first(where: { $0.radiusKm == 1.0 })?.sevenDayCount == 1)

let noInfoSummary = RiskEvaluator.evaluate(
    sightings: [],
    target: target,
    referenceDate: referenceDate
)

precondition(noInfoSummary.level == .noRecentInformation, "情報なしは安全ではなく通常警戒にするべきです")

print("RiskEvaluator smoke test passed")

