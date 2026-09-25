#!/bin/bash
# Show whether the RemoteVoiceRestore helper is installed/running, the active
# input source, and the tail of the observability log. Read-only.
#
# Usage:
#   status.sh                  # real install
#   status.sh --prefix DIR     # inspect a --prefix install
set -euo pipefail

LABEL="dev.xiaomi-remote-codex.voice-restore"
PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: status.sh [--prefix DIR]" >&2; exit 1 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

INSTALL_ROOT="${PREFIX:-$HOME}"
EXE="$INSTALL_ROOT/Library/Application Support/RemoteVoiceRestore/RemoteVoiceRestore.app/Contents/MacOS/remote-voice-restore"
AGENT_PLIST="$INSTALL_ROOT/Library/LaunchAgents/$LABEL.plist"
RESTORE_LOG="$INSTALL_ROOT/Library/Logs/RemoteVoiceRestore/restore.log"

echo "== helper executable"
if [[ -x "$EXE" ]]; then
  echo "  present: $EXE"
else
  echo "  MISSING: $EXE"
fi

echo "== launch agent"
if [[ -f "$AGENT_PLIST" ]]; then
  echo "  plist: $AGENT_PLIST"
  if [[ -z "$PREFIX" ]]; then
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
      echo "  loaded: yes"
    else
      echo "  loaded: no"
    fi
  else
    echo "  loaded: n/a (prefix mode)"
  fi
else
  echo "  plist: MISSING ($AGENT_PLIST)"
fi

echo "== active input source (needs the bundled .app so TIS can select)"
if [[ -x "$EXE" ]]; then
  "$EXE" --print-current-source || echo "  (unable to read input source)"
else
  echo "  n/a (executable not installed)"
fi

echo "== observability log tail"
if [[ -f "$RESTORE_LOG" ]]; then
  tail -n 5 "$RESTORE_LOG" | sed 's/^/  /'
else
  echo "  no restore log yet: $RESTORE_LOG"
fi
