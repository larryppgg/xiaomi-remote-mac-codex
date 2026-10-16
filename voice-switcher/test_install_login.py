"""Isolated installer regressions: no real launchctl, signing or preferences."""
import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('install-login.py')


class LoginTests(unittest.TestCase):
    def exercise(self, loaded):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            exe = home / 'Applications/遥控器语音切换.app/Contents/MacOS/RemoteVoiceSwitcher'
            exe.parent.mkdir(parents=True)
            exe.touch()

            def run(command, **kwargs):
                calls.append(command)
                return subprocess.CompletedProcess(command, 0 if command[:2] != ['launchctl', 'print'] or loaded else 1)

            with patch.object(Path, 'home', return_value=home), patch('subprocess.run', side_effect=run), \
                 patch('sys.argv', [str(SCRIPT), '--apply']), contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(SCRIPT), run_name='__main__')
        return calls

    def test_registered_stopped_service_is_started_without_force_restart(self):
        calls = self.exercise(loaded=True)
        self.assertFalse(any(c[:2] == ['launchctl', 'bootstrap'] for c in calls))
        starts = [c for c in calls if c[:2] == ['launchctl', 'kickstart']]
        self.assertEqual(len(starts), 1)
        self.assertEqual(len(starts[0]), 3)
        self.assertNotIn('-k', starts[0])

    def test_fresh_service_is_bootstrapped_before_start_request(self):
        calls = self.exercise(loaded=False)
        operations = [c[1] for c in calls if c[0] == 'launchctl']
        self.assertEqual(operations, ['print', 'bootstrap', 'kickstart'])


if __name__ == '__main__':
    unittest.main()
