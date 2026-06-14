import CoreLocation
import Foundation

struct BearSighting: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let time: String
    let ward: String
    let place: String
    let latitude: Double
    let longitude: Double
    let detail: String
    let sourceYear: Int
    let sourceType: String?
    let sourceName: String?
    let sourceURL: String?

    init(
        id: String,
        date: String,
        time: String,
        ward: String,
        place: String,
        latitude: Double,
        longitude: Double,
        detail: String,
        sourceYear: Int,
        sourceType: String? = nil,
        sourceName: String? = nil,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.ward = ward
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.detail = detail
        self.sourceYear = sourceYear
        self.sourceType = sourceType
        self.sourceName = sourceName
        self.sourceURL = sourceURL
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var observedAt: Date? {
        SightingDateParser.date(dateString: date, timeString: time)
    }

    var displayDateTime: String {
        if time.isEmpty {
            return date
        }
        return "\(date) \(time)"
    }
}

struct SightingSourceSummary: Codable, Equatable, Identifiable {
    var id: String {
        "\(sourceType)-\(name)"
    }

    let name: String
    let sourceType: String
    let sourceURL: String?
    let status: String
    let latestSightingDate: String?
    let recordCount: Int
    let error: String?

    init(
        name: String,
        sourceType: String,
        sourceURL: String? = nil,
        status: String = "ok",
        latestSightingDate: String? = nil,
        recordCount: Int,
        error: String? = nil
    ) {
        self.name = name
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.status = status
        self.latestSightingDate = latestSightingDate
        self.recordCount = recordCount
        self.error = error
    }
}

struct SightingFeed: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String?
    let recordCount: Int
    let latestSightingDate: String?
    let sources: [SightingSourceSummary]
    let records: [BearSighting]

    static func decode(from data: Data, fallbackSourceName: String) throws -> SightingFeed {
        let decoder = JSONDecoder()

        if let feed = try? decoder.decode(SightingFeed.self, from: data) {
            return feed
        }

        let records = try decoder.decode([BearSighting].self, from: data)
        let latestDate = records.compactMap(\.observedAt).max()
        let latestDateText = latestDate.map {
            DateFormatter.sightingDate.string(from: $0)
        }

        return SightingFeed(
            schemaVersion: 1,
            generatedAt: nil,
            recordCount: records.count,
            latestSightingDate: latestDateText,
            sources: [
                SightingSourceSummary(
                    name: fallbackSourceName,
                    sourceType: "legacy",
                    status: "ok",
                    latestSightingDate: latestDateText,
                    recordCount: records.count
                )
            ],
            records: records
        )
    }
}

enum SightingDateParser {
    static let sapporoTimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

    static func date(dateString: String, timeString: String) -> Date? {
        let dateParts = dateString.split(separator: "-").compactMap { Int($0) }
        guard dateParts.count == 3 else {
            return nil
        }

        let timeParts = timeString.split(separator: ":").compactMap { Int($0) }
        let hour = timeParts.indices.contains(0) ? timeParts[0] : 0
        let minute = timeParts.indices.contains(1) ? timeParts[1] : 0

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = sapporoTimeZone
        components.year = dateParts[0]
        components.month = dateParts[1]
        components.day = dateParts[2]
        components.hour = hour
        components.minute = minute
        return components.date
    }
}

private extension DateFormatter {
    static let sightingDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = SightingDateParser.sapporoTimeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
