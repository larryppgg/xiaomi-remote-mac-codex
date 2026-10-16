#!/usr/bin/env python3
"""Register the already installed helper as a user login service."""
import argparse
import os
import plistlib
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
app = Path.home() / 'Applications/遥控器语音切换.app'
exe = app / 'Contents/MacOS/RemoteVoiceSwitcher'
if not exe.is_file():
    raise SystemExit('Install the built app in ~/Applications first.')
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
label = 'io.github.remote-voice-switcher'
path = Path.home() / f'Library/LaunchAgents/{label}.plist'
service = {'Label': label, 'ProgramArguments': [str(exe)], 'RunAtLoad': True,
           'KeepAlive': {'SuccessfulExit': False}, 'ProcessType': 'Interactive'}
if not args.apply:
    print('Read-only check passed. Quit the helper while idle, then use --apply.')
else:
    if path.exists() and plistlib.loads(path.read_bytes()) != service:
        raise SystemExit('Existing login service differs. Inspect it before changing.')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(service))
    target = f'gui/{os.getuid()}'
    inspection = subprocess.run(['launchctl', 'print', f'{target}/{label}'],
                                capture_output=True, text=True)
    loaded = inspection.returncode == 0
    if loaded and not re.search(r'^\s*pid = \d+\s*$', inspection.stdout, re.MULTILINE):
        # Re-register an idle job after app replacement: launchd may retain
        # code-signing constraints for the previous executable (EX_CONFIG).
        # A live process is never booted out by an installation rerun.
        subprocess.run(['launchctl', 'bootout', f'{target}/{label}'], check=True)
        loaded = False
    if not loaded:
        subprocess.run(['launchctl', 'bootstrap', target, str(path)], check=True)
    # No -k: start a stopped job without interrupting an existing recording.
    subprocess.run(['launchctl', 'kickstart', f'{target}/{label}'], check=True)
    print('Login service installed; start requested without restarting a running helper. '
          'Verify actual helper state and physical voice.')
