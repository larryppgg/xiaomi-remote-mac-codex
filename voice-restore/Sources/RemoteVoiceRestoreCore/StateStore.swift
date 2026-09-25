import Foundation

/// Small on-disk persistence for the last-known non-Doubao input source.
///
/// Only ever stores an input source ID (e.g. "com.tencent.inputmethod.wetype.pinyin").
/// No voice content, transcripts, or credentials are stored. Writes are atomic
/// (temp file + rename) so a crash cannot corrupt state.
public final class StateStore {
    private struct Payload: Codable {
        var lastNonDoubaoSourceID: String
        var updatedAt: Date
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadLastNonDoubao() -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let payload = try? PropertyListDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return payload.lastNonDoubaoSourceID
    }

    @discardableResult
    public func saveLastNonDoubao(_ sourceID: String) -> Bool {
        let payload = Payload(lastNonDoubaoSourceID: sourceID, updatedAt: Date())
        do {
            let data = try PropertyListEncoder().encode(payload)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let dir = url.deletingLastPathComponent()
            let tmp = dir.appendingPathComponent(".state-\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
            return true
        } catch {
            return false
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
