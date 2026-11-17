import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Desktop CI prerequisite. The same probe runs again in the actual iOS App
// process; this deterministic provider test is not a real remote model call.
const bundle = resolve(process.argv[2]);
const directory = await mkdtemp(join(tmpdir(), 'dsh-ios-core-desktop-'));
try {
  const { runCoreProbe, bootBounded } = await import(pathToFileURL(join(bundle, 'core-probe.mjs')).href);
  const report = await runCoreProbe(directory, bundle);
  console.log(JSON.stringify({ environment: 'desktop-node-not-ios', ...report }));
  for (const key of ['coreBooted', 'servicesVerified', 'firstTurnStreamed', 'secondTurnHistoryVerified',
    'cancellationSettled', 'errorSettled', 'disposeVerified', 'badBaselineRejected']) {
    assert.equal(report[key], true, `DSH core gate failed: ${key}, stage=${report.stage}`);
  }
  assert.equal(report.ephemeral, true);
  assert.equal(report.engineReady, false);
  assert.equal(report.modelKind, 'offline-fixture');
  assert.equal(report.errorCode, null);
  assert.equal(report.stage, 'complete');
  const bad = await runCoreProbe('relative-directory', bundle);
  assert.equal(bad.coreBooted, false);
  assert.equal(bad.engineReady, false);
  assert.notEqual(bad.errorCode, null);
  // Ownership-only regression: a boot that resolves after its deadline must
  // release the late root, independently of AgentLoop's positive smoke test.
  const late = Promise.withResolvers();
  const disposed = Promise.withResolvers();
  await assert.rejects(bootBounded(() => late.promise), /IOS_CORE_TIMEOUT/);
  late.resolve({ fiber: { dispose: async () => disposed.resolve() } });
  let deadline;
  try {
    await Promise.race([disposed.promise, new Promise((_, reject) => {
      deadline = setTimeout(() => reject(new Error('Late Loader was not disposed')), 500);
    })]);
  } finally { clearTimeout(deadline); }
  console.log('IOS_CORE_LATE_BOOT_DISPOSAL_VERIFIED');
} finally { await rm(directory, { recursive: true, force: true }); }
