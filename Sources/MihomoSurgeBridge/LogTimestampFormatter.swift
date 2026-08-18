import Foundation

enum LogTimestampFormatter {
    static func string(
        from date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
