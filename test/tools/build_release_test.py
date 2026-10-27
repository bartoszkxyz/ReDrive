#!/usr/bin/env python3
"""
Unit tests for tools/build_release.py
"""

import os
import sys
import unittest

# Add tools to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'tools')))

from build_release import (
    bump_version,
    detect_affected_targets,
    locate_aapt,
    format_bytes,
)


class TestBuildRelease(unittest.TestCase):
    def test_bump_version(self):
        self.assertEqual(bump_version('2.0.2+9', 'patch'), '2.0.3+10')
        self.assertEqual(bump_version('2.0.2+9', 'minor'), '2.1.0+10')
        self.assertEqual(bump_version('2.0.2+9', 'major'), '3.0.0+10')
        self.assertEqual(bump_version('2.0.2+9', 'build'), '2.0.2+10')

    def test_detect_affected_targets_headunit(self):
        files = ['lib/widget/cockpit/pip_application_bay.dart', 'test/widget/pip_application_bay_test.dart']
        targets, reason = detect_affected_targets(files)
        self.assertEqual(targets, ['headunit'])
        self.assertIn('Headunit only', reason)

    def test_detect_affected_targets_phone(self):
        files = ['lib/widget/companion/sync_status_pill.dart', 'test/screens/phone_companion_screen_test.dart']
        targets, reason = detect_affected_targets(files)
        self.assertEqual(targets, ['phone'])
        self.assertIn('Phone only', reason)

    def test_detect_affected_targets_shared(self):
        files = ['lib/services/logging/log_service.dart']
        targets, reason = detect_affected_targets(files)
        self.assertEqual(targets, ['headunit', 'phone'])
        self.assertIn('Both targets affected', reason)

    def test_detect_affected_targets_empty(self):
        targets, reason = detect_affected_targets([])
        self.assertEqual(targets, ['headunit', 'phone'])

    def test_locate_aapt(self):
        aapt = locate_aapt()
        self.assertIsNotNone(aapt)
        self.assertTrue(os.path.exists(aapt))

    def test_format_bytes(self):
        self.assertEqual(format_bytes(500), '500 B')
        self.assertEqual(format_bytes(1024 * 500), '500.0 KB')
        self.assertEqual(format_bytes(1024 * 1024 * 68), '68.0 MB')


if __name__ == '__main__':
    unittest.main()
