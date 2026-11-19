"""Unit checks for the deterministic Flutter staging assembler."""

from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

import assemble_ios_flutter as assemble


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


class PreserveTest(unittest.TestCase):
    def test_target_owned_surfaces_are_never_replaced(self) -> None:
        for path in ('app/lib/app.dart', 'app/lib/main.dart', 'app/lib/ui/theme/theme.dart',
                     'app/lib/ui/web/startup_cover.dart', 'app/lib/ui/ios/ios_official_carrier.dart',
                     'app/lib/ui/shell/root_gate.dart'):
            self.assertTrue(assemble.preserved(path), path)

    def test_chat_and_drawer_come_from_the_donor(self) -> None:
        for path in ('app/lib/ui/chat/chat_screen.dart', 'app/lib/ui/shell/sessions_drawer.dart',
                     'app/lib/ui/shell/home_shell.dart', 'app/lib/ui/chat/widgets/whale_tail.dart'):
            self.assertFalse(assemble.preserved(path), path)


class PatchTest(unittest.TestCase):
    def stage(self, root: Path, *, home: str | None = None,
              cwd: str = 'cwd: conn.isLocal ? localWorkspaceDir : conn.workingDirectory,') -> Path:
        write(root / 'app/lib/main.dart', (
            "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
            "\n"
            "import 'app.dart';\n"
            "\n"
            "runApp(const ProviderScope(child: DshApp()));\n"
        ))
        write(root / 'app/lib/app.dart',
              'home: widget.home ?? %s,\n' % (home or 'const RootGate()'))
        write(root / 'app/lib/state/sessions_state.dart', 'final created = await createSessionInWorkspace(\n  %s\n);\n' % cwd)
        return root

    def test_patch_hands_the_entry_its_own_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = self.stage(Path(temp))
            patched = assemble.patch_staged(root)
            self.assertEqual(patched, ['app/lib/main.dart:entry',
                                       'app/lib/state/sessions_state.dart:cwd'])
            main = (root / 'app/lib/main.dart').read_text(encoding='utf-8')
            self.assertIn("import 'ui/ios/ios_flutter_entry.dart';", main)
            self.assertIn('runApp(const IosFlutterEntry());', main)
            self.assertNotIn('flutter_riverpod', main)
            self.assertNotIn("import 'app.dart';", main)
            self.assertIn('home: widget.home ?? const RootGate(),',
                          (root / 'app/lib/app.dart').read_text(encoding='utf-8'))
            self.assertIn('cwd: conn.isLocal ? null : conn.workingDirectory,',
                          (root / 'app/lib/state/sessions_state.dart').read_text(encoding='utf-8'))

    def test_unknown_site_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = self.stage(Path(temp), cwd='cwd: somewhereElse,')
            with self.assertRaises(assemble.AssemblyError):
                assemble.patch_staged(root)

    def test_partial_entry_rewrite_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = self.stage(Path(temp))
            write(root / 'app/lib/main.dart',
                  "import 'app.dart';\n\nrunApp(const ProviderScope(child: DshApp()));\n")
            with self.assertRaises(assemble.AssemblyError):
                assemble.patch_staged(root)


class TemplateTest(unittest.TestCase):
    def test_missing_template_stops_the_stage(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(assemble.AssemblyError):
                assemble.apply_templates(root / 'out', root, (('home_shell.dart', 'app/lib/x.dart'),), 'source')

    def test_template_bytes_are_staged_verbatim(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            write(root / 'app/lib/ui/ios/donor/home_shell.dart.template', '// staged home\n')
            applied = assemble.apply_templates(root / 'out', root,
                                              (('home_shell.dart', 'app/lib/ui/shell/home_shell.dart'),), 'source')
            self.assertEqual(applied, ['app/lib/ui/shell/home_shell.dart'])
            self.assertEqual((root / 'out/app/lib/ui/shell/home_shell.dart').read_text(encoding='utf-8'),
                             '// staged home\n')

    def test_output_must_be_new(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'out').mkdir()
            write(root / 'out/existing.txt', 'x')
            with self.assertRaises(assemble.AssemblyError):
                assemble.assemble(root, root / 'out', root / 'plan.json', root)


if __name__ == '__main__':
    unittest.main()
