import XCTest
@testable import KuroCore

final class MessageRulesTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(MessageRules.normalize("  hi \n\t there\u{0007} "), "hi there")
        XCTAssertEqual(MessageRules.normalize("👨‍👩‍👧"), "👨‍👩‍👧", "keeps zero-width joiners")
    }

    func testValidate() {
        XCTAssertEqual(MessageRules.validate("   "), .failure(.empty))
        XCTAssertEqual(MessageRules.validate(String(repeating: "好", count: 81)), .failure(.tooLong(limit: 80)))
        XCTAssertEqual(MessageRules.validate(" 你好 "), .success("你好"))
    }

    func testRateLimiter() {
        var limiter = SendRateLimiter(minInterval: 3, maxPerMinute: 3)
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(limiter.check("a", at: t0), .allowed)
        limiter.record("a", at: t0)
        XCTAssertEqual(limiter.check("b", at: t0.addingTimeInterval(1)), .tooFast(retryAfter: 2))
        XCTAssertEqual(limiter.check("a", at: t0.addingTimeInterval(4)), .duplicate)
        limiter.record("b", at: t0.addingTimeInterval(4))
        limiter.record("c", at: t0.addingTimeInterval(8))
        XCTAssertEqual(limiter.check("d", at: t0.addingTimeInterval(12)), .tooFast(retryAfter: 48))
        XCTAssertEqual(limiter.check("d", at: t0.addingTimeInterval(61)), .allowed)
    }
}
