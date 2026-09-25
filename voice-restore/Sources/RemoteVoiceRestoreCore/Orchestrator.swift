import Foundation

/// Observable outcome of feeding one log line into the orchestrator.
public enum Outcome: Equatable {
    case ignored
    case started
    case reentered
    case endedPendingRestore            // release seen; restore scheduled (delay > 0)
    case endedActiveNotDoubao(active: String?)
    case endedNoTarget
    case endedRestored(target: String)
    case orphanActiveNotDoubao(active: String?)
    case orphanNoTarget
    case orphanRestored(target: String)
}

/// Wires the pure pieces together: parse lines, track the session, capture the
/// pre-session source, and apply the restore policy after the release.
///
/// - When `restoreDelay <= 0` the restore is applied synchronously inside
///   `process` (used by deterministic tests).
/// - When `restoreDelay > 0` the restore is scheduled on the given queue so the
///   Doubao IME can finish committing before the keyboard returns to WeChat
///   ("松开并完成上屏后"). A scheduled restore is coalesced: any new session
///   start cancels a pending restore.
public final class Orchestrator {
    private let input: InputSourceControlling
    private let stateStore: StateStore?
    private let policy: RestorePolicy
    private var tracker: SessionTracker
    public let restoreDelay: TimeInterval
    private let queue: DispatchQueue
    private var pendingRestoreWork: DispatchWorkItem?

    /// Called with a short human-readable action line (no voice/credentials).
    /// Used for the observability log.
    public var onAction: ((String) -> Void)?

    public init(
        input: InputSourceControlling,
        stateStore: StateStore?,
        doubaoSourceID: String,
        fallbackTarget: String?,
        tool: String = Configuration.defaultTool,
        restoreDelay: TimeInterval = 0,
        queue: DispatchQueue = DispatchQueue.main
    ) {
        self.input = input
        self.stateStore = stateStore
        self.policy = RestorePolicy(doubaoSourceID: doubaoSourceID,
                                    fallbackTarget: fallbackTarget)
        self.tracker = SessionTracker(tool: tool)
        self.restoreDelay = restoreDelay
        self.queue = queue
    }

    public var isPending: Bool { tracker.pending }

    @discardableResult
    public func process(line: String, now: Date = Date()) -> Outcome {
        let event = VoiceLogParser.parse(line: line)
        let action = tracker.onEvent(event)
        switch action {
        case .ignored:
            return .ignored
        case .started:
            cancelPendingRestore()
            capturePreSessionSource()
            return .started
        case .reentered:
            return .reentered
        case .ended:
            return scheduleOrApplyRestore(kind: "ended")
        case .orphanEnd:
            return scheduleOrApplyRestore(kind: "orphan")
        }
    }

    public func reset() {
        cancelPendingRestore()
        tracker.reset()
    }

    private func capturePreSessionSource() {
        let current = input.currentSourceID()
        if let current = current, current != policy.doubaoSourceID {
            tracker.setPreSessionSource(current)
            stateStore?.saveLastNonDoubao(current)
            onAction?("press: active=\(current) recorded-as-pre-session")
        } else if current == nil {
            // Can't read the source; keep whatever the tracker already has.
            if let persisted = stateStore?.loadLastNonDoubao() {
                tracker.setPreSessionSource(persisted)
            }
        } else {
            onAction?("press: active=doubao no pre-session info")
        }
    }

    private func scheduleOrApplyRestore(kind: String) -> Outcome {
        if restoreDelay > 0 {
            cancelPendingRestore()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Mark the work as executing so a fresh session can safely replace it.
                self.pendingRestoreWork = nil
                _ = self.applyRestore(kind: kind)
            }
            pendingRestoreWork = work
            queue.asyncAfter(deadline: .now() + restoreDelay, execute: work)
            return .endedPendingRestore
        }
        return applyRestore(kind: kind)
    }

    @discardableResult
    private func applyRestore(kind: String) -> Outcome {
        let current = input.currentSourceID()
        let pre = tracker.preSessionSource
        let persisted = stateStore?.loadLastNonDoubao()
        let decision = policy.decide(currentActive: current,
                                     preSessionSource: pre,
                                     persistedLastNonDoubao: persisted)
        switch decision {
        case .activeNotDoubao(let active):
            let msg = "\(kind): active=\(active ?? "nil") not doubao, leaving as-is"
            onAction?(msg)
            return kind == "orphan" ? .orphanActiveNotDoubao(active: active)
                                     : .endedActiveNotDoubao(active: active)
        case .noTarget:
            let msg = "\(kind): active=doubao but no known restore target"
            onAction?(msg)
            return kind == "orphan" ? .orphanNoTarget : .endedNoTarget
        case .restore(let target):
            let ok = input.selectSource(id: target)
            let msg = "\(kind): restored active=doubao target=\(target) ok=\(ok)"
            onAction?(msg)
            return kind == "orphan" ? .orphanRestored(target: target)
                                     : .endedRestored(target: target)
        }
    }

    private func cancelPendingRestore() {
        pendingRestoreWork?.cancel()
        pendingRestoreWork = nil
    }
}
