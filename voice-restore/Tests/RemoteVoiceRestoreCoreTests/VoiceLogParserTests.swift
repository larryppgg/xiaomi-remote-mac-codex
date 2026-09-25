import XCTest
@testable import RemoteVoiceRestoreCore

final class VoiceLogParserTests: XCTestCase {
    func testParsesDoubaoDownRealLine() {
        let line = "VOICE INPUT function_key edge=down tool=doubao"
        XCTAssertEqual(VoiceLogParser.parse(line: line), .functionKeyDown(tool: "doubao"))
    }

    func testParsesDoubaoUpRealLine() {
        let line = "VOICE INPUT function_key edge=up tool=doubao"
        XCTAssertEqual(VoiceLogParser.parse(line: line), .functionKeyUp(tool: "doubao"))
    }

    func testParsesOtherTools() {
        let down = "VOICE INPUT function_key edge=down tool=weixin"
        let up = "VOICE INPUT function_key edge=up tool=weixin"
        XCTAssertEqual(VoiceLogParser.parse(line: down), .functionKeyDown(tool: "weixin"))
        XCTAssertEqual(VoiceLogParser.parse(line: up), .functionKeyUp(tool: "weixin"))
    }

    func testIgnoresNonFunctionKeyVoiceLines() {
        let prepare = "VOICE INPUT source_prepare tool=doubao result=selected managed=true"
        let restore = "VOICE INPUT source_restore result=selected reason=function_key_up"
        let session = "VOICE INPUT session edge=down reason=function_key_down tool=doubao"
        XCTAssertEqual(VoiceLogParser.parse(line: prepare), .ignored)
        XCTAssertEqual(VoiceLogParser.parse(line: restore), .ignored)
        XCTAssertEqual(VoiceLogParser.parse(line: session), .ignored)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertEqual(VoiceLogParser.parse(line: "ATVV STREAM accepted trace=97 model=rc003"), .ignored)
        XCTAssertEqual(VoiceLogParser.parse(line: "random noise"), .ignored)
        XCTAssertEqual(VoiceLogParser.parse(line: "VOICE INPUT function_key edge=side tool=doubao"), .ignored)
        XCTAssertEqual(VoiceLogParser.parse(line: "VOICE INPUT function_key edge=up"), .ignored)
        XCTAssertEqual(VoiceLogParser.parse(line: ""), .ignored)
    }

    func testParsesPhysicalRemoteStream() {
        XCTAssertEqual(VoiceLogParser.parse(line: "ATVV STREAM START session=111"), .remoteStreamStart(session: "111"))
        XCTAssertEqual(VoiceLogParser.parse(line: "ATVV STREAM STOP session=111 partial_frame_bytes=0"), .remoteStreamStop(session: "111"))
    }
}
