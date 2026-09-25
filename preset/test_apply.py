import copy
import importlib.util
import json
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("keymap_apply", Path(__file__).with_name("apply.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
PRESET = json.loads(Path(__file__).with_name("keymap.json").read_text(encoding="utf-8"))


class MappingTests(unittest.TestCase):
    def make_preferences(self):
        profiles = [
            {"model": "rc001", "id": "other-device", "mappings": {"buttonBindings": {"ok": "escape"}}},
            {"model": "rc003", "id": "target-device", "bluetoothIdentifier": "private-local-id",
             "mappings": {"buttonBindings": {"ok": "escape"}}},
        ]
        apps = [{"id": "chrome-profile", "bundleIdentifier": "com.google.Chrome",
                 "applicationPath": "/Applications/Google Chrome.app", "displayName": "Google Chrome",
                 "focusStrategy": "none"}]
        return {"remoteDeviceProfiles": module.encoded_json(profiles),
                "customApplicationProfiles": module.encoded_json(apps),
                "unrelatedSetting": "preserve-me"}

    def test_only_target_profile_and_keymap_change(self):
        original = self.make_preferences()
        original_copy = copy.deepcopy(original)
        result, index = module.prepare(original, PRESET, None)
        profiles = module.decoded_json(result, "remoteDeviceProfiles", [])
        self.assertEqual(index, 1)
        self.assertEqual(profiles[0], module.decoded_json(original, "remoteDeviceProfiles", [])[0])
        self.assertEqual(profiles[1]["bluetoothIdentifier"], "private-local-id")
        self.assertEqual(profiles[1]["mappings"]["buttonBindings"]["back"], "deleteBackward")
        self.assertEqual(profiles[1]["mappings"]["secondaryButtonBindings"]["ok"]["longPress"], {"action": "commandReturn"})
        self.assertEqual(profiles[1]["mappings"]["secondaryButtonBindings"]["home"]["doubleClick"]["applicationProfileID"], "chrome-profile")
        self.assertEqual(result["unrelatedSetting"], "preserve-me")
        self.assertNotIn("buttonBindings", result)  # other device keeps global fallback
        self.assertEqual(original, original_copy)

    def test_idempotent_with_existing_chrome_profile(self):
        first, _ = module.prepare(self.make_preferences(), PRESET, None)
        second, _ = module.prepare(first, PRESET, None)
        self.assertEqual(first, second)

    def test_multiple_rc003_profiles_require_explicit_index(self):
        original = self.make_preferences()
        profiles = module.decoded_json(original, "remoteDeviceProfiles", [])
        profiles.append({"model": "rc003", "id": "second-device", "mappings": {}})
        original["remoteDeviceProfiles"] = module.encoded_json(profiles)
        with self.assertRaises(ValueError):
            module.prepare(original, PRESET, None)


if __name__ == "__main__":
    unittest.main()
