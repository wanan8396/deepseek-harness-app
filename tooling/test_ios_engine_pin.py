from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from ios_engine_pin import ROOT, read_pin, validate_lock


class OfficialIosVersionTests(unittest.TestCase):
    def test_checked_in_pin_resolves_to_official_npm_lock(self):
        self.assertEqual(read_pin(), validate_lock())

    def test_new_version_has_one_pin_and_cross_version_seed_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            requirements = deepcopy(json.loads((ROOT / 'runtime/ios/requirements.json').read_bytes()))
            version = '9.7.2-rc.4'
            package = '@deepseek-ai/dsh'
            relative = f'runtime/locks/dsh-{version}/package-lock.json'
            requirements['engine'].update(version=version, lockfile=relative, webReleaseCommit='deadbee')
            (root / 'runtime/ios').mkdir(parents=True)
            (root / 'runtime/ios/requirements.json').write_text(json.dumps(requirements), encoding='utf-8')
            lockfile = root / relative
            lockfile.parent.mkdir(parents=True)
            dependency = {package: version}
            payload = {'packages': {'': {'dependencies': dependency}, 'node_modules/' + package: {
                'version': version, 'resolved': f'https://registry.npmjs.org/{package}/-/dsh-{version}.tgz',
                'integrity': 'sha512-' + 'A' * 86 + '==', 'engines': {'node': requirements['engine']['node']},
            }}}
            lockfile.write_text(json.dumps(payload), encoding='utf-8')
            seed = lockfile.with_name('package.json')
            seed.write_text(json.dumps({'dependencies': dependency}), encoding='utf-8')
            self.assertEqual(validate_lock(root)['version'], version)
            seed.write_text(json.dumps({'dependencies': {package: '9.7.1'}}), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'ENGINE_SEED_MANIFEST_MISMATCH'):
                validate_lock(root)
