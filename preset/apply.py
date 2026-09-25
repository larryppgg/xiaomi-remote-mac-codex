#!/usr/bin/env python3
"""Apply the public keymap to one paired RC003 profile in SayAll.

Only the mapping fields are changed. The private preferences export and its
backup stay on the user's Mac and must never be committed to this repository.
"""

import argparse
import copy
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from uuid import uuid4

DOMAIN = "com.hd838a.RemoteMic"
PRESET = Path(__file__).with_name("keymap.json")
BACKUP_DIR = Path.home() / "Library/Application Support/XiaomiRemoteCodexPreset/backups"
SAYALL_INFO = Path("/Applications/SayAll.app/Contents/Info.plist")
TESTED_VERSION = "1.9.21"


def decoded_json(plist, key, fallback):
    value = plist.get(key)
    return json.loads(value) if value is not None else copy.deepcopy(fallback)


def encoded_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def sayall_running():
    return subprocess.run(["pgrep", "-x", "RemoteMic"], capture_output=True).returncode == 0


def installed_version():
    if not SAYALL_INFO.is_file():
        raise ValueError("Install SayAll.app from the upstream official release first")
    with SAYALL_INFO.open("rb") as file:
        return plistlib.load(file).get("CFBundleShortVersionString", "unknown")


def chrome_path():
    for candidate in (Path("/Applications/Google Chrome.app"),
                      Path.home() / "Applications/Google Chrome.app"):
        if candidate.exists():
            return str(candidate)
    raise ValueError("Google Chrome.app is required for Home double-click")


def choose_profile(profiles, index):
    matches = [i for i, profile in enumerate(profiles) if profile.get("model") == "rc003"]
    if index is not None:
        if index not in matches:
            raise ValueError("--profile-index must identify an RC003 profile")
        return index
    if len(matches) != 1:
        raise ValueError(f"Expected one paired RC003 profile; found {len(matches)}. "
                         "Pair the remote first or pass --profile-index.")
    return matches[0]


def prepare(plist, preset, profile_index):
    updated = copy.deepcopy(plist)
    profiles = decoded_json(updated, "remoteDeviceProfiles", [])
    selected = choose_profile(profiles, profile_index)
    apps = decoded_json(updated, "customApplicationProfiles", [])
    chrome = next((item for item in apps if item.get("bundleIdentifier") == "com.google.Chrome"), None)
    if chrome is None:
        chrome = {
            "id": str(uuid4()).upper(),
            "displayName": "Google Chrome",
            "bundleIdentifier": "com.google.Chrome",
            "applicationPath": chrome_path(),
            "focusStrategy": "none",
        }
        apps.append(chrome)

    secondary = copy.deepcopy(preset["secondaryButtonBindings"])
    secondary["home"]["doubleClick"].pop("application")
    secondary["home"]["doubleClick"]["applicationProfileID"] = chrome["id"]
    mappings = {
        "buttonBindings": copy.deepcopy(preset["buttonBindings"]),
        "buttonShortcuts": copy.deepcopy(preset["buttonShortcuts"]),
        "secondaryButtonBindings": secondary,
        "buttonRapidPressEnabled": {},
    }
    profiles[selected].setdefault("mappings", {}).update(mappings)
    updated["remoteDeviceProfiles"] = encoded_json(profiles)
    updated["customApplicationProfiles"] = encoded_json(apps)
    # Legacy global bindings are a fallback for every remote. Updating them is
    # safe only when this is the sole paired device.
    if len(profiles) == 1:
        for key, value in mappings.items():
            updated[key] = encoded_json(value)
    updated["customMappingEnabled"] = True
    return updated, selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write settings (default: check only)")
    parser.add_argument("--profile-index", type=int, help="choose among multiple paired RC003 profiles")
    args = parser.parse_args()
    preset = json.loads(PRESET.read_text(encoding="utf-8"))
    if preset.get("format") != 1:
        parser.error("unsupported keymap format")
    try:
        version = installed_version()
        print(f"SayAll version: {version}")
        if args.apply and version != TESTED_VERSION:
            raise ValueError(f"This preset was tested with SayAll {TESTED_VERSION}; "
                             "inspect the new version's mapping UI/schema before applying")
        original_bytes = subprocess.check_output(["defaults", "export", DOMAIN, "-"])
        original = plistlib.loads(original_bytes)
        updated, selected = prepare(original, preset, args.profile_index)
        print(f"RC003 profile index: {selected}")
        print(f"Mappings changed: {original != updated}")
        if not args.apply:
            print("Read-only check complete. Quit SayAll, then run with --apply to save.")
            return
        if sayall_running():
            raise ValueError("Quit SayAll completely before applying settings")
        BACKUP_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup = BACKUP_DIR / f"sayall-before-keymap-{stamp}.plist"
        with backup.open("xb") as file:
            os.fchmod(file.fileno(), 0o600)
            file.write(original_bytes)
        with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as file:
            temp_path = Path(file.name)
            os.fchmod(file.fileno(), 0o600)
            file.write(plistlib.dumps(updated, fmt=plistlib.FMT_XML))
        try:
            subprocess.run(["defaults", "import", DOMAIN, str(temp_path)], check=True)
        finally:
            temp_path.unlink(missing_ok=True)
        readback = plistlib.loads(subprocess.check_output(["defaults", "export", DOMAIN, "-"]))
        if readback != updated:
            raise RuntimeError("Preferences readback differs; backup kept at " + str(backup))
        print("Saved and verified. Backup: " + str(backup))
        print("Launch SayAll and check the button page before testing physical keys.")
    except (ValueError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
