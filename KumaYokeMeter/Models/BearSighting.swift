import CoreLocation
import Foundation

struct BearSighting: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let time: String
    let ward: String
    let place: String
    let latitude: Double?
    let longitude: Double?
    let detail: String
    let sourceYear: Int
    let sourceType: String?
    let sourceName: String?
    let sourceURL: String?
    let municipality: String?
    let area: String?
    let locationText: String?
    let description: String?
    let eventType: String?
    let locationAccuracy: String?
    let locationAccuracyMeters: Int?

    init(
        id: String,
        date: String,
        time: String,
        ward: String,
        place: String,
        latitude: Double?,
        longitude: Double?,
        detail: String,
        sourceYear: Int,
        sourceType: String? = nil,
        sourceName: String? = nil,
        sourceURL: String? = nil,
        municipality: String? = nil,
        area: String? = nil,
        locationText: String? = nil,
        description: String? = nil,
        eventType: String? = nil,
        locationAccuracy: String? = nil,
        locationAccuracyMeters: Int? = nil
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
        self.municipality = municipality
        self.area = area
        self.locationText = locationText
        self.description = description
        self.eventType = eventType
        self.locationAccuracy = locationAccuracy
        self.locationAccuracyMeters = locationAccuracyMeters
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case time
        case ward
        case place
        case latitude
        case longitude
        case detail
        case sourceYear
        case sourceType
        case sourceName
        case sourceURL
        case sourceUrl
        case municipality
        case area
        case locationText
        case description
        case eventType
        case locationAccuracy
        case locationAccuracyMeters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
        ward = try container.decodeIfPresent(String.self, forKey: .ward) ?? ""
        place = try container.decodeIfPresent(String.self, forKey: .place)
            ?? container.decodeIfPresent(String.self, forKey: .locationText)
            ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? ""
        sourceYear = try container.decodeIfPresent(Int.self, forKey: .sourceYear)
            ?? Int(date.prefix(4))
            ?? 0
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
            ?? container.decodeIfPresent(String.self, forKey: .sourceUrl)
        municipality = try container.decodeIfPresent(String.self, forKey: .municipality)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        locationText = try container.decodeIfPresent(String.self, forKey: .locationText)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
        locationAccuracy = try container.decodeIfPresent(String.self, forKey: .locationAccuracy)
        locationAccuracyMeters = try container.decodeIfPresent(Int.self, forKey: .locationAccuracyMeters)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(time, forKey: .time)
        try container.encode(ward, forKey: .ward)
        try container.encode(place, forKey: .place)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encode(detail, forKey: .detail)
        try container.encode(sourceYear, forKey: .sourceYear)
        try container.encodeIfPresent(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(municipality, forKey: .municipality)
        try container.encodeIfPresent(area, forKey: .area)
        try container.encodeIfPresent(locationText, forKey: .locationText)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(eventType, forKey: .eventType)
        try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)
        try container.encodeIfPresent(locationAccuracyMeters, forKey: .locationAccuracyMeters)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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

    var displayLocation: String {
        locationText ?? place
    }

    var displayDetail: String {
        description ?? detail
    }

    var displayArea: String {
        if let municipality, let area, !area.isEmpty {
            return "\(municipality) \(area)"
        }
        if let municipality {
            return municipality
        }
        return ward
    }
}

struct SightingSourceSummary: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let sourceType: String
    let sourceURL: String?
    let sourceUrl: String?
    let status: String
    let latestSightingDate: String?
    let recordCount: Int
    let error: String?

    init(
        id: String? = nil,
        name: String,
        sourceType: String,
        sourceURL: String? = nil,
        status: String = "ok",
        latestSightingDate: String? = nil,
        recordCount: Int,
        error: String? = nil
    ) {
        self.id = id ?? "\(sourceType)-\(name)"
        self.name = name
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.sourceUrl = sourceURL
        self.status = status
        self.latestSightingDate = latestSightingDate
        self.recordCount = recordCount
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceType
        case sourceURL
        case sourceUrl
        case status
        case latestSightingDate
        case recordCount
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sourceType = try container.decode(String.self, forKey: .sourceType)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
            ?? container.decodeIfPresent(String.self, forKey: .sourceUrl)
        sourceUrl = sourceURL
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(sourceType)-\(name)"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "ok"
        latestSightingDate = try container.decodeIfPresent(String.self, forKey: .latestSightingDate)
        recordCount = try container.decodeIfPresent(Int.self, forKey: .recordCount) ?? 0
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct SightingSourceError: Codable, Equatable, Identifiable {
    var id: String {
        "\(sourceId)-\(occurredAt)"
    }

    let sourceId: String
    let message: String
    let occurredAt: String
}

struct SightingFeed: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String?
    let recordCount: Int
    let latestSightingDate: String?
    let sources: [SightingSourceSummary]
    let errors: [SightingSourceError]
    let records: [BearSighting]

    init(
        schemaVersion: Int,
        generatedAt: String?,
        recordCount: Int,
        latestSightingDate: String?,
        sources: [SightingSourceSummary],
        errors: [SightingSourceError] = [],
        records: [BearSighting]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.recordCount = recordCount
        self.latestSightingDate = latestSightingDate
        self.sources = sources
        self.errors = errors
        self.records = records
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case recordCount
        case latestSightingDate
        case sources
        case errors
        case records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        sources = try container.decodeIfPresent([SightingSourceSummary].self, forKey: .sources) ?? []
        errors = try container.decodeIfPresent([SightingSourceError].self, forKey: .errors) ?? []
        records = try container.decode([BearSighting].self, forKey: .records)
        recordCount = try container.decodeIfPresent(Int.self, forKey: .recordCount) ?? records.count
        latestSightingDate = try container.decodeIfPresent(String.self, forKey: .latestSightingDate)
    }

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
            errors: [],
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
