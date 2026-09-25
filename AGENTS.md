# Agent setup notes

This repository is a public preset for SayAll, not a copy of SayAll. Read `README.md`, `docs/keymap.md`, and `docs/voice-input.md` before changing a user's Mac.

1. Install SayAll from `https://github.com/HD838A/remote-mic-app/releases`; verify the installed version and RC003 pairing in the UI.
2. Treat `preset/keymap.json` as the public keymap. Never commit or upload `defaults export com.hd838a.RemoteMic`, `remoteDeviceProfiles`, logs, backup plists, device fingerprints, Bluetooth identifiers, voice text, or Codex sessions.
3. Run `python3 preset/apply.py` first. To apply, quit SayAll, run `python3 preset/apply.py --apply`, relaunch SayAll, and inspect its button page. The script creates a local private backup. Do not silently overwrite other remote profiles.
4. Configure voice only after the user wants Doubao speech and WeChat typing. Use `docs/voice-input.md`; check app permissions through the UI and obtain any required user action. Verify a real long utterance remains committed and keyboard input returns to WeChat.
5. Test physical buttons against the user's current Codex version. With default Enter behavior, Command-Return steered an in-progress reply on the original tested Mac; other versions and input focus states still require a real test. If it fails, report the observed result and update the preset only with evidence.
6. Do not substitute global keyboard control for application focus checks. Do not turn on macOS Full Keyboard Access solely for this preset.
