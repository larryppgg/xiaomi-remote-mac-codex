public enum VoiceMode: String, Equatable {
    case wechat, typeless
    public var other: VoiceMode { self == .wechat ? .typeless : .wechat }
}

public enum RouteEffect: Equatable {
    case start(VoiceMode), stop(VoiceMode), mode(VoiceMode), deferred(VoiceMode)
}

/// SayAll's software Left Command hold carries explicit start/stop edges.
/// A lost or repeated edge must never invert the next recording.
public struct VoiceRouter {
    public private(set) var mode: VoiceMode = .wechat
    public private(set) var active: VoiceMode?
    public private(set) var pending: VoiceMode?
    public init() {}

    public mutating func hold(down: Bool) -> [RouteEffect] {
        if down {
            guard active == nil else { return [] }
            active = mode
            return [.start(mode)]
        }
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
        return []
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
        return effects
    }
}

public enum RecoveryAction: Equatable {
    case releaseWeChatKey, cancelTypeless, none
    public static func forSession(_ mode: VoiceMode?) -> RecoveryAction {
        switch mode {
        case .wechat: return .releaseWeChatKey
        case .typeless: return .cancelTypeless
        case nil: return .none
        }
    }
}

/// Persist user intent separately from the event tap's temporary availability.
public enum RecoveryCause: String, CaseIterable {
    case userPause = "user_pause", sayAllExit = "sayall_exit"
    case tapInterrupted = "tap_interrupted", quit, exit
    public func enabledAfterRecovery(wasEnabled: Bool) -> Bool {
        self == .userPause ? false : wasEnabled
    }
    public var resumesInProcess: Bool {
        self == .sayAllExit || self == .tapInterrupted
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

public enum ModeKeyEffect: Equatable { case pass, consume, toggle }

/// Modifier flags may already be cleared on key-up. Release the verified
/// shortcut by key identity, while still requiring the full chord on key-down.
public struct ModeKeyLatch {
    private var held = false
    public init() {}
    public mutating func handle(code: Int64, flags: UInt64, down: Bool, up: Bool) -> ModeKeyEffect {
        if code == SayAllEventFilter.modeKeyCode, up, held {
            held = false
            return .consume
        }
        guard down, SayAllEventFilter.isModeKey(code: code, flags: flags) else { return .pass }
        guard !held else { return .consume }
        held = true
        return .toggle
    }
}
