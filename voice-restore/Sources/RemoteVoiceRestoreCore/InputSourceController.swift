import Foundation
#if canImport(Carbon)
import Carbon
#endif

/// Abstraction over macOS input source access so the restore logic is testable
/// without touching the real system. The production implementation uses the
/// native Text Input Source (TIS / Carbon) API.
public protocol InputSourceControlling {
    /// Input source ID currently active, or nil if unavailable.
    func currentSourceID() -> String?
    /// Select the input source with the given ID. Returns true on success.
    @discardableResult
    func selectSource(id: String) -> Bool
    /// Enumerate installed input source IDs (used to find a known target).
    func availableSourceIDs() -> [String]
}

/// Production implementation backed by macOS TIS.
///
/// TISSelectInputSource requires the calling process to present a bundle
/// identifier (a bundled .app or a binary with an embedded __info_plist), which
/// install.sh ensures. Selecting a source requires no extra permission.
public final class TISInputSourceController: InputSourceControlling {
    public init() {}

    public func currentSourceID() -> String? {
        // A background LaunchAgent can retain its own ABC text-input context
        // while the foreground app has changed to Doubao. HIToolbox records
        // the selected system input mode used by the foreground app.
        if let prefs = UserDefaults(suiteName: "com.apple.HIToolbox") {
            prefs.synchronize()
            if let selected = prefs.array(forKey: "AppleSelectedInputSources") as? [[String: Any]],
               let mode = selected.first?["Input Mode"] as? String {
                return mode
            }
        }
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return inputSourceID(src)
    }

    public func selectSource(id: String) -> Bool {
        guard let target = findSource(id: id) else { return false }
        return TISSelectInputSource(target) == noErr
    }

    public func availableSourceIDs() -> [String] {
        guard let list = TISCreateInputSourceList(nil, true) else { return [] }
        let sources = list.takeRetainedValue() as! [TISInputSource]
        return sources.compactMap { inputSourceID($0) }
    }

    private func findSource(id: String) -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, true) else { return nil }
        let sources = list.takeRetainedValue() as! [TISInputSource]
        return sources.first { inputSourceID($0) == id }
    }

    private func inputSourceID(_ src: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

/// In-memory fake used by deterministic tests.
public final class FakeInputSourceController: InputSourceControlling {
    public var current: String?
    public var selectLog: [String] = []
    public var available: [String] = []
    public var failSelection = false

    public init(current: String?, available: [String]) {
        self.current = current
        self.available = available
    }

    public func currentSourceID() -> String? { current }

    public func selectSource(id: String) -> Bool {
        if failSelection { return false }
        selectLog.append(id)
        current = id
        return true
    }

    public func availableSourceIDs() -> [String] { available }
}
