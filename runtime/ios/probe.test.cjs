'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { satisfiesFloor, compatibility, atomicReport, collectReport } = require('./probe.cjs');
const requirements = require('./requirements.json');

test('version floor rejects Node18, early24, malformed and prerelease versions', () => {
  for (const version of ['18.20.4', '22.9.0', '24.5.0', '24.8.99', '24.22.1-rc.1', '24', '', 'token']) {
    assert.equal(satisfiesFloor(version, '>=24.9.0'), false, version);
  }
  for (const version of ['24.9.0', 'v24.22.1', '26.0.0']) {
    assert.equal(satisfiesFloor(version, '>=24.9.0'), true, version);
  }
  assert.equal(satisfiesFloor('24.22.1', '^24'), false);
});

test('version success never hides a missing capability', () => {
  assert.deepEqual(compatibility('24.22.1', '>=24.9.0', { sqlite: false, intl: true }), {
    versionCompatible: true, runtimeCompatible: false, missing: ['sqlite'],
  });
  assert.equal(compatibility('18.20.4', '>=24.9.0', { sqlite: true }).runtimeCompatible, false);
  assert.equal(compatibility('24.22.1', '>=24.9.0', { sqlite: true }).runtimeCompatible, true);
  assert.equal(compatibility('24.22.1', '>=24.9.0', { sqlite: undefined }).runtimeCompatible, false);
});

test('requirements floor stays equal to the checked-in official DSH lock', () => {
  const lock = require('../../' + requirements.engine.lockfile);
  const locked = lock.packages['node_modules/' + requirements.engine.package];
  assert.equal(requirements.engine.version, locked.version);
  assert.equal(requirements.engine.node, locked.engines.node);
});

test('report uses atomic private files and never reports DSH ready', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-ios-probe-test-'));
  try {
    const destination = path.join(directory, 'report.json');
    const report = await collectReport(destination);
    assert.equal(report.schemaVersion, 1);
    assert.equal(report.phase, 'probeReady');
    assert.equal(report.engineReady, false);
    assert.equal(report.requiredNode, requirements.engine.node);
    assert.equal(report.versions.node, process.versions.node);
    assert.equal(report.capabilities.filesystemWriteRead, true);
    assert.equal(report.capabilities.importMetaMain, true);
    assert.equal(typeof report.runtimeCompatible, 'boolean');
    assert.equal(report.reportCompatible, report.runtimeCompatible);
    assert.ok(report.unverified.includes('dsh-profile-startup'));
    const serialized = JSON.stringify(report);
    assert.equal(serialized.includes(directory), false);
    atomicReport(destination, report);
    assert.deepEqual(JSON.parse(fs.readFileSync(destination, 'utf8')), report);
    assert.deepEqual(fs.readdirSync(directory), ['report.json']);
    if (process.platform !== 'win32') assert.equal(fs.statSync(destination).mode & 0o777, 0o600);
    atomicReport(destination, { phase: 'probeFailed', engineReady: false });
    assert.equal(JSON.parse(fs.readFileSync(destination, 'utf8')).phase, 'probeFailed');
    assert.throws(() => atomicReport('relative.json', report), /REPORT_PATH_INVALID/);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
