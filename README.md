# 小米遥控器 2 Pro 控制 Mac 与 Codex

一套可复用的 [SayAll（无线麦）](https://github.com/HD838A/remote-mic-app) 按键方案：用小米蓝牙遥控器 2 Pro 控制 Mac、Chrome 和 Codex；按住语音键用 Typeless 识别，平时键盘保留微信输入法。

本仓库提供 **按键预设和安装说明**，并保留旧豆包方案的可选恢复程序。SayAll、Typeless、微信输入法和 Codex 均需从各自官方渠道安装；本仓库不包含它们的二进制文件，也不是 SayAll 的 fork。上游 SayAll 项目及许可见[其仓库](https://github.com/HD838A/remote-mic-app)。

![小米遥控器 2 Pro 按键速查图](assets/remote-keymap-zh.png)

[下载原尺寸按键速查图](assets/remote-keymap-zh.png)

## 先看效果

| 遥控器 | 单击 | 双击 | 长按 |
| --- | --- | --- | --- |
| 语音 | 按住说话，松开结束；Typeless 识别 | — | — |
| 方向左／右 | 标准方向键 `← / →` | 保留连续单击，不另设动作 | 保持对应方向，按住连续移动 |
| 方向上／下 | 标准方向键 `↑ / ↓` | 保留连续单击 | 保持对应方向，按住连续移动 |
| 确定 | 回车；Codex 运行时按其默认设置排队 | 全选 | `⌘Return`，引导当前回复 * |
| 返回 | 删除前一个字符，可连续按 | 保留连续删除 | 删除前一个词 |
| 主页 | `⌘K`，Codex 命令／会话查找 | 打开 Chrome | 打开 Codex |
| 菜单 | `Tab`，下一个控件 | 复制 | 粘贴 |
| 电源 | `Esc`，取消／关闭弹窗 | 播放／暂停 | 关闭当前窗口或标签 |
| TV | 切换 App | `⌃⇧M`，Codex 模型选择器 * | `⇧Tab`，上一个控件 |
| 音量＋／－ | 页面向上／向下滚动 | 撤销／重做 | 上一个／下一个最近会话；Chrome 前后标签 * |

四方向的长按不设置独立动作，从而保留按住重复。音量长按发送 `Ctrl+Shift+Tab / Ctrl+Tab`，在当前核对的 Codex 版本中选择最近会话，在 Chrome 中切换标签；不是按侧边栏项目排序遍历。

完整设计和适用范围见[按键说明](docs/keymap.md)。`*` 表示依赖 Codex 版本与焦点状态；确定键长按的“引导”已在这台 Mac 上的**回复进行中、输入框聚焦**场景通过实体按键测试。当前核对的 Codex 桌面版默认“回车发送”时，会在回复中把 `⌘Return` 解释为与默认排队相反的“引导”；在空闲时，同一个键只会正常发送一条新消息。

## 可选：微信与 Typeless 双语音

默认按住语音用微信，双击 TV 切换到 Typeless，再双击切回；普通打字保持微信。此扩展需要本仓库的原生切换组件，安装与实体测试步骤见[双语音设置](docs/dual-voice.md)。标准预设继续使用上方映射；双语音预设把 TV 长按改为模型选择、电源长按改为 Shift-Tab。

[双语音按键速查图](assets/remote-keymap-dual-voice-zh.png)

## 首次设置

环境：macOS 13+、小米蓝牙遥控器 2 Pro（RC003）、SayAll 1.9.21（本预设核对版本）、Python 3；若使用语音，还需要 Typeless、微信输入法和 SayAll 支持的虚拟麦克风。具体安装要求以[SayAll 上游说明](https://github.com/HD838A/remote-mic-app#%E4%BD%BF%E7%94%A8%E8%A6%81%E6%B1%82)为准。

1. 从 [SayAll 官方 GitHub Releases](https://github.com/HD838A/remote-mic-app/releases)安装适合本机架构的版本。在 macOS 蓝牙设置中配对遥控器，打开 SayAll，完成蓝牙、输入监控和辅助功能授权。确认连接页显示遥控器已连接。
2. 安装 Chrome 和 Codex。打开 SayAll 的“按键”页，启用自定义按键功能；配对完成后应已有一条 RC003 设备档案。
3. **完全退出 SayAll**，在本仓库目录执行：

   ```bash
   python3 preset/apply.py          # 只检查，不写入
   python3 preset/apply.py --apply  # 备份原偏好并应用映射
   ```

4. 重新打开 SayAll，在“按键”页确认“确定长按＝`Command-Return`”、方向键单击＝箭头、TV 长按＝Shift-Tab、主页长按＝打开 Codex。先用短按左右、返回删除和电源双击做实体测试。
5. 若要“微信打字＋Typeless 语音”，按[语音与输入法设置](docs/voice-input.md)配置 Fn 点按兼容模式和同一个麦克风。停用旧 `voice-restore`，无需切换键盘输入源。

脚本只支持已配对的 RC003 档案；有多只 RC003 时先运行检查，再用 `--profile-index N` 指定目标。原偏好备份保存在 `~/Library/Application Support/XiaomiRemoteCodexPreset/backups/`，**不要上传该备份**。预设数据在 [`preset/keymap.json`](preset/keymap.json)；脚本保留其他设备档案。仅当 SayAll 只有一只已配对遥控器时，脚本才同步更新供其使用的全局按键映射。

## 给 Agent 的一段话

> 请阅读此仓库的 README、`AGENTS.md`、`docs/keymap.md` 和 `docs/voice-input.md`。先确认 SayAll 来自 HD838A/remote-mic-app 官方发布、遥控器型号为 RC003 且已配对。运行 `python3 preset/apply.py` 做只读检查；经我授权配置后，退出 SayAll，运行 `python3 preset/apply.py --apply`，重启并核对按键页。需要微信打字＋Typeless 语音时按语音文档配置，停用旧 `voice-restore`。不要上传我的 SayAll 偏好、设备标识、日志、语音或 Codex 会话。用实体遥控器验证关键动作，尤其是“确定长按引导”。

## 恢复与排障

- **Typeless 不响应**：核对实际听写快捷键为 Fn，而非向导推荐文字；SayAll 启用 Typeless Fn 点按兼容；两端选择同一麦克风。旧豆包/微信 Fn 语音快捷键和输入源恢复程序应停用。
- **会话导航**：长按主页先打开 Codex，再单击主页进入查找；输入会话名或语音搜索，用上下和确定选择结果。菜单短按/TV 长按提供正反 Tab 焦点移动，仅适用于应用支持的可聚焦控件。
- **按键没反应**：先看 SayAll 是否仍显示已连接，重新打开应用并测试方向键。不要把 TV 长按设为“聚焦输入框”：在 SayAll 自己处于前台时，该动作曾使 1.9.21 卡住。
- **确定长按只发送或没反应**：确认 Codex 前台且底部输入框有焦点，任务正在回复，Codex 的 `followUpQueueMode` 是 `queue`，SayAll 长按动作是 `Command-Return`。空闲时只会发送新消息。若修改了 Codex 的回车行为，参照[按键说明](docs/keymap.md)调整组合键。
- **恢复原配置**：退出 SayAll，用备份文件执行 `defaults import com.hd838a.RemoteMic '<备份文件路径>'`，再启动 SayAll。备份含本机私有设备信息，仅留本机。

## 验证与边界

2026-10-03 v2：预设已应用，SayAll 按键页与偏好映射已读回，现有三项配置脚本测试通过。新增上下长按、Tab/Shift-Tab、主页查找、音量双击与长按仍待实体遥控器验收，不能据此视为已通过。

Typeless 2.8.1 与 SayAll 1.9.21 的 Fn 点按、MiRemoteV 2ch 短句链路已通过 SayAll 的真实声音与文字检查；超过一分钟的连续语音仍需实测。

这套映射基于 SayAll 1.9.21 在一台 RC003 遥控器上的实体测试。已实测方向移动、删除、TV 双击模型选择、Chrome 播放／暂停、旧豆包语音通路，以及 Codex 运行中长按确定引导。SayAll 的偏好存储格式不是公开稳定接口，升级后应先只读检查，再由 Agent 对照新版 UI 验证，避免盲目导入。

本仓库的辅助程序代码采用 [MIT 许可](LICENSE)。SayAll、Codex 与输入法各自遵循其原项目条款。
