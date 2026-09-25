import Foundation
import Darwin

/// Robust tail of a single UTF-8 log file.
///
/// Handles the situations the requirements call out:
/// - append-only growth (normal SayAll logging)
/// - truncation of the same inode (rewrite in place)
/// - file replacement / rotation (different inode) and recreation
/// - the file not existing yet (SayAll not running or between restarts)
///
/// `startFromEnd: true` means pre-existing content is treated as history and is
/// not delivered, so the helper only reacts to events observed after it starts.
public final class LogReader {
    private let path: String
    private let startFromEnd: Bool
    private let chunkSize: Int

    private var fd: Int32 = -1
    private var offset: UInt64 = 0
    private var currentInode: UInt64 = 0
    private let fileExistedAtStart: Bool
    private var hasOpenedOnce = false
    private var partial = Data()

    public init(path: String, startFromEnd: Bool = true, chunkSize: Int = 65536) {
        self.path = path
        self.startFromEnd = startFromEnd
        self.chunkSize = chunkSize
        var st = stat()
        self.fileExistedAtStart = stat(path, &st) == 0
    }

    deinit {
        if fd >= 0 { close(fd) }
    }

    /// Deliver complete lines (without trailing newline) newly available since
    /// the previous poll. Partial trailing lines are kept until their newline.
    @discardableResult
    public func poll() throws -> [String] {
        try syncFile()
        var lines: [String] = []
        while fd >= 0 {
            var buf = [UInt8](repeating: 0, count: chunkSize)
            let n = pread(fd, &buf, buf.count, off_t(offset))
            if n > 0 {
                offset += UInt64(n)
                partial.append(Data(buf[0..<n]))
            } else if n == 0 {
                break
            } else {
                let err = errno
                if err == EINTR { continue }
                if err == EAGAIN { break }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(err),
                              userInfo: [NSLocalizedDescriptionKey: "read failed on \(path)"])
            }
        }
        while let nl = partial.firstIndex(of: 0x0A) {
            let lineData = partial.subdata(in: 0..<nl)
            partial.removeSubrange(0..<(nl + 1))
            if let s = String(data: lineData, encoding: .utf8) {
                lines.append(s)
            }
        }
        return lines
    }

    /// True when the underlying file is currently open for reading.
    public var isOpen: Bool { fd >= 0 }

    private func syncFile() throws {
        var st = stat()
        let exists = stat(path, &st) == 0

        if !exists {
            if fd >= 0 {
                close(fd); fd = -1
                offset = 0; currentInode = 0; partial = Data()
            }
            return
        }

        let inode = UInt64(st.st_ino)
        let size = UInt64(st.st_size)

        if fd >= 0 {
            if inode != currentInode {
                // Log was replaced/rotated: treat the new file as a fresh log.
                close(fd); fd = -1
                offset = 0; currentInode = 0; partial = Data()
            } else if size < offset {
                // Same file truncated in place: restart from the top.
                offset = 0
                partial = Data()
            }
        }

        if fd < 0 {
            let newFD = open(path, O_RDONLY)
            if newFD < 0 {
                let err = errno
                if err == ENOENT { return } // transient disappearance
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(err),
                              userInfo: [NSLocalizedDescriptionKey: "open failed on \(path)"])
            }
            fd = newFD
            currentInode = inode
            // startFromEnd only applies to the *first* open of a file that
            // already existed when the reader was constructed: that represents
            // "I began watching now; ignore existing history". A file that
            // appears only after startup (SayAll not running yet), or any file
            // opened again after rotation/replacement/recreation, is a fresh
            // log whose contents are new events and must be read from the
            // beginning so nothing is missed.
            if startFromEnd && fileExistedAtStart && !hasOpenedOnce {
                offset = size
            } else {
                offset = 0
            }
            hasOpenedOnce = true
            partial = Data()
        }
    }
}
