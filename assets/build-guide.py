#!/usr/bin/env python3
"""Render the public remote reference as an SVG without private device data."""
from html import escape
from pathlib import Path
import sys
dual = "--dual" in sys.argv

rows = [
    ('语音', '按住说话，松开结束（Typeless）', '—', '—'),
    ('左 / 右', '标准方向键 ← / →', '连续单击保持方向', '按住方向连续移动'),
    ('上 / 下', '标准方向键 ↑ / ↓', '连续单击保持方向', '按住方向连续移动'),
    ('确定', '回车；遵循默认发送行为', '全选', '⌘Return；回复中引导*'),
    ('返回', '删除一个字，可连续删除', '连续单击保持删除', '删除前一个词'),
    ('主页', '⌘K：命令 / 会话查找*', '打开 Chrome', '打开 Codex'),
    ('菜单', 'Tab：下一个控件', '复制', '粘贴'),
    ('电源', 'Esc：取消 / 关闭弹窗', '播放 / 暂停', '关闭窗口 / 标签'),
    ('TV', '切换应用', 'Codex 模型选择器*', '⇧Tab：上一个控件'),
    ('音量 +', '页面向上滚动', '撤销', '上一个最近会话 / 标签*'),
    ('音量 −', '页面向下滚动', '重做', '下一个最近会话 / 标签*'),
]
if dual:
    rows[0] = ('语音', '按住说话，松开结束（当前模式）', '—', '—')
    rows[7] = ('电源', 'Esc：取消 / 关闭弹窗', '播放 / 暂停', '⇧Tab：上一个控件')
    rows[8] = ('TV', '切换应用', '微信 / Typeless 切换', 'Codex 模型选择器*')
parts = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1600" viewBox="0 0 1600 1600">',
    '<rect width="1600" height="1600" fill="#101827"/>',
    '<style>text{font-family:"PingFang SC","Microsoft YaHei",sans-serif;fill:#eef3fb}.small{font-size:23px;fill:#acbfd6}.body{font-size:25px}.head{font-size:25px;font-weight:600;fill:#77dcce}</style>',
    '<text x="70" y="90" font-size="43" font-weight="700">小米遥控器 2 Pro · Mac / Codex 按键速查</text>',
    '<text x="70" y="138" class="small">微信打字 + Typeless 语音｜SayAll 1.9.21｜RC003｜v2 · 2026-10-03</text>',
    '<rect x="65" y="175" width="1470" height="68" rx="12" fill="#23324a"/>',
]
xs = [90, 305, 815, 1180]
for x, label in zip(xs, ['按键', '单击 / 基础操作', '双击', '长按']):
    parts.append(f'<text x="{x}" y="218" class="head">{label}</text>')
for i, row in enumerate(rows):
    y = 250 + i * 75
    if i % 2 == 0:
        parts.append(f'<rect x="65" y="{y}" width="1470" height="72" rx="8" fill="#192638"/>')
    for x, label in zip(xs, row):
        parts.append(f'<text x="{x}" y="{y+45}" class="body">{escape(label)}</text>')
notes = [
    '* 长按确定：Codex 正在回复且输入框聚焦时引导；空闲时正常发送。',
    '* 音量长按：Codex 最近会话 / Chrome 标签；不按侧边栏项目顺序遍历。',
    '* 主页查找与 TV 模型：依赖目标应用。Tab 只移动应用支持的可聚焦控件。',
    '语音：实际快捷键 Fn；SayAll 开启 Fn 点按兼容；两端麦克风都选 MiRemoteV 2ch。',
]
if dual:
    parts = [p.replace("微信打字 + Typeless 语音｜SayAll 1.9.21｜RC003｜v2 · 2026-10-03", "默认微信语音 · TV 双击切 Typeless｜SayAll 1.9.21｜v3 双语音") for p in parts]
    notes[-1] = "语音：默认微信；TV 双击切换模式；录音中切换在松开后生效。"
for i, note in enumerate(notes):
    parts.append(f'<text x="75" y="{1120+i*39}" class="small">{escape(note)}</text>')
parts += [
    '<rect x="65" y="1300" width="1470" height="230" rx="18" fill="#23324a"/>',
    '<text x="90" y="1345" class="head">常用操作顺序</text>',
    '<text x="90" y="1390" class="body">找会话：长按主页进入 Codex → 单击主页查找 → 输入名称 → 上下选择 → 确定。</text>',
    '<text x="90" y="1435" class="body">修正文字：方向移动 → 返回删除；双击确定全选；音量＋双击撤销、－双击重做。</text>',
    '<text x="90" y="1480" class="body">切控件：菜单短按往后、TV 长按往前；退出菜单用电源短按。</text>',
    '</svg>',
]
if dual:
    parts = [p.replace('TV 长按往前', '电源长按往前') for p in parts]
Path(__file__).with_name('remote-keymap-dual-voice-zh.svg' if dual else 'remote-keymap-zh.svg').write_text('\n'.join(parts), encoding='utf-8')
