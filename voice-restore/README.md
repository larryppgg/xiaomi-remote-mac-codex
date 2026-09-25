# RemoteVoiceRestore

A small user-level macOS helper that restores WeChat Input Method (微信输入法)
after a Xiaomi Remote 2 Pro speech session via SayAll / Doubao.

## Problem

SayAll 1.9.21 temporarily selects Doubao Input Method while the remote's Fn
speech key is held. With Doubao's global voice enabled, the *active* input
source stays on Doubao after the key is released even though SayAll reports it
"restored". WeChat Input Method is the daily keyboard IME, so the next keystroke
goes to Doubao until the user switches back manually.

## What it does

1. Tails `~/Library/Logs/RemoteMic/runtime.log` (written by SayAll) and watches
   for physical remote `ATVV STREAM START/STOP session=...` events.
2. When the remote stream starts, it records the currently active
   non-Doubao input source (usually WeChat) into a small state file.
3. When the remote stream stops, it waits 3 seconds by default so Doubao can
   commit even a long recognized utterance, then restores the previous input
   source **only if the active source is still Doubao**.
4. It never touches the source if the active source is anything else — a manual
   switch to ABC / another IME is respected and left alone.

Fn injection and `source_prepare` lines are deliberately **not** triggers;
some physical remote sessions have no Fn log entry.

## Requirements

- macOS 13+ (arm64 or x86_64), Xcode command line tools with Swift.
- SayAll 1.9.21 with Doubao mode (writes the runtime.log above).
- WeChat Input Method installed (`com.tencent.inputmethod.wetype.pinyin`) and
  Doubao Input Method installed (`com.bytedance.inputmethod.doubaoime.pinyin`).
  (These IDs are configurable via CLI flags if yours differ.)

## Install

```bash
cd voice-restore
./install.sh
```

This builds the release binary, bundles it in a minimal `.app`, installs a
**user** LaunchAgent (`~/Library/LaunchAgents/dev.xiaomi-remote-codex.voice-restore.plist`)
and loads it via `launchctl`. Build cache and installed runtime files are under
your own `~/Library`.

## Status / stop / uninstall

```bash
./status.sh      # is it installed/running, active input source, log tail
./uninstall.sh   # stop agent + remove agent plist + app bundle (keeps state/log)
./uninstall.sh --purge   # also delete state.plist and restore.log
```

To stop the helper without uninstalling:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/dev.xiaomi-remote-codex.voice-restore.plist
```

## Rollback

Uninstall restores the system to its prior state: the LaunchAgent is removed and
SayAll, Doubao and WeChat Input Method are untouched (the helper never modifies
their settings). `uninstall.sh --purge` additionally removes the helper's state
file and observability log.

## Isolated testing

```bash
./install.sh --prefix "$(mktemp -d)"   # install under DIR/Library, no launchctl
./status.sh --prefix "$DIR"            # inspect that install
./uninstall.sh --prefix "$DIR" --purge # remove it
```

All scripts support `--dry-run` to print actions without changing anything.

## Privacy

- The helper **never** stores or logs voice content, transcripts, audio, or
  credentials. It only records an input-source ID
  (e.g. `com.tencent.inputmethod.wetype.pinyin`).
- The observability log (`~/Library/Logs/RemoteVoiceRestore/restore.log`)
  contains timestamps and action lines like
  `press: active=... recorded-as-pre-session` / `ended: restored target=...` —
  no sensitive data.
- Input-source selection uses the native macOS Text Input Source (TIS) API.

## Architecture

| File | Responsibility |
| --- | --- |
| `VoiceLogParser` | Deterministic parser for SayAll remote stream events |
| `SessionTracker` | Pure state machine (down/up, overlap, orphan release) |
| `RestorePolicy` | Restore only if active is still Doubao; respect manual choice |
| `LogReader` | Robust tail: append, truncation, rotation, recreation, missing file, partial lines, invalid UTF-8 |
| `StateStore` | Atomic plist of last non-Doubao source ID |
| `InputSourceController` | TIS native input-source API (fake used in tests) |
| `Orchestrator` | Wires parsing→tracking→policy; delayed restore on a dedicated queue |
| `main.swift` | CLI, plain-C signal handler, poll loop |

## Tests

```bash
./install.sh  # also copies source to the local build cache
swift test --disable-sandbox \
  --package-path ~/Library/Caches/RemoteVoiceRestore/source \
  --scratch-path /tmp/remote-voice-restore-tests   # 40 tests
```

The deterministic test suite covers the parser, session edge cases (overlap,
orphan releases, other tools), the restore policy (manual-choice protection),
the log reader (append/truncate/rotate/recreate/partial/invalid UTF-8) and the
orchestrator end-to-end with a fake input-source controller.
