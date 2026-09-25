import XCTest
@testable import RemoteVoiceRestoreCore

final class LogReaderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rvr-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var logURL: URL { dir.appendingPathComponent("runtime.log") }

    private func append(_ s: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(s.utf8))
    }

    private func makeFile() throws {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }

    func testStartFromEndSkipsHistory() throws {
        try makeFile()
        try append("old line 1\n", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), [])
        try append("new line\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["new line"])
    }

    func testReadsAppendedLinesAndWaitsForNewline() throws {
        // Partial content pre-exists; read from the beginning so it is captured.
        try makeFile()
        try append("partial without newline", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: false)
        XCTAssertEqual(try reader.poll(), []) // held without newline
        try append(" still partial", to: logURL)
        XCTAssertEqual(try reader.poll(), []) // still held
        try append("\nnext\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["partial without newline still partial", "next"])
        XCTAssertEqual(try reader.poll(), [])
    }

    func testStartFromBeginningReadsHistory() throws {
        try makeFile()
        try append("history one\nhistory two\n", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: false)
        XCTAssertEqual(try reader.poll(), ["history one", "history two"])
    }

    func testTruncationSameInodeContinuesFromTop() throws {
        try makeFile()
        try append("line a\nline b\nline c\n", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), []) // skipped history

        // Simulate in-place truncation + rewrite (same inode).
        let th = try FileHandle(forWritingTo: logURL)
        try th.truncate(atOffset: 0)
        try th.close()
        try append("line x\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["line x"])
    }

    func testRotationReplacesFile() throws {
        try makeFile()
        try append("old content\n", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), [])

        // Rotate: rename current log aside, create a fresh one, append new lines.
        let rotated = dir.appendingPathComponent("runtime.log.1")
        try FileManager.default.moveItem(at: logURL, to: rotated)
        try makeFile()
        try append("post rotation line\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["post rotation line"])
    }

    func testFileAppearsLater() throws {
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), [])
        try makeFile()
        try append("appeared\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["appeared"])
    }

    func testFileDeletedThenRecreated() throws {
        try makeFile()
        try append("first\n", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), [])
        try FileManager.default.removeItem(at: logURL)
        XCTAssertEqual(try reader.poll(), [])
        try makeFile()
        try append("second\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["second"])
    }

    func testNonUtf8BytesDoNotCorruptStream() throws {
        try makeFile()
        try append("good line\n", to: logURL)
        let reader = LogReader(path: logURL.path, startFromEnd: true)
        XCTAssertEqual(try reader.poll(), [])
        // Append raw bytes that are not valid UTF-8.
        let h = try FileHandle(forWritingTo: logURL)
        try h.seekToEnd()
        try h.write(contentsOf: Data([0x62, 0x61, 0x64, 0xFF, 0x62, 0x79, 0x74, 0x65, 0x73, 0x0A]))
        try h.close()
        // Bad line is dropped; stream continues.
        try append("good again\n", to: logURL)
        XCTAssertEqual(try reader.poll(), ["good again"])
    }
}
