import XCTest
@testable import GoofCore

final class AppCatalogTests: XCTestCase {
    func testIDsAndBundleIDsAreUnique() {
        let ids = AppCatalog.apps.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "room ids must be unique")
        let bundles = AppCatalog.apps.flatMap(\.bundleIDs)
        XCTAssertEqual(bundles.count, Set(bundles).count, "a bundle id may belong to one app only")
    }

    func testRoomIDsAreURLSafeSlugs() {
        for app in AppCatalog.apps {
            XCTAssertNotNil(app.id.range(of: "^[a-z0-9][a-z0-9-]{1,40}$", options: .regularExpression), app.id)
            XCTAssertNotNil(app.tint.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression), app.id)
            XCTAssertFalse(app.bundleIDs.isEmpty, app.id)
        }
    }

    func testEditionsShareOneRoom() {
        XCTAssertEqual(AppCatalog.app(forBundleID: "com.microsoft.VSCode")?.id, "vscode")
        XCTAssertEqual(AppCatalog.app(forBundleID: "com.microsoft.VSCodeInsiders")?.id, "vscode")
        XCTAssertEqual(AppCatalog.app(forBundleID: "com.jetbrains.intellij.ce")?.id, "intellij")
    }

    func testClassify() {
        XCTAssertEqual(AppCatalog.classify(bundleID: "com.anthropic.claudefordesktop"), .app(AppCatalog.app(id: "claude")!))
        XCTAssertEqual(AppCatalog.classify(bundleID: "com.apple.Safari"), .other)
        XCTAssertEqual(AppCatalog.classify(bundleID: nil), .other)
        XCTAssertEqual(AppCatalog.classify(bundleID: "com.apple.dock"), .ignored)
        XCTAssertEqual(AppCatalog.classify(bundleID: AppCatalog.goofBundleID), .ignored)
        XCTAssertEqual(AppCatalog.classify(bundleID: "org.example.GoofFork", ownBundleID: "org.example.GoofFork"), .ignored)
    }

    func testNoBrowsersOrMessengers() {
        let sensitive = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.tencent.xinWeChat",
                         "com.tencent.qq", "ru.keepcoder.Telegram", "com.apple.MobileSMS", "com.apple.mail"]
        for id in sensitive { XCTAssertNil(AppCatalog.app(forBundleID: id), id) }
    }
}
