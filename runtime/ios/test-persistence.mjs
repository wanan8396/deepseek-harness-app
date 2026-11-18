import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// GitHub desktop prerequisite only. The identical probe must also execute in
// the iOS App; orderly root close/reopen is not process death or App-kill proof.
const bundle = resolve(process.argv[2]);
const directory = await mkdtemp(join(tmpdir(), 'dsh-ios-persistence-desktop-'));
const checks = ['storageBooted', 'writerExclusionVerified', 'readWhileOwnedVerified',
  'atomicAppendVerified', 'flushVerified', 'coldResumeVerified', 'disposeVerified', 'badBaselineRejected'];
const reportKeys = [...checks, 'engineReady', 'modelKind', 'persistentStore', 'stage', 'errorCode'].sort();
const assertBoundary = (report) => {
  assert.deepEqual(Object.keys(report).sort(), reportKeys, 'IOS_PERSISTENCE_REPORT_NOT_WHITELISTED');
  for (const key of checks) assert.equal(typeof report[key], 'boolean', 'IOS_PERSISTENCE_CHECK_NOT_BOOLEAN');
  assert.equal(report.engineReady, false, 'IOS_PERSISTENCE_USER_ENGINE_READY');
  assert.equal(report.modelKind, 'offline-fixture');
  assert.equal(report.persistentStore, true);
  assert.equal(Object.hasOwn(report, 'ephemeral'), false, 'IOS_PERSISTENCE_EPHEMERAL_CONTRACT_CHANGED');
};
try {
  const manifest = JSON.parse(await readFile(join(bundle, 'distribution-manifest.json'), 'utf8'));
  assert.equal(manifest.distribution, 'ios-adapted-persistence-probe');
  assert.equal(manifest.phase, 'persistence');
  assert.equal(manifest.engineReady, false);
  assert.equal(manifest.engineVersion, '0.2.2-rc.3');
  const { runPersistenceProbe, bootPersistenceBounded } = await import(pathToFileURL(join(bundle, 'persistence-probe.mjs')).href);
  const report = await runPersistenceProbe(directory, bundle);
  console.log(JSON.stringify({ environment: 'desktop-node-not-ios', ...report }));
  assertBoundary(report);
  for (const key of checks) assert.equal(report[key], true, `IOS_PERSISTENCE_GATE_FAILED:${key}:${report.stage}`);
  assert.equal(report.errorCode, null);
  assert.equal(report.stage, 'complete');
  console.log('IOS_PERSISTENCE_CLOSE_REOPEN_NOT_APP_KILL_VERIFIED');

  // Invalid input must remain red, including checks that previously passed.
  // Neither a real database nor a model fallback may be created for this call.
  const invalid = await runPersistenceProbe('relative-directory', bundle);
  assertBoundary(invalid);
  for (const key of checks) assert.equal(invalid[key], false, `IOS_PERSISTENCE_INVALID_INPUT_GREEN:${key}`);
  assert.equal(invalid.stage, 'input');
  assert.equal(invalid.errorCode, 'IOS_PERSISTENCE_INPUT_INVALID');

  // This oracle owns its synthetic late root; it does not use provider helpers
  // or a successful AgentLoop to infer deadline resource retirement.
  const late = Promise.withResolvers();
  const disposed = Promise.withResolvers();
  let count = 0;
  await assert.rejects(bootPersistenceBounded(() => late.promise, [], 10), /IOS_PERSISTENCE_TIMEOUT/);
  late.resolve({ fiber: { dispose: async () => { count += 1; disposed.resolve(); } } });
  let timer;
  try {
    await Promise.race([disposed.promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('IOS_PERSISTENCE_LATE_ROOT_LEAKED')), 500);
    })]);
  } finally { clearTimeout(timer); }
  assert.equal(count, 1, 'IOS_PERSISTENCE_LATE_ROOT_DISPOSE_COUNT');
  console.log('IOS_PERSISTENCE_LATE_BOOT_DISPOSAL_VERIFIED');
} finally { await rm(directory, { recursive: true, force: true }); }
