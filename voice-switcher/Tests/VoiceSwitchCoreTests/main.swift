import Foundation
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

var modeLatch = ModeKeyLatch()
requireEqual(modeLatch.handle(code: 80, flags: 0, down: true, up: false), .pass)
requireEqual(modeLatch.handle(code: 80, flags: 0x1C0000, down: true, up: false), .toggle)
requireEqual(modeLatch.handle(code: 80, flags: 0x1C0000, down: true, up: false), .consume)
requireEqual(modeLatch.handle(code: 80, flags: 0, down: false, up: true), .consume)
requireEqual(modeLatch.handle(code: 80, flags: 0x1C0000, down: true, up: false), .toggle)
requireEqual(modeLatch.handle(code: 79, flags: 0, down: false, up: true), .pass)
requireEqual(modeLatch.handle(code: 80, flags: 0, down: false, up: true), .consume)
requireEqual(modeLatch.handle(code: 80, flags: 0, down: false, up: true), .pass)
print("PASS: mode shortcut releases without modifiers and ignores repeated down")

requireTrue(VoiceRecoveryGate.resumesIdleTap(armed: true, active: false, keysHeld: false, quitting: false))
requireFalse(VoiceRecoveryGate.resumesIdleTap(armed: true, active: true, keysHeld: false, quitting: false))
requireFalse(VoiceRecoveryGate.resumesIdleTap(armed: true, active: false, keysHeld: true, quitting: false))
requireFalse(VoiceRecoveryGate.resumesIdleTap(armed: false, active: false, keysHeld: false, quitting: false))
requireFalse(VoiceRecoveryGate.resumesIdleTap(armed: true, active: false, keysHeld: false, quitting: true))
requireTrue(VoiceRecoveryGate.acceptsFreshPress(pending: true, down: true, repeating: false, quitting: false))
requireFalse(VoiceRecoveryGate.acceptsFreshPress(pending: false, down: true, repeating: false, quitting: false))
requireFalse(VoiceRecoveryGate.acceptsFreshPress(pending: true, down: false, repeating: false, quitting: false))
requireFalse(VoiceRecoveryGate.acceptsFreshPress(pending: true, down: true, repeating: true, quitting: false))
requireFalse(VoiceRecoveryGate.acceptsFreshPress(pending: true, down: true, repeating: false, quitting: true))
for mode in [VoiceMode.wechat, .typeless] {
    var rapid = VoiceRouter()
    if mode == .typeless { _ = rapid.toggle() }
    for _ in 0..<20 {
        requireEqual(rapid.hold(down: true), [.start(mode)])
        requireEqual(rapid.hold(down: false), [.stop(mode)])
    }
}
print("PASS: idle tap resumes immediately; fresh press bypasses recovery wait; rapid consecutive sessions do not need cooldown")

requireFalse(VoiceRecoveryGate.acceptsFreshPress(pending: true, down: true, repeating: false, quitting: false, cleaningUp: true))
print("PASS: queued cleanup blocks fresh starts until cleanup completes")

// Real filesystem notifications: no keyboard/voice injection is used here.
let edgeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: edgeDirectory, withIntermediateDirectories: true)
let edgeURL = edgeDirectory.appendingPathComponent("runtime.log")
let edgePrefix = "2026-10-18T01:00:00.000Z pid=123 ver=1.9.21 build=174 VOICE KEY mode=left_command "
try Data((edgePrefix + "DOWN\n").utf8).write(to: edgeURL)
var observedEdges: [SayAllVoiceEdge] = []
let edgeReader = VoiceEdgeReader(url: edgeURL) { observedEdges.append($0) }
requireTrue(edgeReader.start())
func settleEdges() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
func appendEdges(_ text: String, to url: URL = edgeURL) throws {
    let h = try FileHandle(forWritingTo: url)
    try h.seekToEnd()
    try h.write(contentsOf: Data(text.utf8))
    try h.close()
}
settleEdges()
requireEqual(observedEdges.count, 0) // No historical replay.
try appendEdges(edgePrefix + "DO")
settleEdges()
requireEqual(observedEdges.count, 0)
try appendEdges("WN\n" + edgePrefix + "UP\n")
settleEdges()
requireEqual(observedEdges.map { $0.down }, [true, false])
try appendEdges("unrelated text\n" + String(repeating: "a", count: 2000) + "\n")
settleEdges()
requireEqual(observedEdges.count, 2)
// More than one read budget followed by rename must preserve the old UP tail.
try appendEdges(String(repeating: "ignored\n", count: 40000) + edgePrefix + "UP\n")
try FileManager.default.moveItem(at: edgeURL, to: edgeDirectory.appendingPathComponent("runtime.1.log"))
try Data((edgePrefix + "DOWN\n" + edgePrefix + "UP\n").utf8).write(to: edgeURL)
settleEdges()
requireEqual(observedEdges.map { $0.down }, [true, false, false, true, false])
edgeReader.stop()
requireTrue(edgeReader.start())
settleEdges()
requireEqual(observedEdges.count, 5) // Restart also skips history.
try appendEdges(edgePrefix + "DOWN\n" + edgePrefix + "UP\n")
settleEdges()
requireEqual(observedEdges.map { $0.down }, [true, false, false, true, false, true, false])
edgeReader.stop()
try FileManager.default.removeItem(at: edgeDirectory)
print("PASS: filesystem voice edges preserve fragments, ordered rotation tails, and skip startup history")
