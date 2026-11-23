import XCTest
@testable import GoofCore

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

    func testDelayShiftsBusyLanesOnly() {
        var layout = DanmakuLayout(laneCount: 2, panelWidth: 300, speed: 100, gap: 0)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 0)   // lane 0 busy until t0 + 1s
        layout.delay(by: 2)                                         // lane 0 busy until t0 + 3s
        XCTAssertEqual(layout.place(width: 100, at: t0.addingTimeInterval(1))?.lane, 1)
        XCTAssertNil(layout.place(width: 100, at: t0.addingTimeInterval(1.5)))
        XCTAssertEqual(layout.place(width: 100, at: t0.addingTimeInterval(3))?.lane, 0)
    }

    func testReset() {
        var layout = DanmakuLayout(laneCount: 1, panelWidth: 300, speed: 100, gap: 0)
        XCTAssertNotNil(layout.place(width: 100, at: t0))
        layout.reset()
        XCTAssertNotNil(layout.place(width: 100, at: t0))
    }

    func testChangingLaneCountAddsAndRemovesLanes() {
        var layout = DanmakuLayout(laneCount: 1, panelWidth: 300, speed: 100, gap: 0)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 0)
        layout.laneCount = 3                                        // the panel got taller
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 1)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 2)
        XCTAssertNil(layout.place(width: 100, at: t0))
        layout.laneCount = 1                                        // and shorter again
        XCTAssertNil(layout.place(width: 100, at: t0))              // lane 0 is still busy
        XCTAssertEqual(layout.place(width: 100, at: t0.addingTimeInterval(1))?.lane, 0)
    }

    func testLaneCountNeverDropsBelowOne() {
        var layout = DanmakuLayout(laneCount: 2, panelWidth: 300, speed: 100, gap: 0)
        layout.laneCount = 0
        XCTAssertEqual(layout.laneCount, 1)
        XCTAssertEqual(layout.place(width: 100, at: t0)?.lane, 0)
        XCTAssertEqual(DanmakuLayout(laneCount: -3).laneCount, 1)
    }
}
