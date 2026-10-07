# 微信与 Typeless 双语音模式

此方案是本仓库的可选扩展，不是 SayAll 原生功能。它保持 SayAll 1.9.21 的 Fn 点按兼容和音频传输，由本仓库的「遥控器语音切换」组件转换触发事件。

## 使用

- 切换器每次启动默认微信语音。按住语音键说话，松开结束。
- 双击 TV：切到 Typeless；再次双击 TV：切回微信。菜单栏和短暂浮层显示当前模式，不抢输入框焦点。
- 录音中双击 TV：在当前录音结束后切换，结束事件仍送给原来的工具。
- 主页长按：打开 Codex 并用其原生 Option+L 回到输入框。TV 短按仍切换应用。
- 普通键盘仍用微信输入法。TV 长按选 Codex 模型；电源长按 Shift-Tab 向前移动焦点。

## Agent 安装与配置

1. 确认标准方案已经工作，读取根目录 `AGENTS.md`。从仓库构建组件，不需要获取或重编译 SayAll 的源码：

   ```bash
   cd voice-switcher
   swift run VoiceSwitchChecks
   ./build.sh
   ```

   需要 macOS 13+ 和 Swift 5.9+。测试程序只使用 Swift 标准库，不依赖 Xcode 的 XCTest。
2. 将生成的 `dist/遥控器语音切换.app` 复制到用户的 `~/Applications/`。用桌面操作工具打开应用。新应用先保持未启用；权限不足时不得声称已接管遥控器。
3. 经用户对新组件授权后，在系统设置的辅助功能中加入并允许「遥控器语音切换」。系统若另外要求输入监控，同样由用户授权。该系统权限涉及键盘事件；组件在代码中只接受 SayAll 的 Bundle ID、注入标记及指定键码，其他事件原样通过。不记录普通键盘、音频、输入文字、账户或第三方应用历史。
4. Typeless 设置：Dictate 只绑定 **左 Command + 右 Command**，移除 Fn，防止它与微信同时识别。麦克风选择 `MiRemoteV 2ch`。不要只依据向导推荐文字判断快捷键已保存，必须读取实际设置界面。
5. 微信输入法设置 → 语音输入：启用「按住说话」，快捷键为 **Control + Shift + 空格**，移除原来的 Fn 绑定；麦克风选择 `MiRemoteV 2ch`。普通键盘输入源保留微信。设置程序在微信输入法安装包中的 `WeTypeSettings.app`。
6. SayAll：保留语音触发键 Fn 和「语音键模拟 Fn 点按」。退出 SayAll 后应用可选预设：

   ```bash
   python3 preset/apply.py --preset keymap-dual-voice.json
   python3 preset/apply.py --preset keymap-dual-voice.json --apply
   ```

7. 重新启动 SayAll，读回主页长按为「Codex · 输入框」（键盘快捷键聚焦 Option+L）、TV 短按为 Command+Tab、TV 双击为 `Control+Option+Command+F19`、TV 长按为模型快捷键、电源长按为 Shift-Tab。在切换器中点击「启用双语音」，然后关闭或隐藏设置窗口，保持目标输入框在前台。
8. 执行下方实测，完成前保留原配置备份。验证成功后，在语音键已松开且组件空闲时退出组件，运行 `python3 voice-switcher/install-login.py` 检查，再运行 `python3 voice-switcher/install-login.py --apply` 注册登录启动。新启动默认微信，不恢复上次 Typeless 模式；若 SayAll 尚未就绪，组件等待其安静至少 3 秒后启用。

## 必须实测的场景

| 场景 | 预期 / 失败判定 |
| --- | --- |
| 初次启动与权限缺失 | 无权限时显示未启用，不声称已接管；权限具备后可启用 |
| 默认微信 | 按住语音，微信浮窗出现；松开后文字留下；Typeless 不启动 |
| TV 双击到 Typeless | 浮层、菜单栏变为 Typeless；按住语音只出现 Typeless，松开结束并提交文字 |
| 切回微信 | 同一 TV 双击恢复微信，再次语音正常，不需要重启 SayAll |
| 连续两段 | 微信与 Typeless 分别完成两段，不能第二次变成反向启动或保持录音 |
| 录音中切换 | 当前工具继续录音并完成；下一段才使用新模式 |
| 真键盘 Fn | 不经过切换器改写；保持系统自己的 Fn 行为，不触发微信或 Typeless |
| 主页长按 | 从其他焦点打开 Codex 并聚焦输入框，可直接输入；不执行 Escape 或停止当前任务 |
| 普通遥控器 | 四方向、连续删除、默认发送与长按引导、播放暂停保持原配置 |
| SayAll 中途退出 | 切换器释放自己持有的微信快捷键；不得留下修饰键按下状态 |
| Typeless 长句 | 超过一分钟实际说话，完整上屏；字数额度、网络及官方单次时长限制仍生效 |

单元场景只证明路由与事件隔离，构建和签名只证明程序能生成。日志中的 `posted` 表示触发事件已提交，**不表示第三方识别或最终文字成功**。第三方工具提前取消、手动通过另一快捷键结束或达到自身限制的行为需要单独实测；测试期间先松开遥控器语音键，再使用工具自己的取消操作。

## 本机诊断与回退

组件日志仅含模式和生命周期，保存在本机 `~/Library/Logs/RemoteVoiceSwitcher/switcher.log`，不要上传。没有用户语音或输入内容。

回退顺序：先松开语音键；暂停并退出切换器；关闭微信 Control+Shift+空格 按住说话；Typeless 恢复 Fn 并删除左/右 Command 组合；退出 SayAll，用本机备份恢复或应用标准 `keymap.json`，再启动 SayAll。移除登录启动项：`launchctl bootout gui/$(id -u)/io.github.remote-voice-switcher`，再将 `~/Library/LaunchAgents/io.github.remote-voice-switcher.plist` 移到废纸篓。只卸载本组件，不删除微信、Typeless、SayAll 或任何聊天历史。

## 当前验收

- 路由、按下重复、录音中切换、恢复与来源隔离：8 个自动化场景通过。
- 2026-10-04：组件构建和签名验证通过；辅助功能已允许，事件接口已启用；当时微信 Fn 按住说话、Typeless 左右 Command 组合、同一麦克风以及 SayAll 双语音预设已从界面读回。
- 2026-10-04：用户确认微信与 Typeless 两种模式均成功识别并留下文字；运行记录对应两种模式各两次开始和结束。登录服务启动后已读回运行状态、事件接口和默认微信模式。
- 2026-10-07：微信改为左 Control+左 Shift+空格，组件发送完整修饰键按下/松开序列；用户确认微信、Typeless 均能识别并留下文字，运行记录包含两模式启停。主页长按打开 Codex 并聚焦输入框也通过实体确认。配置脚本 4 项测试、路由/恢复检查、构建及严格签名通过。
- 录音中切换、双模式下超过一分钟的长句和异常恢复仍需实体测试，自动化恢复场景不能替代真机结果。

Typeless 的点按启停与快捷键设置依据[官方听写说明](https://www.typeless.com/help/quickstart/dictate)和[官方设置说明](https://www.typeless.com/help/quickstart/settings)。

## 避免 Fn 被输入法先拦截

微信按住说话使用独立的 Control+Shift+空格，Typeless 使用左右 Command；两者都不绑定 Fn。SayAll 仍输出带其标记的 Fn，切换器将它转换为当前工具的独立快捷键。不依赖接口顺序轮询，也不增加后台服务。普通键盘 Fn 不再作为微信语音快捷键。

构建目录受云盘占位文件影响时，可将编译缓存与产物放在本机缓存目录：

```bash
REMOTE_VOICE_BUILD_DIR="$HOME/Library/Caches/RemoteVoiceSwitcherBuild" \
REMOTE_VOICE_APP_DIR="$HOME/Library/Caches/RemoteVoiceSwitcherBuild/遥控器语音切换.app" \
voice-switcher/build.sh
```

使用该参数时，应复制命令最后输出的 `.app` 路径，替代默认 `dist` 路径。
