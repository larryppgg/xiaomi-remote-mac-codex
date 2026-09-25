import Foundation

/// Pure state machine over the remote-voice session stream.
///
/// Handles the edge cases called out in the requirements:
/// - overlapping presses (edge=down while a session is already pending)
/// - an orphan edge=up (release seen without a matching down in our window,
///   e.g. we started after the press, or the log rotated mid-session)
/// - Fn injection events are ignored: physical remote streams also emit them
///   on some SayAll paths, and counting both would end one session twice.
public struct SessionTracker: Equatable {
    public enum Action: Equatable {
        /// A doubao press started a new session.
        case started
        /// Another press arrived while a session was already pending.
        case reentered
        /// A pending session released normally.
        case ended
        /// A release arrived with no pending session in our window.
        case orphanEnd
        /// Event does not concern the tracked tool.
        case ignored
    }

    public let tool: String
    public private(set) var pending = false
    /// Input source observed just before the press, if it was not already Doubao.
    public private(set) var preSessionSource: String?

    public init(tool: String) {
        self.tool = tool
    }

    public mutating func onEvent(_ event: VoiceLogEvent) -> Action {
        switch event {
        case .remoteStreamStart:
            if pending {
                // Overlapping press: keep the session open and keep the original
                // pre-session source; do not re-capture over Doubao.
                return .reentered
            }
            pending = true
            preSessionSource = nil
            return .started
        case .remoteStreamStop:
            if pending {
                pending = false
                return .ended
            }
            return .orphanEnd
        case .functionKeyDown, .functionKeyUp, .ignored:
            return .ignored
        }
    }

    /// Record the input source that was active when the press was observed.
    /// Only meaningful while a session is pending.
    public mutating func setPreSessionSource(_ source: String?) {
        guard pending else { return }
        preSessionSource = source
    }

    public mutating func reset() {
        pending = false
        preSessionSource = nil
    }
}
