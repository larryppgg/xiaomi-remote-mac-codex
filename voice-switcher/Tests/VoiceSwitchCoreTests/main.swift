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
    func testWechatHoldSpansBothPulses() {
        var r = VoiceRouter()
        requireEqual(r.pulse(down: true), [.start(.wechat)])
        requireEqual(r.pulse(down: false), [])
        requireEqual(r.active, .wechat)
        requireEqual(r.pulse(down: true), [.stop(.wechat)])
        requireNil(r.active)
    }
    func testTypelessAndBack() {
        var r = VoiceRouter()
        requireEqual(r.toggle(), [.mode(.typeless)])
        requireEqual(r.pulse(down: true), [.start(.typeless)])
        _ = r.pulse(down: false)
        requireEqual(r.pulse(down: true), [.stop(.typeless)])
        requireEqual(r.toggle(), [.mode(.wechat)])
    }
    func testRepeatDownDoesNotStopRecording() {
        var r = VoiceRouter()
        _ = r.pulse(down: true)
        requireEqual(r.pulse(down: true), [])
        requireEqual(r.active, .wechat)
    }
    func testSwitchDuringRecordingWaitsUntilStopAndDoesNotStopWrongEngine() {
        var r = VoiceRouter()
        _ = r.pulse(down: true); _ = r.pulse(down: false)
        requireEqual(r.toggle(), [.deferred(.typeless)])
        requireEqual(r.active, .wechat)
        requireEqual(r.mode, .wechat)
        requireEqual(r.pulse(down: true), [.stop(.wechat), .mode(.typeless)])
        _ = r.pulse(down: false)
        requireEqual(r.pulse(down: true), [.start(.typeless)])
    }
    func testTwoDeferredTogglesCancelEachOther() {
        var r = VoiceRouter()
        _ = r.pulse(down: true); _ = r.pulse(down: false)
        _ = r.toggle(); _ = r.toggle()
        requireNil(r.pending)
        requireEqual(r.pulse(down: true), [.stop(.wechat)])
    }
    func testRecoveryReleasesOnceAndAllowsNewSession() {
        var r = VoiceRouter()
        _ = r.toggle(); _ = r.pulse(down: true)
        requireEqual(r.reset(), [.stop(.typeless)])
        requireEqual(r.reset(), [])
        requireEqual(r.pulse(down: true), [.start(.typeless)])
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
checks.testWechatHoldSpansBothPulses()
checks.testTypelessAndBack()
checks.testRepeatDownDoesNotStopRecording()
checks.testSwitchDuringRecordingWaitsUntilStopAndDoesNotStopWrongEngine()
checks.testTwoDeferredTogglesCancelEachOther()
checks.testRecoveryReleasesOnceAndAllowsNewSession()
checks.testPhysicalFnAndOtherAppsSyntheticEventsAreExcluded()
checks.testModeShortcutDoesNotMatchModelOrOrdinaryKeys()
print("PASS: 8 routing, isolation and recovery scenarios")
requireEqual(RecoveryAction.forSession(.wechat), .releaseFn)
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
