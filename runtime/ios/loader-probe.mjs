import { randomBytes } from 'node:crypto';
import { isAbsolute, join } from 'node:path';
import { lstat, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

function containsExpectedFailure(error, seen = new Set()) {
  if (!error || typeof error !== 'object' || seen.has(error)) return false;
  seen.add(error);
  if (error.message === 'IOS_LOADER_FIXTURE_EXPECTED_FAILURE') return true;
  return containsExpectedFailure(error.cause, seen)
    || (error instanceof AggregateError && error.errors.some((item) => containsExpectedFailure(item, seen)));
}

async function markerMatches(filename, challenge, property) {
  try {
    const value = JSON.parse(await readFile(filename, 'utf8'));
    return value.challenge === challenge && value[property] === true;
  } catch { return false; }
}

/** Run real official Loader lifecycle checks, not a DSH application boot. */
export async function runLoaderProbe(privateDir, bundleDir, expectedVersion) {
  const report = { dshLoaderBooted: false, serviceVerified: false,
    disposeVerified: false, badBaselineRejected: false, engineReady: false,
    stage: 'input', errorCode: null };
  let work;
  let good;
  let bad;
  try {
    if (!isAbsolute(privateDir) || !isAbsolute(bundleDir)) throw new Error('IOS_LOADER_INPUT_INVALID');
    for (const directory of [privateDir, bundleDir]) {
      const info = await lstat(directory);
      if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('IOS_LOADER_INPUT_INVALID');
    }
    const bundle = await realpath(bundleDir);
    const metadata = JSON.parse(await readFile(join(bundle, 'distribution-manifest.json'), 'utf8'));
    if (metadata.distribution !== 'ios-adapted-loader-probe' || metadata.engineVersion !== expectedVersion) {
      throw new Error('IOS_LOADER_DISTRIBUTION_INVALID');
    }
    report.stage = 'import';
    const { boot, StartupError } = await import(pathToFileURL(join(bundle,
      'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js')).href);
    const fixture = pathToFileURL(join(bundle, 'loader-fixture.mjs')).href;
    const challenge = randomBytes(32).toString('hex');
    work = await mkdtemp(join(privateDir, '.dsh-loader-'));
    const positive = join(work, 'positive');
    const negative = join(work, 'negative');
    await mkdir(positive, { mode: 0o700 });
    await mkdir(negative, { mode: 0o700 });
    const config = join(positive, 'cordis.json');
    await writeFile(config, JSON.stringify([{ id: 'ios-loader-fixture', name: fixture,
      config: { directory: positive, challenge } }]), { flag: 'wx', mode: 0o600 });
    report.stage = 'boot';
    good = await boot('dsh-ios-loader', config, [], undefined);
    report.stage = 'entry';
    const entry = good.get('loader')?.resolve('include')?.subtree?.resolve('ios-loader-fixture');
    report.dshLoaderBooted = good.fiber.state === 2 && entry?.fiber?.state === 2;
    if (!report.dshLoaderBooted) throw new Error('IOS_LOADER_ENTRY_INACTIVE');
    report.stage = 'service';
    const service = good.get('iosLoaderProbe');
    report.serviceVerified = service?.challenge === challenge && service?.activated === true
      && await markerMatches(join(positive, 'activated.json'), challenge, 'activated');
    if (!report.serviceVerified) throw new Error('IOS_LOADER_SERVICE_INVALID');
    report.stage = 'dispose';
    await good.fiber.dispose();
    good = undefined;
    report.disposeVerified = await markerMatches(join(positive, 'disposed.json'), challenge, 'disposed');
    if (!report.disposeVerified) throw new Error('IOS_LOADER_DISPOSE_INVALID');

    // agent-loop is an official required startup id. A failing optional row
    // would only warn and would not independently test the boot rejection gate.
    const badConfig = join(negative, 'cordis.json');
    await writeFile(badConfig, JSON.stringify([{ id: 'agent-loop', name: fixture,
      config: { directory: negative, challenge, fail: true } }]), { flag: 'wx', mode: 0o600 });
    report.stage = 'negative';
    try {
      bad = await boot('dsh-ios-loader-bad-baseline', badConfig, [], undefined);
    } catch (error) {
      report.badBaselineRejected = error instanceof StartupError
        && error.entries.some(({ id, required, outcome }) => id === 'agent-loop'
          && required === true && outcome.kind === 'failed')
        && containsExpectedFailure(error)
        && await markerMatches(join(negative, 'failure-entered.json'), challenge, 'failureEntered');
    }
    if (!report.badBaselineRejected) throw new Error('IOS_LOADER_BAD_BASELINE_NOT_REJECTED');
    report.stage = 'complete';
  } catch {
    // Return only the fixed stage/code; never expose error text, paths or environment.
    report.errorCode = 'IOS_DSH_LOADER_PROBE_FAILED';
  } finally {
    for (const context of [bad, good]) {
      try { await context?.fiber.dispose(); }
      catch { report.disposeVerified = false; report.errorCode = 'IOS_DSH_LOADER_CLEANUP_FAILED'; report.stage = 'cleanup'; }
    }
    if (work) {
      try { await rm(work, { recursive: true, force: true }); }
      catch { report.disposeVerified = false; report.errorCode = 'IOS_DSH_LOADER_CLEANUP_FAILED'; report.stage = 'cleanup'; }
    }
  }
  return report;
}
