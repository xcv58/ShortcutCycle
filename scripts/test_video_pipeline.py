"""Capture isolation regressions; no desktop interaction or recording required."""
import plistlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import video_pipeline as pipeline


class CaptureIsolationTests(unittest.TestCase):
    def test_process_lookup_excludes_production_and_other_dev_install(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / 'ShortcutCycle Dev.app'
            (bundle / 'Contents').mkdir(parents=True)
            (bundle / 'Contents' / 'Info.plist').write_bytes(
                plistlib.dumps({'CFBundleExecutable': 'ShortcutCycle'})
            )
            executable = bundle / 'Contents' / 'MacOS' / 'ShortcutCycle'
            processes = '\n'.join([
                '11 /Applications/ShortcutCycle.app/Contents/MacOS/ShortcutCycle',
                '12 /private/tmp/other/ShortcutCycle Dev.app/Contents/MacOS/ShortcutCycle',
                f'13 {executable}',
                f'14 {executable} Helper',
            ])
            with patch.object(pipeline, 'run', return_value=SimpleNamespace(stdout=processes)):
                self.assertEqual(pipeline.integration_process_ids(
                    {'app_bundle_path': str(bundle)}), [13])

    def test_unsandboxed_capture_uses_its_own_domain_in_normal_home(self):
        profile = {'bundle_id': 'com.example.capture', 'sandboxed': False}
        home = Path.home()
        self.assertEqual(pipeline.preferences_path(profile),
                         home / 'Library/Preferences/com.example.capture.plist')
        self.assertEqual(pipeline.integration_query_result_path(profile),
                         home / 'tmp/shortcutcycle-result.json')
        self.assertEqual(pipeline.fixture_import_path(profile),
                         home / 'tmp/shortcutcycle-fixture.json')


    def test_sandbox_profile_retains_container_paths(self):
        profile = {'bundle_id': 'com.example.dev'}
        self.assertEqual(pipeline.integration_home_directory(profile),
                         Path.home() / 'Library/Containers/com.example.dev/Data')


if __name__ == '__main__':
    unittest.main()
