import XCTest
@testable import RemoteVoiceRestoreCore

final class OrchestratorTests: XCTestCase {
    private let doubao = "com.bytedance.inputmethod.doubaoime.pinyin"
    private let wechat = "com.tencent.inputmethod.wetype.pinyin"
    private let abc = "com.apple.keylayout.ABC"

    private func makeInput(_ current: String?) -> FakeInputSourceController {
        FakeInputSourceController(current: current, available: [doubao, wechat, abc])
    }

    private func tempStateURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rvr-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.plist")
    }

    private func downLine() -> String {
        "ATVV STREAM START session=1"
    }
    private func upLine() -> String {
        "ATVV STREAM STOP session=1"
    }

    func testFullFlowRestoresWechat() throws {
        let input = makeInput(wechat)
        let state = StateStore(url: try tempStateURL())
        let o = Orchestrator(input: input, stateStore: state, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)

        XCTAssertEqual(o.process(line: downLine()), .started)
        XCTAssertEqual(state.loadLastNonDoubao(), wechat)

        input.current = doubao // SayAll selected Doubao
        XCTAssertEqual(o.process(line: upLine()), .endedRestored(target: wechat))
        XCTAssertEqual(input.selectLog, [wechat])
        XCTAssertEqual(input.current, wechat)
    }

    func testManualSwitchToAnotherSourceIsRespected() throws {
        let input = makeInput(wechat)
        let state = StateStore(url: try tempStateURL())
        let o = Orchestrator(input: input, stateStore: state, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)

        _ = o.process(line: downLine())
        input.current = abc // user manually switched to ABC during speech
        XCTAssertEqual(o.process(line: upLine()), .endedActiveNotDoubao(active: abc))
        XCTAssertEqual(input.selectLog, [])
        XCTAssertEqual(input.current, abc)
    }

    func testManualReturnToWechatIsRespected() throws {
        let input = makeInput(wechat)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        _ = o.process(line: downLine())
        input.current = wechat // SayAll's own restore actually worked
        XCTAssertEqual(o.process(line: upLine()), .endedActiveNotDoubao(active: wechat))
        XCTAssertEqual(input.selectLog, [])
    }

    func testPressAlreadyOnDoubaoFallsBackToPersisted() throws {
        let input = makeInput(doubao) // SayAll switched before we could read
        let state = StateStore(url: try tempStateURL())
        XCTAssertTrue(state.saveLastNonDoubao(wechat))
        let o = Orchestrator(input: input, stateStore: state, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        XCTAssertEqual(o.process(line: downLine()), .started)
        XCTAssertEqual(o.process(line: upLine()), .endedRestored(target: wechat))
        XCTAssertEqual(input.selectLog, [wechat])
    }

    func testNoTargetDoesNothing() throws {
        let input = makeInput(doubao)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: nil, restoreDelay: 0)
        _ = o.process(line: downLine())
        XCTAssertEqual(o.process(line: upLine()), .endedNoTarget)
        XCTAssertEqual(input.selectLog, [])
    }

    func testOrphanUpRestoresFromPersisted() throws {
        let input = makeInput(doubao)
        let state = StateStore(url: try tempStateURL())
        XCTAssertTrue(state.saveLastNonDoubao(wechat))
        let o = Orchestrator(input: input, stateStore: state, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        XCTAssertEqual(o.process(line: upLine()), .orphanRestored(target: wechat))
        XCTAssertEqual(input.selectLog, [wechat])
    }

    func testOrphanUpRespectsManualChoice() throws {
        let input = makeInput(abc)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        XCTAssertEqual(o.process(line: upLine()), .orphanActiveNotDoubao(active: abc))
        XCTAssertEqual(input.selectLog, [])
    }

    func testOverlappingPressesRestoreOnce() throws {
        let input = makeInput(wechat)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        XCTAssertEqual(o.process(line: downLine()), .started)
        XCTAssertEqual(o.process(line: downLine()), .reentered)
        input.current = doubao
        XCTAssertEqual(o.process(line: upLine()), .endedRestored(target: wechat))
        XCTAssertEqual(input.selectLog, [wechat])
        XCTAssertEqual(input.current, wechat)
    }

    func testOtherToolIgnored() throws {
        let input = makeInput(doubao)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        XCTAssertEqual(o.process(line: "VOICE INPUT function_key edge=down tool=weixin"), .ignored)
        XCTAssertEqual(o.process(line: "VOICE INPUT function_key edge=up tool=weixin"), .ignored)
        XCTAssertEqual(input.selectLog, [])
        XCTAssertFalse(o.isPending)
    }

    func testDelayedRestoreHappensAfterRelease() throws {
        let input = makeInput(wechat)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0.05,
                             queue: DispatchQueue(label: "test-delay"))
        _ = o.process(line: downLine())
        input.current = doubao
        XCTAssertEqual(o.process(line: upLine()), .endedPendingRestore)
        XCTAssertEqual(input.selectLog, [])

        let done = expectation(description: "restore applied after delay")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(input.selectLog, [wechat])
        XCTAssertEqual(input.current, wechat)
    }

    func testNewSessionCancelsPendingRestore() throws {
        let input = makeInput(wechat)
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0.05,
                             queue: DispatchQueue(label: "test-cancel"))
        _ = o.process(line: downLine())
        input.current = doubao
        XCTAssertEqual(o.process(line: upLine()), .endedPendingRestore)
        // New press arrives before the delayed restore fires.
        XCTAssertEqual(o.process(line: downLine()), .started)
        XCTAssertEqual(input.selectLog, [])

        let done = expectation(description: "wait past original delay")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(input.selectLog, [])
        XCTAssertEqual(input.current, doubao) // untouched
    }
}
