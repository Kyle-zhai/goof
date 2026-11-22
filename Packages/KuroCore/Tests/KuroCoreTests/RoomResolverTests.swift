import XCTest
@testable import KuroCore

final class RoomResolverTests: XCTestCase {
    let claude = "claude"
    let figma = "figma"
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeResolver() -> RoomResolver {
        RoomResolver(config: .init(debounce: 3, grace: 45, idleThreshold: 120), allowed: [claude, figma])
    }

    func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testJoinsAfterDebounce() {
        var r = makeResolver()
        XCTAssertEqual(r.frontmostChanged(to: claude, at: t(0)), .none)
        XCTAssertEqual(r.tick(at: t(2)), .none)
        XCTAssertEqual(r.tick(at: t(3)), .active(roomID: claude))
    }

    func testQuickSwitchingDoesNotJoin() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.frontmostChanged(to: figma, at: t(1))
        r.frontmostChanged(to: claude, at: t(2))
        XCTAssertEqual(r.tick(at: t(4)), .none, "claude only stable for 2s")
        XCTAssertEqual(r.tick(at: t(5)), .active(roomID: claude))
    }

    func testNonAllowedAppNeverJoins() {
        var r = makeResolver()
        r.frontmostChanged(to: nil, at: t(0))
        XCTAssertEqual(r.tick(at: t(100)), .none)
    }

    func testShortTripAwayKeepsRoom() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        XCTAssertEqual(r.frontmostChanged(to: nil, at: t(10)), .away(roomID: claude))
        XCTAssertEqual(r.tick(at: t(30)), .away(roomID: claude))
        XCTAssertEqual(r.frontmostChanged(to: claude, at: t(40)), .active(roomID: claude), "rejoin needs no debounce")
    }

    func testGraceExpiryLeavesRoom() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        r.frontmostChanged(to: nil, at: t(10))
        XCTAssertEqual(r.tick(at: t(54)), .away(roomID: claude))
        XCTAssertEqual(r.tick(at: t(55)), .none)
    }

    func testSwitchingBetweenAllowedApps() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        XCTAssertEqual(r.frontmostChanged(to: figma, at: t(10)), .away(roomID: claude))
        XCTAssertEqual(r.tick(at: t(13)), .active(roomID: figma))
    }

    func testIdleMarksAwayThenLeaves() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        XCTAssertEqual(r.idleUpdated(119, at: t(122)), .active(roomID: claude))
        XCTAssertEqual(r.idleUpdated(120, at: t(123)), .away(roomID: claude))
        XCTAssertEqual(r.idleUpdated(165, at: t(168)), .none)
    }

    func testActivityAfterIdleRejoinsDuringGrace() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        r.idleUpdated(130, at: t(133))
        XCTAssertEqual(r.idleUpdated(0, at: t(140)), .active(roomID: claude))
    }

    func testScreenLockLeavesImmediately() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        XCTAssertEqual(r.sessionAwayChanged(true, at: t(5)), .none)
        r.sessionAwayChanged(false, at: t(60))
        XCTAssertEqual(r.tick(at: t(62)), .none)
        XCTAssertEqual(r.tick(at: t(63)), .active(roomID: claude))
    }

    func testPendingRoomIsExposedDuringDebounce() {
        var r = makeResolver()
        r.frontmostChanged(to: figma, at: t(0))
        XCTAssertEqual(r.pendingRoom?.roomID, figma)
        r.tick(at: t(3))
        XCTAssertEqual(r.status, .active(roomID: figma))
        XCTAssertNil(r.pendingRoom, "nothing is pending once the room is joined")
    }

    func testGraceRemainingCountsDownWhileAway() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        XCTAssertNil(r.graceRemaining(at: t(3)))
        r.frontmostChanged(to: nil, at: t(10))
        XCTAssertEqual(r.graceRemaining(at: t(10)), 45)
        XCTAssertEqual(r.graceRemaining(at: t(30)), 25)
        r.frontmostChanged(to: claude, at: t(31))
        XCTAssertNil(r.graceRemaining(at: t(31)))
    }

    func testAllowingCurrentAppLaterJoinsAfterDebounce() {
        var r = RoomResolver(config: .init(debounce: 3, grace: 45, idleThreshold: 120), allowed: [])
        r.frontmostChanged(to: claude, at: t(0))
        XCTAssertEqual(r.tick(at: t(10)), .none)
        r.setAllowed([claude], at: t(10))
        XCTAssertEqual(r.tick(at: t(12)), .none)
        XCTAssertEqual(r.tick(at: t(13)), .active(roomID: claude))
    }

    func testRevokingPermissionExitsImmediately() {
        var r = makeResolver()
        r.frontmostChanged(to: claude, at: t(0))
        r.tick(at: t(3))
        XCTAssertEqual(r.setAllowed([figma], at: t(4)), .none)
    }
}
