import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import VoiceSwitchCore

private let ownMarker: Int64 = 0x5256_5357

final class Switcher: NSObject, NSApplicationDelegate {
    var router = VoiceRouter()
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var status: NSStatusItem!
    var window: NSWindow!
    var label: NSTextField!
    var button: NSButton!
    var hud: NSPanel?
    var hudGeneration = 0
    var heartbeat: Timer?
    var modeKeyHeld = false
    var armed = false
    var startupPending = false
    var quitting = false
    var logHandle: FileHandle?
    var terminationSources: [DispatchSourceSignal] = []
    var commandChordHeld = false
    var commandChordGeneration = 0
    var wechatChordHeld = false
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for code in [SIGTERM, SIGINT] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            terminationSources.append(source)
        }
        openLog()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "切换微信 / Typeless", action: #selector(toggleMode), keyEquivalent: "")
        menu.addItem(withTitle: "设置与状态…", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出切换器", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }
        status.menu = menu
        makeWindow()
        startupPending = defaults.bool(forKey: "enabled")
        if startupPending, sayAllQuiet(), installTap() {
            startupPending = false
            armed = true
            log("enabled default=wechat")
        }
        refresh()
        if !armed { showWindow() }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.startupPending, self.sayAllQuiet(), self.installTap() {
                self.startupPending = false
                self.router = VoiceRouter()
                self.armed = true
                self.log("enabled default=wechat source=deferred_startup")
                self.window.orderOut(nil)
                self.refresh()
            }
            if self.router.active != nil,
               NSRunningApplication.runningApplications(withBundleIdentifier: "com.hd838a.RemoteMic").isEmpty {
                self.recover(reason: "sayall_exit")
            }
            if self.quitting, self.sayAllQuiet() { NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }

    func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 370),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "遥控器语音切换"
        window.isReleasedWhenClosed = false
        window.center()
        let content = NSView(frame: window.contentView!.bounds)
        window.contentView = content
        let heading = NSTextField(labelWithString: "微信 / Typeless 遥控器语音")
        heading.font = .boldSystemFont(ofSize: 23)
        heading.frame = NSRect(x: 28, y: 312, width: 504, height: 32)
        content.addSubview(heading)
        label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 17)
        label.frame = NSRect(x: 28, y: 244, width: 504, height: 56)
        content.addSubview(label)
        let guide = NSTextField(wrappingLabelWithString:
            "默认使用微信语音。双击 TV 切换，按住语音键说话，松开结束。\n\n" +
            "微信：Control + Shift + 空格 按住说话。Typeless：只绑定左 Command + 右 Command。\n" +
            "SayAll：保留 Fn 点按兼容；两端麦克风均为 MiRemoteV 2ch。")
        guide.font = .systemFont(ofSize: 14)
        guide.frame = NSRect(x: 28, y: 103, width: 504, height: 136)
        content.addSubview(guide)
        button = NSButton(title: "启用双语音", target: self, action: #selector(toggleEnabled))
        button.frame = NSRect(x: 28, y: 47, width: 150, height: 38)
        content.addSubview(button)
        let permissions = NSButton(title: "辅助功能设置…", target: self, action: #selector(openPermissions))
        permissions.frame = NSRect(x: 190, y: 47, width: 160, height: 38)
        content.addSubview(permissions)
        let modeButton = NSButton(title: "切换语音模式", target: self, action: #selector(toggleMode))
        modeButton.frame = NSRect(x: 362, y: 47, width: 164, height: 38)
        content.addSubview(modeButton)
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleEnabled() {
        startupPending = false
        if armed {
            recover(reason: "user_pause")
        } else {
            guard AXIsProcessTrusted() else {
                toast("请先在辅助功能中允许“遥控器语音切换”")
                refresh(); return
            }
            guard installTap() else {
                toast("事件接收未就绪，请检查辅助功能 / 输入监控权限")
                refresh(); return
            }
            guard sayAllQuiet() else {
                toast("请松开语音键，等 3 秒后再启用")
                log("enable_deferred reason=voice_not_quiet")
                return
            }
            router = VoiceRouter()
            modeKeyHeld = false
            armed = true
            defaults.set(true, forKey: "enabled")
            log("enabled default=wechat")
            toast("已启用 · 微信语音")
        }
        refresh()
    }

    @objc func toggleMode() {
        guard armed else { toast("请先启用双语音"); return }
        perform(router.toggle())
    }

    func installTap() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<Switcher>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log("tap_create_failed"); return false
        }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log("tap_ready")
        return true
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                self.recover(reason: "tap_interrupted")
                if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker == SayAllEventFilter.marker else { return Unmanaged.passUnretained(event) }
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.hd838a.RemoteMic"
        else { return Unmanaged.passUnretained(event) }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 63 {
            // Once installed, a paused router consumes verified remote tails.
            // A delayed stop pulse must not reach WeChat as a fresh Fn press.
            guard armed else { return nil }
            let down = type == .keyDown || (type == .flagsChanged && event.flags.contains(.maskSecondaryFn))
            perform(router.pulse(down: down))
            return nil
        }
        if SayAllEventFilter.isModeKey(code: code, flags: event.flags.rawValue) {
            guard armed else { return nil }
            if type == .keyDown, !modeKeyHeld {
                modeKeyHeld = true
                perform(router.toggle())
            } else if type == .keyUp { modeKeyHeld = false }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// Uses only SayAll stream metadata; neither voice text nor other app data
    /// is parsed, saved or logged. Allow 3 s for its bounded audio drain/tap.
    func sayAllQuiet() -> Bool {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.hd838a.RemoteMic").first
        else { return true }
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/RemoteMic/runtime.log")
        guard let reader = try? FileHandle(forReadingFrom: path) else { return false }
        defer { try? reader.close() }
        guard let end = try? reader.seekToEnd() else { return false }
        try? reader.seek(toOffset: end > 65_536 ? end - 65_536 : 0)
        guard let data = try? reader.readToEnd() else { return false }
        let text = String(decoding: data, as: UTF8.self)
        let pidTag = "pid=\(application.processIdentifier) "
        for line in text.split(separator: "\n").reversed() where line.contains(pidTag) {
            if line.contains("ATVV STREAM START session=") { return false }
            if line.contains("ATVV STREAM STOP session=") || line.contains("APP START version=") {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let timestamp = line.split(separator: " ").first,
                      let stop = formatter.date(from: String(timestamp)) else { return false }
                return StreamIdleGuard.isSafe(last: line.contains("APP START") ? .boot : .stopped,
                                              age: Date().timeIntervalSince(stop))
            }
        }
        return false // unknown is not a safe start condition
    }

    func recover(reason: String) {
        startupPending = false
        releaseCommandChord()
        let action = RecoveryAction.forSession(router.active)
        _ = router.reset()
        modeKeyHeld = false
        armed = false
        defaults.set(false, forKey: "enabled")
        switch action {
        case .releaseWeChatKey: releaseWeChatChord()
        case .cancelTypeless:
            // Escape cancels; unlike a toggle chord, it cannot start recording.
            if !NSRunningApplication.runningApplications(withBundleIdentifier: "now.typeless.desktop").isEmpty {
                post(code: 53, down: true, flags: [])
                post(code: 53, down: false, flags: [])
            }
        case .none: break
        }
        log("recovery reason=\(reason) action=\(action) text_result=unknown")
        toast("语音切换已暂停；松开语音键后可重新启用")
        refresh()
    }

    func perform(_ effects: [RouteEffect]) {
        for effect in effects {
            switch effect {
            case let .start(mode):
                if mode == .wechat {
                    pressWeChatChord()
                } else {
                    commandPairTap()
                }
                log("trigger_start mode=\(mode.rawValue) result=posted text_result=unknown")
            case let .stop(mode):
                if mode == .wechat {
                    releaseWeChatChord()
                } else {
                    commandPairTap()
                }
                log("trigger_stop mode=\(mode.rawValue) result=posted text_result=unknown")
            case let .mode(mode):
                log("mode_changed mode=\(mode.rawValue)")
                toast("已切换 · \(mode == .wechat ? "微信语音" : "Typeless")")
            case let .deferred(mode):
                log("mode_deferred mode=\(mode.rawValue)")
                toast("录音结束后 · \(mode == .wechat ? "微信语音" : "Typeless")")
            }
        }
        if !effects.isEmpty { DispatchQueue.main.async { self.refresh() } }
    }

    /// Match WeChat's recorded left Control + left Shift + Space chord,
    /// including physical modifier transitions rather than Space flags alone.
    func pressWeChatChord() {
        guard !wechatChordHeld else { return }
        wechatChordHeld = true
        post(code: 59, down: true, flags: CGEventFlags(rawValue: 0x40001))
        post(code: 56, down: true, flags: CGEventFlags(rawValue: 0x60003))
        post(code: 49, down: true, flags: CGEventFlags(rawValue: 0x60003))
    }

    func releaseWeChatChord() {
        guard wechatChordHeld else { return }
        wechatChordHeld = false
        post(code: 49, down: false, flags: CGEventFlags(rawValue: 0x60003))
        post(code: 56, down: false, flags: CGEventFlags(rawValue: 0x40001))
        post(code: 59, down: false, flags: [])
    }

    /// Typeless's visible setting is a standalone Left Cmd + Right Cmd chord.
    /// Include the device-side modifier bits so left/right remain distinct.
    func commandPairTap() {
        releaseCommandChord()
        let left: UInt64 = 0x8
        let right: UInt64 = 0x10
        post(code: 55, down: true, flags: CGEventFlags(rawValue: 0x100000 | left))
        post(code: 54, down: true, flags: CGEventFlags(rawValue: 0x100000 | left | right))
        commandChordHeld = true
        let generation = commandChordGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if self.commandChordGeneration == generation { self.releaseCommandChord() }
        }
    }

    func releaseCommandChord() {
        commandChordGeneration += 1
        guard commandChordHeld else { return }
        commandChordHeld = false
        post(code: 54, down: false, flags: CGEventFlags(rawValue: 0x100000 | 0x8))
        post(code: 55, down: false, flags: [])
    }

    func post(code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            log("event_create_failed"); return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: ownMarker)
        event.post(tap: .cghidEventTap)
    }

    func refresh() {
        let mode = router.mode == .wechat ? "微信" : "Typeless"
        status.button?.title = armed ? "语音：\(mode)" : "语音：未启用"
        label.stringValue = armed ? "当前：\(mode)语音\n\(router.active == nil ? "双击 TV 切换；按住语音说话" : "语音会话进行中")" :
            "尚未启用\n先完成两端快捷键配置和辅助功能授权"
        button.title = armed ? "暂停双语音" : "启用双语音"
    }

    func toast(_ message: String) {
        DispatchQueue.main.async {
            self.hudGeneration += 1
            let generation = self.hudGeneration
            self.hud?.orderOut(nil)
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 70),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            panel.level = .floating
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let text = NSTextField(labelWithString: message)
            text.alignment = .center
            text.font = .systemFont(ofSize: 20, weight: .semibold)
            text.frame = NSRect(x: 10, y: 20, width: 460, height: 30)
            panel.contentView?.addSubview(text)
            if let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 240, y: screen.visibleFrame.maxY - 110))
            }
            self.hud = panel
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.hudGeneration == generation { self.hud?.orderOut(nil) }
            }
        }
    }

    func openLog() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/RemoteVoiceSwitcher")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("switcher.log")
        // Bounded diagnostic log, containing only our modes and lifecycle.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 500_000 {
            try? Data().write(to: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        logHandle = try? FileHandle(forWritingTo: url)
        _ = try? logHandle?.seekToEnd()
    }
    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        try? logHandle?.write(contentsOf: Data(line.utf8))
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if router.active != nil { recover(reason: "quit") }
        if tap != nil, !sayAllQuiet() {
            quitting = true
            armed = false
            toast("请松开语音键；本段结束后退出切换器")
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        if router.active != nil { recover(reason: "exit") }
        releaseCommandChord()
        releaseWeChatChord()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        log("exit keys_released=true")
        try? logHandle?.close()
    }
}

let application = NSApplication.shared
let delegate = Switcher()
application.delegate = delegate
application.run()
