import Foundation
import Dispatch
import Darwin

/// Ordered metadata only. No transcript, audio, or keyboard contents are retained.
public struct SayAllVoiceEdge: Equatable {
    public let pid: Int32
    public let down: Bool

    public static func parse(_ line: String) -> SayAllVoiceEdge? {
        let fields = line.split(separator: " ")
        guard fields.count == 8, fields[1].hasPrefix("pid="),
              let pid = Int32(fields[1].dropFirst(4)), pid > 0,
              fields[2].hasPrefix("ver="), fields[3].hasPrefix("build="),
              fields[4] == "VOICE", fields[5] == "KEY",
              fields[6] == "mode=left_command",
              fields[7] == "DOWN" || fields[7] == "UP" else { return nil }
        return SayAllVoiceEdge(pid: pid, down: fields[7] == "DOWN")
    }
}

/// Watches append/rotation on the existing SayAll log. One main-queue owner
/// preserves down/up order even when several notifications coalesce.
public final class VoiceEdgeReader {
    private let url: URL
    private let receive: (SayAllVoiceEdge) -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var inode: ino_t = 0
    private var offset: off_t = 0
    private var partial = Data()
    private var discardingLine = false
    private var openedBefore = false

    public init(url: URL, receive: @escaping (SayAllVoiceEdge) -> Void) {
        self.url = url
        self.receive = receive
    }

    @discardableResult public func start() -> Bool {
        guard directorySource == nil else { return true }
        let directoryFD = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard directoryFD >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.reconcile() }
        source.setCancelHandler { close(directoryFD) }
        directorySource = source
        // Initial attachment skips existing bytes, including an unfinished line.
        reconcile()
        openedBefore = true // A file created later contains new events, not history.
        source.resume()
        guard fd >= 0 else { stop(); return false }
        return true
    }

    public func stop() {
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
        fd = -1
        partial.removeAll()
        openedBefore = false
        inode = 0
        offset = 0
        discardingLine = false
    }

    private func reconcile() {
        guard directorySource != nil else { return }
        var info = stat()
        guard stat(url.path, &info) == 0 else { return }
        if fd >= 0, inode == info.st_ino { drain(); return }
        // Drain the old inode before attaching its replacement after rotation.
        if fd >= 0, !drain() { return }
        fileSource?.cancel()
        fileSource = nil
        fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return }
        guard fstat(fd, &info) == 0 else { close(fd); fd = -1; return }
        inode = info.st_ino
        offset = openedBefore ? 0 : info.st_size
        openedBefore = true
        partial.removeAll()
        discardingLine = false
        let currentFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: currentFD,
            eventMask: [.write, .extend, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.reconcile() }
        source.setCancelHandler { close(currentFD) }
        fileSource = source
        source.resume()
        drain()
    }

    @discardableResult private func drain() -> Bool {
        guard fd >= 0 else { return true }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return true }
        if info.st_size < offset {
            offset = 0
            partial.removeAll()
            discardingLine = false
        }
        // Bound each main-queue turn; continue through queued work if needed.
        var remaining = 262_144
        var buffer = [UInt8](repeating: 0, count: 4096)
        while remaining > 0 {
            let count = pread(fd, &buffer, min(buffer.count, remaining), offset)
            guard count > 0 else { break }
            offset += off_t(count)
            remaining -= count
            for byte in buffer.prefix(count) {
                if byte == 10 {
                    if !discardingLine, let line = String(data: partial, encoding: .utf8),
                       let edge = SayAllVoiceEdge.parse(line) { receive(edge) }
                    partial.removeAll(keepingCapacity: true)
                    discardingLine = false
                } else if !discardingLine {
                    if partial.count < 1024 { partial.append(byte) }
                    else { partial.removeAll(keepingCapacity: true); discardingLine = true }
                }
            }
        }
        if remaining == 0 {
            DispatchQueue.main.async { [weak self] in self?.reconcile() }
            return false // Preserve the old inode until its ordered tail is drained.
        }
        return true
    }

    deinit { stop() }
}
