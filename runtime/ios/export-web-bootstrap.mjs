import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

// S1 is a cloud-built, offline bootstrap fixture, not the Web Host profile.
const { engine } = JSON.parse(await readFile(new URL('./requirements.json', import.meta.url)));
const VERSION = engine.version;
const PACKAGE = '@deepseek-ai/dsh-client-modules';
const RELEASE = { version: VERSION, commit: engine.webReleaseCommit };
const APP_BOOT = '@deepseek-ai/dsh-app-boot';
const FRONTEND = '@deepseek-ai/dsh-web-frontend';
const WEBSERVER = '@deepseek-ai/dsh-host-webserver';
const LOCK = fileURLToPath(new URL(`../../${engine.lockfile}`, import.meta.url));
const MIME = 'text/javascript; charset=utf-8';
const DOCUMENT_URL = 'dsh-app://bundle/';
const REVISION = /^[0-9a-f]{12}$/;

const sha256 = (bytes, encoding = 'hex') => createHash('sha256').update(bytes).digest(encoding);
const fileRecord = (path, bytes) => ({ path, bytes: bytes.length, sha256: sha256(bytes) });

async function seedFile(seed, path) {
  const filename = join(seed, path);
  assert((await lstat(filename)).isFile() && await realpath(filename) === filename,
    `expected regular locked seed file: ${path}`);
  return readFile(filename);
}

async function lockedPackage(seed, lock, name) {
  const directory = `node_modules/${name}`;
  const record = lock.packages[directory];
  assert.equal(record?.version, VERSION, `unexpected lock version: ${name}`);
  assert.equal(record.license, 'MIT', `unexpected locked license: ${name}`);
  assert.match(record.integrity, /^sha512-[A-Za-z0-9+/]{86}==$/);
  const installed = JSON.parse(await seedFile(seed, `${directory}/package.json`));
  assert.equal(installed.name, name);
  assert.equal(installed.version, record.version);
  assert.equal(installed.license, record.license);
  return { directory, record };
}

async function assertMissingOutput(output) {
  try {
    await lstat(output);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw error;
  }
  throw new Error('iOS Web bootstrap output already exists');
}

async function pinnedFile(seed, directory, path, expectedHash) {
  const bytes = await seedFile(seed, `${directory}/${path}`);
  assert.equal(sha256(bytes), expectedHash, `unexpected rc.3 ${directory}/${path}`);
  return bytes;
}

function checkSingleton(graph) {
  assert.deepEqual(graph.release, RELEASE);
  assert.match(graph.rev, REVISION);
  assert.equal(graph.entries.length, 1);
  assert.equal(graph.batches.length, 1);
  const [entry] = graph.entries;
  const [batch] = graph.batches;
  const reference = rev => `plugins/??${PACKAGE}/client.js&rev=${rev}`;
  assert.match(entry.rev, REVISION);
  assert.match(batch.rev, REVISION);
  assert.notEqual(batch.rev, entry.rev, 'entry and parser combo revisions must be distinct');
  assert.deepEqual(entry, { id: PACKAGE, url: reference(entry.rev), rev: entry.rev, inject: [], immediately: true });
  assert.deepEqual(batch, { phase: 'bootstrap', url: reference(batch.rev), rev: batch.rev, entries: [PACKAGE] });
  return { entry, batch };
}

async function getBundle(registry, reference, path, stockBundle) {
  const request = new Request(new URL(reference, DOCUMENT_URL));
  const url = new URL(request.url);
  const route = `${url.pathname}${url.search}`;
  assert.equal(url.protocol, 'dsh-app:');
  assert.equal(url.host, 'bundle');
  assert.equal(route, `/${reference}`, 'combo URL must retain both question marks and exact revision');
  const response = await registry.fetchBundle(request);
  assert.equal(response.status, 200, `registry did not serve ${route}`);
  assert.equal(response.headers.get('content-type'), MIME);
  assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable');
  const bytes = Buffer.from(await response.arrayBuffer());

  // rc.3 removes the package-local map comment, adds a separator and stamps a combo-relative map URL.
  // This comparison authenticates executable bytes; only the registry's response is exported.
  const terminalMap = '\n//# sourceMappingURL=client.js.map';
  const source = stockBundle.toString('utf8');
  assert(source.endsWith(terminalMap));
  const mapReference = url.search.replace('/client.js&rev=', '/client.js.map&rev=');
  const expected = Buffer.from(`${source.slice(0, -terminalMap.length)}\n;\n//# sourceMappingURL=${mapReference}\n`);
  assert(bytes.equals(expected), `registry bundle bytes differ from the rc.3 client artifact: ${route}`);
  return { file: { url: route, contentType: MIME, ...fileRecord(path, bytes) }, bytes };
}

/** Export only rc.3 module bootstrap assets; no server, connection, profile, or app UI is mounted. */
export async function exportWebBootstrap(seedPath, outputPath) {
  const seed = await realpath(resolve(seedPath));
  const requestedOutput = resolve(outputPath);
  const output = join(await realpath(dirname(requestedOutput)), basename(requestedOutput));
  const fromSeed = relative(seed, output);
  assert(fromSeed && (isAbsolute(fromSeed) || fromSeed === '..' || fromSeed.startsWith(`..${sep}`)),
    'bootstrap staging must not write into the locked seed');
  await assertMissingOutput(output);
  const lockBytes = await readFile(LOCK);
  assert((await seedFile(seed, 'package-lock.json')).equals(lockBytes), 'installed seed lock does not match the rc.3 lock');
  const lock = JSON.parse(lockBytes);
  const [appBoot, modules, webserver, frontend] = await Promise.all(
    [APP_BOOT, PACKAGE, WEBSERVER, FRONTEND].map(name => lockedPackage(seed, lock, name)),
  );
  const bootPath = `${appBoot.directory}/lib/index.js`;
  const registryPath = `${modules.directory}/lib/index.js`;
  const rendererPath = `${webserver.directory}/lib/index.js`;
  const clientPath = `${modules.directory}/lib/client.js`;
  const [, , , stockIndex, stockBundle, license] = await Promise.all([
    pinnedFile(seed, appBoot.directory, 'lib/index.js', 'a8d2138bb274bd982079df14a615f6c0d5d7589c9faeae81973128a72293b6de'),
    pinnedFile(seed, modules.directory, 'lib/index.js', 'a1056961926b9524a3940db3fb1cd84b5880eed54f06b8efaafa7c120b0d7602'),
    pinnedFile(seed, webserver.directory, 'lib/index.js', '81a85ab619d8977e090e23124fd4e0e135c944c99b8b199eadea615532f2b2e3'),
    pinnedFile(seed, frontend.directory, 'dist/index.html', '271698ef62d4cc9a10a5f0aa28d0f4f6cd5e16fe04734908c3eab477a8da0ec1'),
    pinnedFile(seed, modules.directory, 'lib/client.js', 'fc491b97b5d923446faf9ebff238dba6d1f8a55b03e8bf71bea90355ee33bec6'),
    seedFile(seed, `${modules.directory}/LICENSE`),
  ]);

  const work = await mkdtemp(join(dirname(output), '.ios-web-bootstrap-'));
  let ctx;
  try {
    const config = join(work, 'cordis.json');
    // Keep even Cordis' fallback resolution helper inside the private config scope.
    await writeFile(join(work, 'package.json'), '{}\n', { flag: 'wx' });
    const name = pathToFileURL(join(seed, registryPath)).href;
    await writeFile(config, JSON.stringify([{ id: 'modules', name }]), { flag: 'wx' });
    const [{ boot }, { ClientModuleRegistry, bootInjections }, { renderIndexInjections }] = await Promise.all([
      import(pathToFileURL(join(seed, bootPath)).href),
      import(name),
      import(pathToFileURL(join(seed, rendererPath)).href),
    ]);
    ctx = await boot('dsh-ios-web-bootstrap', config, []);
    const loader = ctx.get('loader');
    const row = loader?.resolve('include')?.subtree?.resolve('modules');
    const registry = ctx.get('clientModules');
    assert.equal(row?.options.name, name);
    assert.equal(row.fiber?.state, 2, 'official modules row did not activate');
    assert(registry instanceof ClientModuleRegistry, 'official ClientModuleRegistry is required');
    assert.equal(ctx.get('webServer'), undefined, 'S1 must not mount the HTTP server');
    assert.equal(registry.clientPath(PACKAGE), join(seed, clientPath));

    const graph = registry.graph();
    const { entry, batch } = checkSingleton(graph);
    const injections = bootInjections(graph);
    const emitted = [];
    ctx.emit('webserver/index-inject', emitted);
    assert.deepEqual(emitted, injections, 'registry must publish the same ordered index rows');
    assert.deepEqual(injections.map(row => row.kind), ['script', 'script-src', 'global']);
    assert.equal(injections[0].placement, 'head');
    assert.deepEqual(injections[1], { kind: 'script-src', placement: 'head', src: batch.url });
    assert.deepEqual(injections[2], { kind: 'global', name: '__DSH_BOOT__', value: graph });

    const combo = await getBundle(registry, batch.url, 'bootstrap-combo.js', stockBundle);
    const fallback = await getBundle(registry, entry.url, 'bootstrap-entry.js', stockBundle);
    assert.notEqual(combo.file.sha256, fallback.file.sha256, 'map trailers must carry their distinct revisions');
    const html = renderIndexInjections(stockIndex.toString('utf8'), injections);
    // Quote each returned hash in the native scheme response's CSP. This includes the readiness tail.
    const inlineScripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(([, text]) => text);
    assert.equal(inlineScripts.length, 3);
    const htmlBytes = Buffer.from(html, 'utf8');
    const manifest = {
      schemaVersion: 1, package: PACKAGE, version: VERSION,
      integrity: modules.record.integrity, sourceLockSHA256: sha256(lockBytes),
      stockIndexSHA256: sha256(stockIndex), clientBundleSHA256: sha256(stockBundle),
      graph, injections, cspScriptHashes: inlineScripts.map(text => `sha256-${sha256(text, 'base64')}`),
      index: fileRecord('index.html', htmlBytes),
      resources: [combo.file, fallback.file], license: fileRecord('LICENSE', license),
    };

    await ctx.fiber.dispose();
    ctx = undefined;
    const stage = join(work, 'stage');
    await mkdir(stage);
    await Promise.all([
      writeFile(join(stage, manifest.index.path), htmlBytes),
      writeFile(join(stage, combo.file.path), combo.bytes),
      writeFile(join(stage, fallback.file.path), fallback.bytes),
      writeFile(join(stage, manifest.license.path), license),
      writeFile(join(stage, 'distribution-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`),
    ]);
    await assertMissingOutput(output);
    await rename(stage, output);
    return manifest;
  } finally {
    try { await ctx?.fiber.dispose(); }
    finally { await rm(work, { recursive: true, force: true }); }
  }
}

if (import.meta.main) {
  const { values } = parseArgs({ options: { seed: { type: 'string' }, output: { type: 'string' } } });
  if (!values.seed || !values.output) throw new Error('usage: node export-web-bootstrap.mjs --seed DIRECTORY --output NEW_DIRECTORY');
  const manifest = await exportWebBootstrap(values.seed, values.output);
  console.log(JSON.stringify({ phase: 'official-module-bootstrap-assets', version: manifest.version,
    commit: manifest.graph.release.commit, resources: manifest.resources.length }));
}
