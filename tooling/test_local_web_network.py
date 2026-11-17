"""Regression for the HTTP LAN URLs produced by the desktop QR plugin."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'app/android/app/src'


class LocalWebNetworkTest(unittest.TestCase):
    def test_lite_allows_user_selected_http_lan_origins(self):
        tree = ET.parse(SOURCE/'main/res/xml/network_security_config.xml')
        base = tree.find('base-config')
        self.assertIsNotNone(base)
        self.assertEqual(base.get('cleartextTrafficPermitted'), 'true')

    def test_single_network_policy_has_no_retired_variant_override(self):
        self.assertFalse((SOURCE/'localWebLite/res/xml/network_security_config.xml').exists())

    def test_lite_does_not_add_custom_tls_trust(self):
        tree = ET.parse(SOURCE/'main/res/xml/network_security_config.xml')
        self.assertIsNone(tree.find('.//trust-anchors'))
        self.assertIsNone(tree.find('.//debug-overrides'))

    def test_manifest_uses_overridable_network_resource(self):
        app = ET.parse(SOURCE/'main/AndroidManifest.xml').find('application')
        self.assertEqual(app.get('{http://schemas.android.com/apk/res/android}networkSecurityConfig'),
                         '@xml/network_security_config')


if __name__ == '__main__':
    unittest.main()
