#!/bin/bash
# Install the RemoteVoiceRestore user-level background helper.
#
# What this does (all under the current user; nothing system-wide):
#   1. Builds the release binary with SwiftPM (isolated clang module cache).
#   2. Bundles it in a minimal .app so the native TIS API can select an input
#      source (TISSelectInputSource needs a bundle identifier).
#   3. Installs a user LaunchAgent (~/Library/LaunchAgents) that keeps the
#      helper running while you are logged in.
#   4. Bootstraps the agent via launchctl (skipped in --prefix/--dry-run mode).
#
# It never touches voice recordings, transcripts, or credentials, and never
# writes outside the user's own Library folders.
#
# Usage:
#   install.sh                 # real install under the current user
#   install.sh --dry-run       # print what would be done, change nothing
#   install.sh --prefix DIR    # install into DIR/Library/... for isolated testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="dev.xiaomi-remote-codex.voice-restore"
PREFIX=""
DRY_RUN=0

usage() {
  cat <<'EOF' >&2
Usage: install.sh [--prefix DIR] [--dry-run]
  --prefix DIR   install under DIR/Library/... instead of the real user Library
                 (also disables launchctl bootstrap). For isolated testing.
  --dry-run      print the actions that would be taken without doing them.
  -h, --help     show this help.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

# --- Resolve install destinations (user-level only) ---------------------------
INSTALL_ROOT="${PREFIX:-$HOME}"
APP_DIR="$INSTALL_ROOT/Library/Application Support/RemoteVoiceRestore/RemoteVoiceRestore.app"
EXE_PATH="$APP_DIR/Contents/MacOS/remote-voice-restore"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
AGENT_DIR="$INSTALL_ROOT/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$LABEL.plist"
SUPPORT_DIR="$INSTALL_ROOT/Library/Application Support/RemoteVoiceRestore"
STATE_PATH="$SUPPORT_DIR/state.plist"
RESTORE_LOG="$INSTALL_ROOT/Library/Logs/RemoteVoiceRestore/restore.log"
LOG_PATH="$INSTALL_ROOT/Library/Logs/RemoteMic/runtime.log"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    would run: %s\n' "$*"
  else
    "$@"
  fi
}

step() { printf '==> %s\n' "$*"; }

# --- 1. Build -----------------------------------------------------------------
step "building release binary (swift build -c release)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/rvr-swiftmodcache"
SOURCE_DIR="$INSTALL_ROOT/Library/Caches/RemoteVoiceRestore/source"
BUILD_DIR="$INSTALL_ROOT/Library/Caches/RemoteVoiceRestore/swiftpm"
run mkdir -p "$SOURCE_DIR"
run rsync -a --delete --exclude='.build/' --exclude='.swiftpm/' "$SCRIPT_DIR/" "$SOURCE_DIR/"
run swift build -c release --disable-sandbox --package-path "$SOURCE_DIR" --scratch-path "$BUILD_DIR"
BIN="$BUILD_DIR/release/remote-voice-restore"
if [[ $DRY_RUN -eq 0 && ! -x "$BIN" ]]; then
  echo "error: build did not produce $BIN" >&2
  exit 1
fi

# --- 2. App bundle ------------------------------------------------------------
step "installing app bundle at $APP_DIR"
run mkdir -p "$APP_DIR/Contents/MacOS"
run cp "$BIN" "$EXE_PATH"
run chmod 755 "$EXE_PATH"

step "writing Info.plist (bundle identifier required by TIS)"
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$APP_DIR/Contents"
  cat > "$INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$LABEL</string>
  <key>CFBundleName</key>
  <string>RemoteVoiceRestore</string>
  <key>CFBundleExecutable</key>
  <string>remote-voice-restore</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
</dict>
</plist>
EOF
fi

# Adhoc-sign the bundle so its Contents/Info.plist is bound into the signature.
# No identity or keychain is used; this is the sandbox-safe, user-level default.
step "adhoc-signing app bundle (binds Info.plist for TIS)"
run codesign --force --sign - "$APP_DIR"

# --- 3. Launch agent plist ----------------------------------------------------
step "writing launch agent at $AGENT_PLIST"
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$AGENT_DIR"
  cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$EXE_PATH</string>
    <string>--log-path</string>
    <string>$LOG_PATH</string>
    <string>--state-path</string>
    <string>$STATE_PATH</string>
    <string>--restore-log</string>
    <string>$RESTORE_LOG</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF
fi

# --- 4. Load the agent --------------------------------------------------------
if [[ -n "$PREFIX" ]]; then
  step "prefix mode: not loading launch agent (no launchctl, no system changes)"
elif [[ $DRY_RUN -eq 1 ]]; then
  step "would (re)load agent:"
  run launchctl bootout "gui/$(id -u)" "$AGENT_PLIST"
  run launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
  run launchctl kickstart -k "gui/$(id -u)/$LABEL"
else
  step "loading launch agent (launchctl bootstrap)"
  launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
fi

step "done."
if [[ -z "$PREFIX" && $DRY_RUN -eq 0 ]]; then
  echo "    check status with:  $SCRIPT_DIR/status.sh"
  echo "    uninstall with:     $SCRIPT_DIR/uninstall.sh"
fi
