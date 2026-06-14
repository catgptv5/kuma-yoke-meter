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

