> 本页为 Typeless 单语音方案。默认微信、TV 双击切 Typeless 的可选方案见 [双语音设置](dual-voice.md)，两者的 Fn 配置不同。

# 微信打字＋Typeless 遥控器语音

键盘使用微信输入法，遥控器语音由 Typeless 识别。Typeless 把结果插入当前输入框，无需切换键盘输入源。

## 设置

1. 从 [Typeless 官方网站](https://www.typeless.com/)安装应用，完成其权限与快捷键向导。权限需要本人授权，密码由本人输入。
2. 在 Typeless 设置中，把**实际语音输入快捷键**设为 `Fn`；向导写“推荐 Fn”不代表实际已保存 Fn。当前 2.8.1 是按一下开始，再按一下结束。
3. 在 SayAll 1.9.21 首次向导中选择 Typeless，启用 **Fn 点按兼容模式**，完成真实按键及语音测试。遥控器按住开始收音，松开结束；SayAll 将这两个边沿转换成 Typeless 所需的 Fn 点按。
4. SayAll 语音输出与 Typeless 麦克风都选择 **MiRemoteV 2ch**。只配置系统默认输入可能选错设备。
5. 关闭微信、豆包对 Fn 语音的占用。若装过本仓库旧恢复辅助程序，执行 `voice-restore/uninstall.sh` 停用；不要安装它用于 Typeless。普通输入源切到微信。
6. 在 Codex 输入框按住遥控器语音键，说一句后松开；确认 Typeless 浮窗结束、文字留下。再验证一段超过一分钟的实际语音，最后用键盘打字确认仍是微信。

## 运行限制

Typeless 官方当前说明每次听写最长 **9 分钟**，到上限会结束并保存到 History；并非无限录音。免费版还有字数额度，以应用显示为准。本方案不自动购买或订阅。

[官方听写说明](https://www.typeless.com/help/quickstart/dictate) · [单次时长说明](https://www.typeless.com/help/troubleshooting/dictation-limit)

## 排障与 Agent 注意事项

- 无浮窗：先核对实际 Fn 快捷键、SayAll 点按兼容、权限及连接。
- 有浮窗但无声音：核对两端 MiRemoteV 2ch，并测试遥控器声音。
- 向导报输入目标未就绪：把 SayAll 测试窗口置于前台并点输入框，别在 Codex 输入框测试该步骤。
- 长句没上屏：检查 Typeless History、网络和额度；不要切换输入源来结束临时识别。
- 不发布应用偏好、麦克风设备 ID、日志、识别文字、账户信息或 Codex 会话。

旧豆包方案见[历史说明](voice-input-legacy-doubao.md)，仅适用于主动选择该方案的人。
