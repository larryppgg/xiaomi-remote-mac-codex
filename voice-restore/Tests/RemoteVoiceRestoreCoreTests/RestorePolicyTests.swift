import XCTest
@testable import RemoteVoiceRestoreCore

final class RestorePolicyTests: XCTestCase {
    private let doubao = "com.bytedance.inputmethod.doubaoime.pinyin"
    private let wechat = "com.tencent.inputmethod.wetype.pinyin"

    func testRestoreWhenStillDoubao() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: wechat)
        XCTAssertEqual(p.decide(currentActive: doubao, preSessionSource: wechat, persistedLastNonDoubao: nil),
                       .restore(target: wechat))
    }

    func testRestoreUsingPersistedWhenNoPreSession() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: wechat)
        XCTAssertEqual(p.decide(currentActive: doubao, preSessionSource: nil, persistedLastNonDoubao: wechat),
                       .restore(target: wechat))
    }

    func testRestoreUsingFallbackWhenNothingKnown() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: wechat)
        XCTAssertEqual(p.decide(currentActive: doubao, preSessionSource: nil, persistedLastNonDoubao: nil),
                       .restore(target: wechat))
    }

    func testStalePersistedABCDoesNotReplaceConfiguredWechat() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: wechat)
        XCTAssertEqual(p.decide(currentActive: doubao, preSessionSource: nil,
                                persistedLastNonDoubao: "com.apple.keylayout.ABC"),
                       .restore(target: wechat))
    }

    func testNoTargetWhenEverythingIsDoubao() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: doubao)
        XCTAssertEqual(p.decide(currentActive: doubao, preSessionSource: nil, persistedLastNonDoubao: nil), .noTarget)
        let p2 = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: nil)
        XCTAssertEqual(p2.decide(currentActive: doubao, preSessionSource: nil, persistedLastNonDoubao: nil), .noTarget)
    }

    func testManualChoiceIsRespected() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: wechat)
        // User switched to WeChat already -> do nothing.
        XCTAssertEqual(p.decide(currentActive: wechat, preSessionSource: wechat, persistedLastNonDoubao: nil),
                       .activeNotDoubao(active: wechat))
        // User switched to ABC -> do nothing.
        XCTAssertEqual(p.decide(currentActive: "com.apple.keylayout.ABC", preSessionSource: wechat, persistedLastNonDoubao: nil),
                       .activeNotDoubao(active: "com.apple.keylayout.ABC"))
        // Active source unknown -> do nothing.
        XCTAssertEqual(p.decide(currentActive: nil, preSessionSource: wechat, persistedLastNonDoubao: nil),
                       .activeNotDoubao(active: nil))
    }

    func testPreSessionTakesPrecedenceOverPersisted() {
        let p = RestorePolicy(doubaoSourceID: doubao, fallbackTarget: wechat)
        XCTAssertEqual(p.decide(currentActive: doubao,
                                preSessionSource: "com.apple.keylayout.ABC",
                                persistedLastNonDoubao: wechat),
                       .restore(target: "com.apple.keylayout.ABC"))
    }
}
