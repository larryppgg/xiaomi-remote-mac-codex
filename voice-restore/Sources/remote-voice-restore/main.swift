import Foundation
import RemoteVoiceRestoreCore

// MARK: - Argument parsing

struct Options {
    var logPath = Configuration.defaultLogPath
    var statePath = Configuration.defaultStatePath
    var restoreLogPath = Configuration.defaultRestoreLogPath
    var doubaoSourceID = Configuration.defaultDoubaoSourceID
    var wechatSourceID = Configuration.defaultWechatSourceID
    var tool = Configuration.defaultTool
    var intervalMs: UInt64 = 250
    var restoreDelayMs: Double = 3000
    var startFromEnd = true
    var quiet = false
    var printCurrentSource = false
}

func usage() -> Never {
    let text = """
    Usage: remote-voice-restore [options]

    Monitors SayAll's runtime.log and restores WeChat Input Method after a
    Xiaomi Remote 2 Pro speech session (Doubao tool) that leaves Doubao active.

      --log-path PATH          SayAll runtime.log (default: ~/Library/Logs/RemoteMic/runtime.log)
      --state-path PATH        state file for last non-Doubao source (default: ~/Library/Application Support/RemoteVoiceRestore/state.plist)
      --restore-log PATH       observability log (default: ~/Library/Logs/RemoteVoiceRestore/restore.log)
      --doubao-source ID       Doubao input mode ID (default: com.bytedance.inputmethod.doubaoime.pinyin)
      --wechat-source ID       fallback target (default: com.tencent.inputmethod.wetype.pinyin)
      --tool NAME              session tool marker (default: doubao)
      --interval-ms N          log poll interval (default: 250)
      --restore-delay-ms N     delay after release before restoring (default: 3000)
      --no-start-from-end      also process pre-existing log history on start
      --quiet                  do not write observability log
      --print-current-source   print the active input source ID and exit
      --help                   show this help
    """
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
    exit(0)
}

var opts = Options()
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--help", "-h": usage()
    case "--log-path": opts.logPath = args.removeFirst()
    case "--state-path": opts.statePath = args.removeFirst()
    case "--restore-log": opts.restoreLogPath = args.removeFirst()
    case "--doubao-source": opts.doubaoSourceID = args.removeFirst()
    case "--wechat-source": opts.wechatSourceID = args.removeFirst()
    case "--tool": opts.tool = args.removeFirst()
    case "--interval-ms": opts.intervalMs = UInt64(args.removeFirst()) ?? 250
    case "--restore-delay-ms": opts.restoreDelayMs = Double(args.removeFirst()) ?? 400
    case "--no-start-from-end": opts.startFromEnd = false
    case "--quiet": opts.quiet = true
    case "--print-current-source": opts.printCurrentSource = true
    default:
        FileHandle.standardError.write(Data(("unknown option: \(arg)\n").utf8))
        usage()
    }
}

// MARK: - Logging

final class RestoreLogger {
    private let url: URL
    private let lock = NSLock()
    private var file: FileHandle?
    init?(path: String) {
        self.url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            self.file = try FileHandle(forWritingTo: url)
            _ = try? self.file?.seekToEnd()
        } catch {
            return nil
        }
    }
    func log(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let file = file else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(ts) \(line)\n".utf8)
        file.write(data)
        try? file.synchronize()
    }
    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? file?.close()
        file = nil
    }
}

let logger: RestoreLogger? = opts.quiet ? nil : RestoreLogger(path: opts.restoreLogPath)
if !opts.quiet && logger == nil {
    FileHandle.standardError.write(Data("warning: could not open restore log at \(opts.restoreLogPath)\n".utf8))
}

// MARK: - Components

let input = TISInputSourceController()
if opts.printCurrentSource {
    let id = input.currentSourceID() ?? "nil"
    FileHandle.standardOutput.write(Data((id + "\n").utf8))
    exit(id == "nil" ? 1 : 0)
}
let stateStore = StateStore(url: URL(fileURLWithPath: opts.statePath))
// The delayed restore must run on a dedicated queue: this executable's main
// thread lives in a tight poll/sleep loop and never drains DispatchQueue.main,
// so a main-queue asyncAfter would silently never fire.
let restoreQueue = DispatchQueue(label: "dev.xiaomi-remote-codex.voice-restore.restore")
let orchestrator = Orchestrator(
    input: input,
    stateStore: stateStore,
    doubaoSourceID: opts.doubaoSourceID,
    fallbackTarget: opts.wechatSourceID,
    tool: opts.tool,
    restoreDelay: opts.restoreDelayMs / 1000.0,
    queue: restoreQueue
)
orchestrator.onAction = { line in
    logger?.log(line)
}

let reader = LogReader(path: opts.logPath, startFromEnd: opts.startFromEnd)

// MARK: - Signal handling (graceful stop for launchctl stop)
//
// A real C-style handler is required: the main thread lives in a tight
// poll/sleep loop and never drains the main queue, so a DispatchSource-based
// handler would never run and SIGTERM would be ignored (launchctl kill would
// hang). The plain handler below interrupts the sleep and sets the flag the
// main loop checks, so `launchctl kill` and Ctrl-C stop the helper cleanly.

var stopRequested: sig_atomic_t = 0
func onStopSignal(_ sig: Int32) {
    stopRequested = 1
}
signal(SIGTERM, onStopSignal)
signal(SIGINT, onStopSignal)

// MARK: - Main loop

logger?.log("started log=\(opts.logPath) tool=\(opts.tool) doubao=\(opts.doubaoSourceID) wechat=\(opts.wechatSourceID) delayMs=\(opts.restoreDelayMs)")

var pollCount: UInt64 = 0
while stopRequested == 0 {
    autoreleasepool {
        do {
            let lines = try reader.poll()
            for line in lines {
                _ = orchestrator.process(line: line)
            }
        } catch {
            logger?.log("error reading log: \(error)")
        }
    }
    pollCount += 1
    if pollCount >= 60 {
        pollCount = 0
        if !opts.quiet && reader.isOpen {
            logger?.log("heartbeat current=\(input.currentSourceID() ?? "nil") pending=\(orchestrator.isPending)")
        }
    }
    Thread.sleep(forTimeInterval: TimeInterval(opts.intervalMs) / 1000.0)
}

logger?.log("stopped")
logger?.close()
exit(0)
