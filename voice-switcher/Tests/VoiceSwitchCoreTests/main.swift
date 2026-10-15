import VoiceSwitchCore

func requireEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    precondition(a == b, "Expected \(b), got \(a)", file: file, line: line)
}
func requireNil<T>(_ a: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(a == nil, "Expected nil", file: file, line: line)
}
func requireTrue(_ a: Bool) { precondition(a) }
func requireFalse(_ a: Bool) { precondition(!a) }

final class VoiceRouterChecks {
    func testWechatHoldHasExplicitRelease() {
        var r = VoiceRouter()
        requireEqual(r.hold(down: true), [.start(.wechat)])
        requireEqual(r.active, .wechat)
        requireEqual(r.hold(down: false), [.stop(.wechat)])
        requireNil(r.active)
    }
    func testTypelessAndBack() {
        var r = VoiceRouter()
        requireEqual(r.toggle(), [.mode(.typeless)])
        requireEqual(r.hold(down: true), [.start(.typeless)])
        requireEqual(r.hold(down: false), [.stop(.typeless)])
        requireEqual(r.toggle(), [.mode(.wechat)])
    }
    func testRepeatDownDoesNotStopRecording() {
        var r = VoiceRouter()
        _ = r.hold(down: true)
        requireEqual(r.hold(down: true), [])
        requireEqual(r.active, .wechat)
    }
    func testSwitchDuringRecordingWaitsUntilStopAndDoesNotStopWrongEngine() {
        var r = VoiceRouter()
        _ = r.hold(down: true)
        requireEqual(r.toggle(), [.deferred(.typeless)])
        requireEqual(r.active, .wechat)
        requireEqual(r.mode, .wechat)
        requireEqual(r.hold(down: false), [.stop(.wechat), .mode(.typeless)])
        _ = r.hold(down: false)
        requireEqual(r.hold(down: true), [.start(.typeless)])
    }
    func testTwoDeferredTogglesCancelEachOther() {
        var r = VoiceRouter()
        _ = r.hold(down: true)
        _ = r.toggle(); _ = r.toggle()
        requireNil(r.pending)
        requireEqual(r.hold(down: false), [.stop(.wechat)])
    }
    func testRecoveryReleasesOnceAndAllowsNewSession() {
        var r = VoiceRouter()
        _ = r.toggle(); _ = r.hold(down: true)
        requireEqual(r.reset(), [.stop(.typeless)])
        requireEqual(r.reset(), [])
        requireEqual(r.hold(down: true), [.start(.typeless)])
    }
    func testPhysicalFnAndOtherAppsSyntheticEventsAreExcluded() {
        requireFalse(SayAllEventFilter.accepts(marker: 0, sourceIsSayAll: true))
        requireFalse(SayAllEventFilter.accepts(marker: SayAllEventFilter.marker, sourceIsSayAll: false))
        requireTrue(SayAllEventFilter.accepts(marker: SayAllEventFilter.marker, sourceIsSayAll: true))
    }
    func testModeShortcutDoesNotMatchModelOrOrdinaryKeys() {
        requireTrue(SayAllEventFilter.isModeKey(code: 80, flags: 0x1C0000))
        requireFalse(SayAllEventFilter.isModeKey(code: 80, flags: 0x40000))
        requireFalse(SayAllEventFilter.isModeKey(code: 46, flags: 0x60000))
    }
}

let checks = VoiceRouterChecks()
checks.testWechatHoldHasExplicitRelease()
checks.testTypelessAndBack()
checks.testRepeatDownDoesNotStopRecording()
checks.testSwitchDuringRecordingWaitsUntilStopAndDoesNotStopWrongEngine()
checks.testTwoDeferredTogglesCancelEachOther()
checks.testRecoveryReleasesOnceAndAllowsNewSession()
checks.testPhysicalFnAndOtherAppsSyntheticEventsAreExcluded()
checks.testModeShortcutDoesNotMatchModelOrOrdinaryKeys()
print("PASS: 8 routing, isolation and recovery scenarios")
requireEqual(RecoveryAction.forSession(.wechat), .releaseWeChatKey)
requireEqual(RecoveryAction.forSession(.typeless), .cancelTypeless)
requireEqual(RecoveryAction.forSession(nil), .none)
print("PASS: recovery never replays a Typeless toggle chord")
requireFalse(StreamIdleGuard.isSafe(last: .started, age: 90))
requireFalse(StreamIdleGuard.isSafe(last: .stopped, age: 1))
requireFalse(StreamIdleGuard.isSafe(last: nil, age: 90))
requireTrue(StreamIdleGuard.isSafe(last: .stopped, age: 3.1))
requireFalse(StreamIdleGuard.isSafe(last: .boot, age: 0.5))
requireTrue(StreamIdleGuard.isSafe(last: .boot, age: 10))
print("PASS: active, draining, unknown and fresh-launch gates")

var lostPress = VoiceRouter()
requireEqual(lostPress.hold(down: false), []) // orphan release never starts
requireEqual(lostPress.hold(down: true), [.start(.wechat)])
requireEqual(lostPress.hold(down: true), []) // repeated press never stops
requireEqual(lostPress.hold(down: false), [.stop(.wechat)])
requireEqual(lostPress.hold(down: false), []) // repeated release never restarts
requireEqual(lostPress.hold(down: true), [.start(.wechat)])
requireEqual(lostPress.hold(down: false), [.stop(.wechat)])
print("PASS: orphan and repeated edges cannot invert recording")

for cause in RecoveryCause.allCases {
    requireFalse(cause.enabledAfterRecovery(wasEnabled: false))
    requireEqual(cause.enabledAfterRecovery(wasEnabled: true), cause != .userPause)
    requireEqual(cause.resumesInProcess, cause == .sayAllExit || cause == .tapInterrupted)
}
print("PASS: only explicit pause clears enabled intent; transient failures resume, quit preserves preference")
