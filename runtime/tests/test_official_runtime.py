"""Pure builder contracts: no device, npm, or runtime extraction required."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("official_builder", Path(__file__).parents[1] / "build-official-runtime.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class OfficialRuntimeBuilderTest(unittest.TestCase):
    def test_current_release_is_pinned_to_official_rc3(self):
        self.assertEqual("0.2.2-rc.3", builder.OFFICIAL_VERSION)

    def test_archive_names_reject_escape_absolute_and_backslash(self):
        for name in ("/etc/passwd", "../x", "a/../x", "a\\b", "", "."):
            with self.subTest(name=name), self.assertRaises(ValueError):
                builder.check_member(name)
        self.assertEqual("opt/dsh/file", builder.check_member("./opt/dsh/file"))

    def test_excluded_tree_does_not_match_sibling_prefix(self):
        self.assertTrue(builder.tree_member("opt/dsh/module", "opt/dsh"))
        self.assertTrue(builder.tree_member("opt/dsh", "opt/dsh"))
        self.assertFalse(builder.tree_member("opt/dsh-app/local", "opt/dsh"))
        self.assertFalse(builder.tree_member("opt/dsh-other", "opt/dsh"))

    def test_official_launch_removes_only_known_base_patch(self):
        seed = {"launch": {"argv": ["proot", "NODE_OPTIONS=--dns-result-order=ipv4first", "/bin/sh", "-c",
            "echo $$ > /tmp/dsh-web.pid; exec /usr/local/bin/dsh web --patch /etc/dsh-app/dsh-web.patch.yml --host 127.0.0.1 --port {PORT} --no-open"], "env": {"KEEP": "yes"}}}
        launch = builder.launch(seed)
        self.assertNotIn("--patch", launch["argv"][-1])
        self.assertIn("--port {PORT}", launch["argv"][-1])
        self.assertIn("--patch", seed["launch"]["argv"][-1])
        self.assertEqual({"KEEP": "yes"}, launch["env"])

    def test_unknown_or_legacy_preload_launch_is_rejected(self):
        base = "exec /usr/local/bin/dsh web --patch /etc/dsh-app/dsh-web.patch.yml"
        for argv in (["dsh web"], [base, base], ["NODE_OPTIONS=--import=/old.mjs", base], [base+" --patch /leftover.yml"]):
            with self.subTest(argv=argv), self.assertRaises(ValueError):
                builder.launch({"launch": {"argv": argv}})

    def test_overlay_contains_no_legacy_code_or_patch(self):
        runtime = {"engineDistribution": "official-unmodified", "capabilities": {"legacyBridge": False, "enginePatches": False}}
        data = builder.overlay(runtime)
        self.assertEqual({"etc/dsh-app", "etc/dsh-app/runtime.json", "usr/local/bin/dsh"}, set(data))
        self.assertFalse(any("dsh-go" in name for name in data))
        shim = data["usr/local/bin/dsh"][2].decode()
        self.assertIn('"$@"', shim)
        self.assertIn("@deepseek-ai/dsh/lib/bin.js", shim)
        self.assertNotIn("--import", shim)
        self.assertNotIn("--patch", shim)
        self.assertEqual(runtime, json.loads(data["etc/dsh-app/runtime.json"][2]))


if __name__ == "__main__":
    unittest.main()
