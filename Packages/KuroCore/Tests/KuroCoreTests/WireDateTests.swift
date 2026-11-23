import XCTest
@testable import KuroCore

final class WireDateTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_795_341_600) // 2026-11-22T10:00:00Z

    func testFormatsServersSend() throws {
        XCTAssertEqual(WireDate.parse("2026-11-22T10:00:00Z"), reference)
        XCTAssertEqual(WireDate.parse("2026-11-22T10:00:00+00:00"), reference)
        XCTAssertEqual(WireDate.parse("2026-11-22T18:00:00+08:00"), reference)

        let millis = try XCTUnwrap(WireDate.parse("2026-11-22T10:00:00.250Z"))
        XCTAssertEqual(millis.timeIntervalSince(reference), 0.25, accuracy: 0.001)

        // Postgres timestamptz in JSON: microseconds and a numeric offset.
        let micros = try XCTUnwrap(WireDate.parse("2026-11-22T10:00:00.123456+00:00"))
        XCTAssertEqual(micros.timeIntervalSince(reference), 0.123, accuracy: 0.001)
    }

    func testRejectsGarbage() {
        XCTAssertNil(WireDate.parse(""))
        XCTAssertNil(WireDate.parse("yesterday"))
        XCTAssertNil(WireDate.parse("2026-11-22"))
    }
}
