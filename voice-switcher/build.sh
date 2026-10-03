#!/bin/zsh
set -euo pipefail
task_root="${0:A:h}"
cd "$task_root"
swift build -c release
task_bin="$(swift build -c release --show-bin-path)"
task_app="$task_root/dist/遥控器语音切换.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin/RemoteVoiceSwitcher" "$task_app/Contents/MacOS/RemoteVoiceSwitcher"
cp Support/Info.plist "$task_app/Contents/Info.plist"
xattr -dr com.apple.FinderInfo "$task_app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$task_app" 2>/dev/null || true
codesign --force --sign - --requirements '=designated => identifier "io.github.remote-voice-switcher"' "$task_app"
codesign --verify --strict "$task_app"
print "$task_app"
