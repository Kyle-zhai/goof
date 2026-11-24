import Foundation

/// Parses the timestamps servers send in JSON: ISO 8601 with a time zone,
/// with or without fractional seconds. Postgres and many other servers send
/// microseconds ("2026-11-22T10:00:00.123456+00:00"), which
/// `ISO8601DateFormatter` does not reliably accept, so the fraction is cut to
/// milliseconds first.
public enum WireDate {
    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
