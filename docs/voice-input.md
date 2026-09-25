# 微信键盘输入＋豆包遥控器语音

目标：日常键盘使用微信输入法；按住遥控器语音键时由豆包识别；松开并上屏后再切回微信。语音键本身由 SayAll 处理，不写进普通按键预设。

## 设置顺序

1. 安装[SayAll](https://github.com/HD838A/remote-mic-app/releases)、豆包输入法和微信输入法。先按 SayAll 的首次使用向导配对遥控器，确认连接页显示已连接。
2. 使用 SayAll 安装包自带的兼容麦克风，或按上游说明选一个兼容的虚拟音频设备。在 SayAll“连接”页将语音输出选到该设备；在豆包的语音设置中选同一个麦克风。
3. 在 SayAll“按键”页把语音触发键选为 `Fn/地球键`。让豆包的全局语音快捷键响应 Fn；关闭微信输入法对同一 Fn 语音快捷键的占用。普通键盘输入源先切为微信。
4. 先测试一次短句：Codex 输入框中按住遥控器语音键说话，松开后确认文字真正留在输入框。若豆包没有识别，先检查麦克风输入与 Fn 快捷键，不要安装恢复程序掩盖前段故障。
5. 若松开后键盘留在豆包，在仓库根目录执行：

   ```bash
   cd voice-restore
   ./install.sh
   ./status.sh
   ```

   这个用户级辅助程序读取 SayAll 的遥控器语音开始／停止事件，默认在停止 **3 秒后**、且当前输入源仍是豆包时恢复到语音前的输入源（通常是微信）。它不读取语音内容。`./uninstall.sh` 可移除程序和 LaunchAgent；不带 `--purge` 时保留本机状态与日志。

6. 用一段约 15–20 秒的实际语音验证：松开后等识别文字上的临时下划线消失，确认文字仍留在 Codex 输入框；再打一个字，确认键盘输入源为微信。若文字消失，先检查 `~/Library/Logs/RemoteVoiceRestore/restore.log` 的恢复时间，必要时用 `--restore-delay-ms` 增大等待时间并重新加载辅助程序。

## 可调延迟

`voice-restore/Sources/remote-voice-restore/main.swift` 的默认值为 3000 毫秒。也可以给 LaunchAgent 的 `ProgramArguments` 添加 `--restore-delay-ms` 和所需毫秒数，然后重新加载。更长的等待有利于长句上屏，但键盘切回微信也更晚；请用真实长句选择适合本机的值。

不要发布 `~/Library/Logs/RemoteMic/runtime.log`、`~/Library/Logs/RemoteVoiceRestore/restore.log` 或任何本机输入法状态文件。报告问题时只说明语音是否留下、恢复时间和输入源结果即可。
