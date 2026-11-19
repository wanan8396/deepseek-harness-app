#!/usr/bin/env python3
"""The official builder preserves the native installer's narrow upgrade contract."""
import copy
import importlib.util
from pathlib import Path
import re
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('official_builder', HERE / 'build-official-runtime.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

# Independent installer oracle: never replace the user's Linux/Python/home trees.
ENGINE_PATHS = [
    'opt/dsh', 'opt/node', 'etc/dsh-app',
    'etc/profile.d/dsh-app.sh', 'usr/local/lib/node_modules/pnpm',
    'usr/local/bin/dsh', 'usr/local/bin/node', 'usr/local/bin/npm', 'usr/local/bin/npx',
    'usr/local/bin/corepack', 'usr/local/bin/pnpm', 'usr/local/bin/pnpx', 'usr/local/bin/pn', 'usr/local/bin/pnx',
]


class RuntimeUpgradePackaging(unittest.TestCase):
    def seed(self):
        return {
            'abi': 'arm64-v8a', 'nodeVersion': '24', 'pnpmVersion': '11',
            'ubuntuVersion': '24.04.5', 'prootVersion': '5',
            'upgrade': {'schema': 1, 'baseId': 'a' * 64, 'ubuntuVersion': '24.04.5',
                        'paths': list(ENGINE_PATHS)},
        }

    def describe(self, seed):
        identity = {'name': '@deepseek-ai/dsh', 'version': '0.2.2-rc.5',
                    'registry': 'https://registry.npmjs.org/', 'lockSha256': 'b' * 64}
        with patch.object(builder, 'official_identity', return_value=identity):
            return builder.describe_official_manifest(seed, Path('unused-prefix'))

    def test_android_owns_only_the_exact_non_overlapping_engine_paths(self):
        source = HERE.parent / 'app/android/app/src/main/kotlin/app/dsh/runtime/EngineUpgrade.kt'
        declaration = source.read_text(encoding='utf-8').split('internal val ENGINE_PATHS = listOf(', 1)[1].split('\n)', 1)[0]
        self.assertEqual(ENGINE_PATHS, re.findall(r'"([^"]+)"', declaration))
        for path in ENGINE_PATHS:
            self.assertNotIn(path, ('usr', 'usr/local', 'usr/local/bin', 'opt/python', 'var/lib/dpkg', 'root'))
            self.assertNotIn('..', path.split('/'))
            self.assertFalse(any(other.startswith(path + '/') for other in ENGINE_PATHS if other != path))

    def test_official_manifest_preserves_seed_system_identity_and_path_list(self):
        seed = self.seed()
        before = copy.deepcopy(seed)
        runtime = self.describe(seed)
        self.assertEqual(before, seed)
        self.assertEqual(before['upgrade'], runtime['upgrade'])
        self.assertEqual(ENGINE_PATHS, runtime['upgrade']['paths'])
        seed['nodeVersion'] = 'new-engine-node'
        seed['pnpmVersion'] = 'new-engine-pnpm'
        changed = self.describe(seed)
        self.assertEqual(runtime['upgrade'], changed['upgrade'])
        self.assertNotEqual(runtime['runtimeVersion'], changed['runtimeVersion'])
        runtime['upgrade']['paths'].append('mutation-only-in-return-value')
        self.assertEqual(ENGINE_PATHS, seed['upgrade']['paths'])

    def test_seed_only_slots_are_not_forwarded_to_current_upgrade(self):
        seed = self.seed()
        seed['upgrade']['paths'].append('opt/retired-seed-slot')
        runtime = self.describe(seed)
        self.assertEqual(ENGINE_PATHS, runtime['upgrade']['paths'])
        self.assertEqual(seed['upgrade']['baseId'], runtime['upgrade']['baseId'])
        self.assertEqual('opt/retired-seed-slot', seed['upgrade']['paths'][-1])

    def test_official_manifest_requires_a_known_seed_upgrade_contract(self):
        for descriptor in (None, {}, {'schema': 2, 'paths': ENGINE_PATHS},
                           {'schema': 1, 'paths': ['opt/dsh', 'opt/node', 'opt/python', 'etc/dsh-app']}):
            with self.subTest(descriptor=descriptor):
                seed = self.seed()
                seed['upgrade'] = descriptor
                with self.assertRaises(ValueError):
                    self.describe(seed)


if __name__ == '__main__':
    unittest.main(verbosity=2)
