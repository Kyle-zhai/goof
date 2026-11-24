import Foundation

/// "Do not disturb" choices offered in the menu bar and the dashboard.
public enum PauseDuration: String, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes
    case oneHour
    case restOfToday
    case untilResumed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thirtyMinutes: "30 Minutes"
        case .oneHour: "1 Hour"
        case .restOfToday: "Rest of Today"
        case .untilResumed: "Until I Resume"
        }
    }

    /// When the pause ends. `untilResumed` returns `.distantFuture`.
    public func endDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .restOfToday:
            let startOfToday = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(24 * 60 * 60)
        case .untilResumed:
            return .distantFuture
        }
    }
}
