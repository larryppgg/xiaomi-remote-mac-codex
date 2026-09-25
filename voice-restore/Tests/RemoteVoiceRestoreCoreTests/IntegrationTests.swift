import XCTest
@testable import RemoteVoiceRestoreCore

/// End-to-end: real LogReader over a temp SayAll-style log feeding the
/// Orchestrator, with a fake input controller for the system boundary.
final class IntegrationTests: XCTestCase {
    private let doubao = "com.bytedance.inputmethod.doubaoime.pinyin"
    private let wechat = "com.tencent.inputmethod.wetype.pinyin"

    private var dir: URL!
    private var logURL: URL!
    private var input: FakeInputSourceController!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rvr-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logURL = dir.appendingPathComponent("runtime.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        input = FakeInputSourceController(current: wechat, available: [doubao, wechat])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func append(_ s: String) throws {
        let h = try FileHandle(forWritingTo: logURL)
        try h.seekToEnd()
        try h.write(contentsOf: Data(s.utf8))
        try h.close()
    }

    func testEndToEndSpeechSessionRestoresWechat() throws {
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        _ = try reader.poll() // skip history

        try append("2026-09-24T14:24:36.130Z pid=3432 ver=1.9.21 build=174 ATVV STREAM START session=97\n")
        XCTAssertEqual(try reader.poll().map { o.process(line: $0) }, [.started])

        input.current = doubao // SayAll leaves Doubao active
        try append("2026-09-24T14:24:37.246Z pid=3432 ver=1.9.21 build=174 ATVV STREAM STOP session=97 partial_frame_bytes=0\n")
        XCTAssertEqual(try reader.poll().map { o.process(line: $0) }, [.endedRestored(target: wechat)])
        XCTAssertEqual(input.selectLog, [wechat])
    }

    func testEndToEndIgnoresPreExistingHistoryAndUnrelatedLines() throws {
        // History present before startFromEnd reader begins.
        try append("2026-09-24T12:00:00.000Z VOICE INPUT function_key edge=down tool=doubao\n")
        let o = Orchestrator(input: input, stateStore: nil, doubaoSourceID: doubao,
                             fallbackTarget: wechat, restoreDelay: 0)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), []) // history skipped

        try append("2026-09-24T12:00:01.000Z VOICE INPUT function_key edge=down tool=doubao\n")
        try append("2026-09-24T12:00:02.000Z VOICE INPUT source_prepare tool=doubao result=selected managed=true\n")
        input.current = doubao
        try append("2026-09-24T12:00:03.000Z ATVV STREAM STOP session=1\n")
        let outcomes = try reader.poll().map { o.process(line: $0) }
        XCTAssertEqual(outcomes, [.ignored, .ignored, .orphanRestored(target: wechat)])
        XCTAssertEqual(input.selectLog, [wechat])
    }
}
