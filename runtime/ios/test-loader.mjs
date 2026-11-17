import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// This is a desktop CI gate only. iOS runs the same exported probe separately
// inside node_start; desktop success is not substituted for that result.
const bundle = resolve(process.argv[2]);
const directory = await mkdtemp(join(tmpdir(), 'dsh-ios-loader-desktop-'));
try {
  const { runLoaderProbe } = await import(pathToFileURL(join(bundle, 'loader-probe.mjs')).href);
  const report = await runLoaderProbe(directory, bundle);
  console.log(JSON.stringify({ environment: 'desktop-node-not-ios', ...report }));
  for (const key of ['dshLoaderBooted', 'serviceVerified', 'disposeVerified', 'badBaselineRejected']) {
    assert.equal(report[key], true, `DSH Loader gate failed: ${key}, stage=${report.stage}`);
  }
  assert.equal(report.engineReady, false);
  assert.equal(report.errorCode, null);
  assert.equal(report.stage, 'complete');
  const bad = await runLoaderProbe('relative-directory', bundle);
  assert.equal(bad.dshLoaderBooted, false);
  assert.equal(bad.engineReady, false);
  assert.notEqual(bad.errorCode, null);
} finally {
  await rm(directory, { recursive: true, force: true });
}
