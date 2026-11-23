import XCTest
@testable import GoofCore

final class MessagePacerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)

    func testReleasesOneAtATime() {
        var p = MessagePacer<Int>(interval: 0.5, burstInterval: 0.25, burstThreshold: 3, capacity: 10)
        p.enqueue(1); p.enqueue(2)
        XCTAssertEqual(p.release(at: t0), 1)
        XCTAssertNil(p.release(at: t0.addingTimeInterval(0.4)))
        XCTAssertEqual(p.release(at: t0.addingTimeInterval(0.5)), 2)
        XCTAssertNil(p.release(at: t0.addingTimeInterval(5)))
    }

    func testSpeedsUpWhenBacklogGrows() {
        var p = MessagePacer<Int>(interval: 0.5, burstInterval: 0.25, burstThreshold: 3, capacity: 10)
        (1...5).forEach { p.enqueue($0) }
        XCTAssertEqual(p.release(at: t0), 1)
        XCTAssertEqual(p.release(at: t0.addingTimeInterval(0.25)), 2, "4 left > threshold, burst gap applies")
        XCTAssertNil(p.release(at: t0.addingTimeInterval(0.5)), "3 left = threshold, normal gap again")
        XCTAssertEqual(p.release(at: t0.addingTimeInterval(0.75)), 3)
    }

    func testDropsOldestBeyondCapacity() {
        var p = MessagePacer<Int>(capacity: 3)
        (1...5).forEach { p.enqueue($0) }
        XCTAssertEqual(p.pending, [3, 4, 5])
    }
}

final class PauseDurationTests: XCTestCase {
    func testEndDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 15, minute: 10))!
        XCTAssertEqual(PauseDuration.thirtyMinutes.endDate(from: now, calendar: calendar), now.addingTimeInterval(1800))
        XCTAssertEqual(PauseDuration.oneHour.endDate(from: now, calendar: calendar), now.addingTimeInterval(3600))
        XCTAssertEqual(PauseDuration.restOfToday.endDate(from: now, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 0, minute: 0)))
        XCTAssertEqual(PauseDuration.untilResumed.endDate(from: now, calendar: calendar), .distantFuture)
    }
}
