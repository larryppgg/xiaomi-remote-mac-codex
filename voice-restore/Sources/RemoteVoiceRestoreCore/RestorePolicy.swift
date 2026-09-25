import Foundation

/// What the helper decided to do after a remote voice release.
public enum RestoreDecision: Equatable {
    /// Active source is not Doubao — the user chose something else; leave it alone.
    case activeNotDoubao(active: String?)
    /// Active source is Doubao but we have no known non-Doubao target.
    case noTarget
    /// Active source is still Doubao — switch back to the target.
    case restore(target: String)
}

/// Pure policy: restore the previous input source only if the active source is
/// still Doubao after a remote speech release. Any other active source means the
/// user (or SayAll) already made a choice — never override it.
public struct RestorePolicy: Equatable {
    public let doubaoSourceID: String
    /// Last-resort target when no pre-session/persisted source is known (WeChat).
    public let fallbackTarget: String?

    public init(doubaoSourceID: String, fallbackTarget: String?) {
        self.doubaoSourceID = doubaoSourceID
        self.fallbackTarget = fallbackTarget
    }

    public func decide(
        currentActive: String?,
        preSessionSource: String?,
        persistedLastNonDoubao: String?
    ) -> RestoreDecision {
        guard currentActive == doubaoSourceID else {
            return .activeNotDoubao(active: currentActive)
        }
        // The user's daily keyboard is WeChat. A persisted source may be stale
        // (for example ABC observed by a background agent on an earlier run),
        // so prefer the configured WeChat fallback when this session's source
        // was not captured.
        let target = preSessionSource ?? fallbackTarget ?? persistedLastNonDoubao
        guard let target = target, target != doubaoSourceID else {
            return .noTarget
        }
        return .restore(target: target)
    }
}
