import XCTest
@testable import RemoteVoiceRestoreCore

final class SessionTrackerTests: XCTestCase {
    func testNormalDownUp() {
        var t = SessionTracker(tool: "doubao")
        XCTAssertEqual(t.onEvent(.remoteStreamStart(session: "1")), .started)
        XCTAssertTrue(t.pending)
        XCTAssertEqual(t.onEvent(.remoteStreamStop(session: "1")), .ended)
        XCTAssertFalse(t.pending)
    }

    func testOverlappingPresses() {
        var t = SessionTracker(tool: "doubao")
        XCTAssertEqual(t.onEvent(.remoteStreamStart(session: "1")), .started)
        XCTAssertEqual(t.onEvent(.remoteStreamStart(session: "1")), .reentered)
        XCTAssertTrue(t.pending)
        XCTAssertEqual(t.onEvent(.remoteStreamStop(session: "1")), .ended)
        XCTAssertFalse(t.pending)
    }

    func testOrphanUp() {
        var t = SessionTracker(tool: "doubao")
        XCTAssertEqual(t.onEvent(.remoteStreamStop(session: "1")), .orphanEnd)
    }

    func testOtherToolIgnored() {
        var t = SessionTracker(tool: "doubao")
        XCTAssertEqual(t.onEvent(.functionKeyDown(tool: "weixin")), .ignored)
        XCTAssertEqual(t.onEvent(.functionKeyUp(tool: "weixin")), .ignored)
        XCTAssertFalse(t.pending)
        XCTAssertEqual(t.onEvent(.ignored), .ignored)
    }

    func testPreSessionSourceCapturedOnlyWhilePending() {
        var t = SessionTracker(tool: "doubao")
        t.setPreSessionSource("abc")
        XCTAssertNil(t.preSessionSource)

        _ = t.onEvent(.remoteStreamStart(session: "1"))
        t.setPreSessionSource("com.tencent.inputmethod.wetype.pinyin")
        XCTAssertEqual(t.preSessionSource, "com.tencent.inputmethod.wetype.pinyin")

        // A second press must not clear an already-captured pre-session source.
        _ = t.onEvent(.remoteStreamStart(session: "1"))
        XCTAssertEqual(t.preSessionSource, "com.tencent.inputmethod.wetype.pinyin")

        _ = t.onEvent(.remoteStreamStop(session: "1"))
        t.setPreSessionSource("abc")
        XCTAssertEqual(t.preSessionSource, "com.tencent.inputmethod.wetype.pinyin")
    }

    func testFunctionKeyMarkersDoNotDoubleCountRemoteStream() {
        var t = SessionTracker(tool: "doubao")
        XCTAssertEqual(t.onEvent(.remoteStreamStart(session: "111")), .started)
        XCTAssertEqual(t.onEvent(.functionKeyDown(tool: "doubao")), .ignored)
        XCTAssertEqual(t.onEvent(.remoteStreamStop(session: "111")), .ended)
        XCTAssertEqual(t.onEvent(.functionKeyUp(tool: "doubao")), .ignored)
        XCTAssertFalse(t.pending)
    }
}
