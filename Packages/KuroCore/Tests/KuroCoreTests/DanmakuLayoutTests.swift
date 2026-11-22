import XCTest
@testable import KuroCore

final class DanmakuLayoutTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)

    func testFillsLanesTopDown() {
        var layout = DanmakuLayout(laneCount: 3, panelWidth: 300, speed: 100, gap: 0)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 0)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 1)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 2)
        XCTAssertNil(layout.place(width: 100, at: t0))
    }

    func testLaneFreesOnceTailEnters() {
        var layout = DanmakuLayout(laneCount: 1, panelWidth: 300, speed: 100, gap: 20)
        XCTAssertNotNil(layout.place(width: 100, at: t0))
        XCTAssertNil(layout.place(width: 50, at: t0.addingTimeInterval(1.1)))
        XCTAssertEqual(layout.place(width: 50, at: t0.addingTimeInterval(1.2))?.lane, 0)
    }

    func testDuration() {
        let layout = DanmakuLayout(laneCount: 1, panelWidth: 300, speed: 100, gap: 0)
        XCTAssertEqual(layout.duration(forWidth: 100), 4, accuracy: 0.0001)
    }
}
