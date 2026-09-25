#!/bin/bash
# Uninstall the RemoteVoiceRestore background helper.
#
# Removes the LaunchAgent and the app bundle. The persisted state file and the
# observability log are kept by default; pass --purge to remove them too.
#
# Usage:
#   uninstall.sh               # stop agent, remove agent plist + app bundle
#   uninstall.sh --purge       # also delete state.plist and restore.log
#   uninstall.sh --prefix DIR  # undo a --prefix install
#   uninstall.sh --dry-run     # print actions without changing anything
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="dev.xiaomi-remote-codex.voice-restore"
PREFIX=""
DRY_RUN=0
PURGE=0

usage() {
  cat <<'EOF' >&2
Usage: uninstall.sh [--prefix DIR] [--purge] [--dry-run]
  --prefix DIR   target a --prefix install under DIR/Library/...
  --purge        also delete the state file and the observability log
  --dry-run      print actions without changing anything
  -h, --help     show this help.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

INSTALL_ROOT="${PREFIX:-$HOME}"
APP_DIR="$INSTALL_ROOT/Library/Application Support/RemoteVoiceRestore/RemoteVoiceRestore.app"
AGENT_PLIST="$INSTALL_ROOT/Library/LaunchAgents/$LABEL.plist"
STATE_PATH="$INSTALL_ROOT/Library/Application Support/RemoteVoiceRestore/state.plist"
RESTORE_LOG="$INSTALL_ROOT/Library/Logs/RemoteVoiceRestore/restore.log"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    would run: %s\n' "$*"
  else
    "$@"
  fi
}
step() { printf '==> %s\n' "$*"; }

step "unloading launch agent (launchctl bootout, errors ignored)"
if [[ -z "$PREFIX" && $DRY_RUN -eq 0 ]]; then
  launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || true
elif [[ $DRY_RUN -eq 1 ]]; then
  run launchctl bootout "gui/$(id -u)" "$AGENT_PLIST"
else
  step "prefix mode: no launchctl call"
fi

step "removing agent plist: $AGENT_PLIST"
run rm -f "$AGENT_PLIST"

step "removing app bundle: $APP_DIR"
run rm -rf "$APP_DIR"

if [[ $PURGE -eq 1 ]]; then
  step "removing state file: $STATE_PATH"
  run rm -f "$STATE_PATH"
  step "removing restore log: $RESTORE_LOG"
  run rm -f "$RESTORE_LOG"
else
  step "keeping state file and restore log (use --purge to remove)"
fi

step "done."
