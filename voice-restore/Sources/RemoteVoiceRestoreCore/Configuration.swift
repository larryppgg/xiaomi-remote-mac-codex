import Foundation

/// Static, user-level defaults for the remote voice restore helper.
///
/// No voice content or credentials are ever written here — only input source IDs.
public enum Configuration {
    /// SayAll 1.9.21 writes remote-voice activity here.
    public static let defaultLogPath =
        NSString(string: "~/Library/Logs/RemoteMic/runtime.log").expandingTildeInPath

    /// Doubao global voice leaves this input mode active after remote speech.
    public static let defaultDoubaoSourceID = "com.bytedance.inputmethod.doubaoime.pinyin"

    /// WeChat (WeType) pinyin — the daily keyboard input method we restore to.
    public static let defaultWechatSourceID = "com.tencent.inputmethod.wetype.pinyin"

    /// Persisted last-known non-Doubao source (an input source ID, nothing sensitive).
    public static let defaultStatePath =
        NSString(string: "~/Library/Application Support/RemoteVoiceRestore/state.plist").expandingTildeInPath

    /// Restore log used only for observability ("可查看"). Contains no voice content.
    public static let defaultRestoreLogPath =
        NSString(string: "~/Library/Logs/RemoteVoiceRestore/restore.log").expandingTildeInPath

    /// Kept for compatible CLI arguments; remote stream events are physical.
    public static let defaultTool = "doubao"
}
