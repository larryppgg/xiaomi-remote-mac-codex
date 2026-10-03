public enum VoiceMode: String, Equatable {
    case wechat, typeless
    public var other: VoiceMode { self == .wechat ? .typeless : .wechat }
}

public enum RouteEffect: Equatable {
    case start(VoiceMode), stop(VoiceMode), mode(VoiceMode), deferred(VoiceMode)
}

/// SayAll's Fn tap mode emits one pulse after audio preparation and another
/// after audio drains. Route those pulses, preserving its timing and audio.
public struct VoiceRouter {
    public private(set) var mode: VoiceMode = .wechat
    public private(set) var active: VoiceMode?
    public private(set) var pending: VoiceMode?
    private var pulseHeld = false
    public init() {}

    public mutating func pulse(down: Bool) -> [RouteEffect] {
        if !down { pulseHeld = false; return [] }
        guard !pulseHeld else { return [] }
        pulseHeld = true
        if let active {
            self.active = nil
            var effects: [RouteEffect] = [.stop(active)]
            if let pending {
                mode = pending
                self.pending = nil
                effects.append(.mode(mode))
            }
            return effects
        }
        active = mode
        return [.start(mode)]
    }

    public mutating func toggle() -> [RouteEffect] {
        let next = (pending ?? mode).other
        if active != nil {
            pending = next == mode ? nil : next
            return [.deferred(next)]
        }
        mode = next
        return [.mode(mode)]
    }

    /// Return the previous local session for caller-specific cleanup. Typeless
    /// is a toggle API: recovery must cancel, never blindly replay its chord.
    public mutating func reset() -> [RouteEffect] {
        let effects = active.map { [RouteEffect.stop($0)] } ?? []
        active = nil
        pending = nil
        pulseHeld = false
        return effects
    }
}

public enum RecoveryAction: Equatable {
    case releaseFn, cancelTypeless, none
    public static func forSession(_ mode: VoiceMode?) -> RecoveryAction {
        switch mode {
        case .wechat: return .releaseFn
        case .typeless: return .cancelTypeless
        case nil: return .none
        }
    }
}

public enum StreamBoundary { case started, stopped, boot }
public enum StreamIdleGuard {
    public static func isSafe(last: StreamBoundary?, age: Double) -> Bool {
        guard let last else { return false }
        switch last {
        case .started: return false
        case .stopped, .boot: return age >= 3
        }
    }
}

public enum SayAllEventFilter {
    public static let marker: Int64 = 0x5849_414F
    public static let modeKeyCode: Int64 = 80 // F19
    public static let modeFlags: UInt64 = 0x1C0000 // Command + Option + Control
    public static let shortcutFlagMask: UInt64 = 0x1E0000
    public static func accepts(marker: Int64, sourceIsSayAll: Bool) -> Bool {
        marker == Self.marker && sourceIsSayAll
    }
    public static func isModeKey(code: Int64, flags: UInt64) -> Bool {
        code == modeKeyCode && flags & shortcutFlagMask == modeFlags
    }
}
