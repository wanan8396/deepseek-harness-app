import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createContext, runInContext } from 'node:vm';
import { exportWebBootstrap } from './export-web-bootstrap.mjs';

const MODULES = '@deepseek-ai/dsh-client-modules';
const { engine } = JSON.parse(await readFile(new URL('./requirements.json', import.meta.url)));
const RELEASE = { version: engine.version, commit: engine.webReleaseCommit };
const LOCK = new URL(`../../${engine.lockfile}`, import.meta.url);
const sha = (bytes, encoding = 'hex') => createHash('sha256').update(bytes).digest(encoding);

async function checkedFile(directory, record, expectedPath) {
  assert.equal(record.path, expectedPath);
  const bytes = await readFile(join(directory, expectedPath));
  assert.equal(bytes.length, record.bytes);
  assert.equal(sha(bytes), record.sha256);
  return bytes;
}

async function guardedReexport(seed, directory, expected) {
  const temporary = await mkdtemp(join(tmpdir(), 'dsh-ios-web-bootstrap-test-'));
  const output = join(temporary, 'stage');
  const listen = Server.prototype.listen;
  const connect = Socket.prototype.connect;
  const nativeFetch = globalThis.fetch;
  const attempts = [];
  const deny = kind => () => {
    attempts.push(kind);
    throw new Error(`offline bootstrap attempted ${kind}`);
  };
  try {
    Server.prototype.listen = deny('listen');
    Socket.prototype.connect = deny('connect');
    globalThis.fetch = deny('fetch');
    assert.throws(() => new Server().listen(0), /attempted listen/);
    assert.throws(() => new Socket().connect(1), /attempted connect/);
    assert.throws(() => fetch('https://dsh.invalid'), /attempted fetch/);
    assert.deepEqual(attempts.splice(0), ['listen', 'connect', 'fetch']);
    assert.deepEqual(await exportWebBootstrap(seed, output), expected);
    await assert.rejects(() => exportWebBootstrap(seed, output), /output already exists/);
    assert.deepEqual(attempts, [], 'the official Loader, registry and renderer must not use a transport');
    const files = await readdir(directory);
    assert.deepEqual((await readdir(output)).sort(), files.sort());
    for (const file of files) {
      assert((await readFile(join(output, file))).equals(await readFile(join(directory, file))), `re-export differs: ${file}`);
    }
  } finally {
    Server.prototype.listen = listen;
    Socket.prototype.connect = connect;
    globalThis.fetch = nativeFetch;
    await rm(temporary, { recursive: true, force: true });
  }
}

function realm() {
  const context = createContext({});
  runInContext('globalThis.window = globalThis', context);
  return context;
}

function runClassic(context, text, filename) {
  return runInContext(text, context, { filename, timeout: 1000 });
}

function createLoader(context) {
  return runClassic(context, '__ModuleLoader__.create({ boot: __DSH_BOOT__, staticModules: {} })', 's1-consumer');
}

// Independent consumer of what was staged; no mock ModuleLoader or API Host.
async function validateStaged(seed, directory) {
  const manifest = JSON.parse(await readFile(join(directory, 'distribution-manifest.json'), 'utf8'));
  const lock = await readFile(LOCK);
  const stock = await readFile(join(seed, 'node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html'));
  const packageRoot = join(seed, 'node_modules', MODULES);
  const client = await readFile(join(packageRoot, 'lib/client.js'));
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.package, MODULES);
  assert.equal(manifest.version, RELEASE.version);
  assert.equal(manifest.sourceLockSHA256, sha(lock));
  assert.equal(manifest.integrity, JSON.parse(lock).packages[`node_modules/${MODULES}`].integrity);
  assert.equal(manifest.stockIndexSHA256, '271698ef62d4cc9a10a5f0aa28d0f4f6cd5e16fe04734908c3eab477a8da0ec1');
  assert.equal(sha(stock), manifest.stockIndexSHA256);
  assert.equal(manifest.clientBundleSHA256, 'fc491b97b5d923446faf9ebff238dba6d1f8a55b03e8bf71bea90355ee33bec6');
  assert.equal(sha(client), manifest.clientBundleSHA256);
  assert((await checkedFile(directory, manifest.license, 'LICENSE')).equals(await readFile(join(packageRoot, 'LICENSE'))));

  const { graph, injections, resources } = manifest;
  const { rev, entries, batches } = graph;
  const combo = /^plugins\/\?\?@deepseek-ai\/dsh-client-modules\/client\.js&rev=([a-f0-9]{12})$/;
  assert.deepEqual(Object.keys(graph).sort(), ['batches', 'entries', 'release', 'rev']);
  assert.deepEqual(graph.release, RELEASE);
  assert.equal(rev, createHash('sha1').update(JSON.stringify({ entries, batches })).digest('hex').slice(0, 12));
  assert.equal(entries.length, 1);
  assert.equal(batches.length, 1);
  const [entry] = entries;
  const [batch] = batches;
  assert.match(entry.url, combo);
  assert.match(batch.url, combo);
  assert.notEqual(entry.url, batch.url);
  assert.deepEqual(entry, { id: MODULES, url: entry.url, rev: combo.exec(entry.url)[1], inject: [], immediately: true });
  assert.deepEqual(batch, { phase: 'bootstrap', url: batch.url, rev: combo.exec(batch.url)[1], entries: [MODULES] });
  assert.equal(resources.length, 2);

  const bodies = new Map();
  const [parserResource, fallbackResource] = resources;
  for (const [resource, descriptor, path] of [
    [parserResource, batch, 'bootstrap-combo.js'], [fallbackResource, entry, 'bootstrap-entry.js'],
  ]) {
    assert.equal(resource.url, `/${descriptor.url}`);
    assert.equal(resource.contentType, 'text/javascript; charset=utf-8');
    const bytes = await checkedFile(directory, resource, path);
    const text = bytes.toString('utf8');
    const map = /^\/\/# sourceMappingURL=(.+)\n$/;
    const start = text.lastIndexOf('//# sourceMappingURL=');
    const trailer = map.exec(text.slice(start));
    assert(trailer, 'missing registry combo map trailer');
    assert.equal(trailer[1], `??${MODULES}/client.js.map&rev=${descriptor.rev}`);
    // Pin the revision-independent executable body separately from the response hash.
    assert.equal(sha(text.slice(0, start)), '76100984f90134e037370c14343d08f7c426e6791ca696ec75584047cf9388d1');
    bodies.set(resource.url, text);
  }
  const html = (await checkedFile(directory, manifest.index, 'index.html')).toString('utf8');
  const tags = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
  assert.equal(tags.length, 5);
  const [queue, blocking, global, shell, tail] = tags;
  assert.deepEqual(injections, [
    { kind: 'script', placement: 'head', text: queue[2] },
    { kind: 'script-src', placement: 'head', src: batch.url },
    { kind: 'global', name: '__DSH_BOOT__', value: graph },
  ]);
  assert.equal(blocking[1], ` src="${batch.url.replace('&', '&amp;')}"`);
  assert.equal(blocking[2], '');
  assert.equal(shell[1], ' type="module" crossorigin src="./assets/index-Ciz7DZxv.js"');
  assert.equal(tail[2], '(globalThis.__DSH_BOOT_READY__ ??= Promise.withResolvers()).resolve()');
  assert.equal(queue.index, html.indexOf('<head>') + '<head>'.length);
  assert.equal(tail.index, html.indexOf('<body>') + '<body>'.length);
  assert.deepEqual([queue[1], global[1], tail[1]], ['', '', '']);
  assert.deepEqual(manifest.cspScriptHashes, [queue, global, tail].map(tag => `sha256-${sha(tag[2], 'base64')}`));
  assert.equal(html.replace(queue[0] + blocking[0] + global[0], '').replace(tail[0], ''), stock.toString('utf8'));

  const doc = new URL('dsh-app://bundle/');
  const externalURL = new URL(blocking[1].slice(6, -1).replace('&amp;', '&'), doc);
  const route = `${externalURL.pathname}${externalURL.search}`;
  assert.equal(externalURL.protocol, doc.protocol);
  assert.equal(externalURL.host, doc.host);
  assert.equal(route, parserResource.url);
  assert.equal(bodies.has(route.replace('??', '?')), false);
  assert.equal(bodies.has(route.slice(0, route.indexOf('?'))), false);
  const script = bodies.get(route);

  const context = realm();
  runClassic(context, queue[2], 'official-queue');
  assert.equal(context.__ModuleLoader__.mode, 'queue');
  assert.equal(context.__ModuleLoader__.pendingQueue.length, 0);
  runClassic(context, script, route);
  assert.equal(context.__ModuleLoader__.pendingQueue.length, 1);
  assert.equal(context.__ModuleLoader__.pendingQueue[0].id, MODULES);
  runClassic(context, global[2], 'official-graph');
  assert.deepEqual(JSON.parse(JSON.stringify(context.__DSH_BOOT__)), graph);
  runClassic(context, tail[2], 'official-readiness');
  await context.__DSH_BOOT_READY__.promise;
  const loader = createLoader(context);
  assert.equal(context.__ModuleLoader__.mode, 'live');
  assert.equal(context.__ModuleLoader__.pendingQueue.length, 0);
  const face = await loader.import(`${MODULES}/client`);
  assert(loader instanceof face.ClientModuleSystem);
  assert.equal(face, await loader.import(MODULES));
  assert.deepEqual(JSON.parse(JSON.stringify(loader.manifest.release)), RELEASE);

  const withoutCombo = realm();
  runClassic(withoutCombo, queue[2], 'official-queue');
  runClassic(withoutCombo, global[2], 'official-graph');
  runClassic(withoutCombo, tail[2], 'official-readiness');
  assert.throws(() => createLoader(withoutCombo), /HTML did not preload/);
  const beforeQueue = realm();
  assert.throws(() => runClassic(beforeQueue, script, route), /reading 'load'/);
  assert.throws(() => runClassic(context, bodies.get(fallbackResource.url), fallbackResource.url), /duplicate factory registration/);
  return manifest;
}

const [, , seedArg, directoryArg, ...extra] = process.argv;
assert(seedArg && directoryArg && extra.length === 0, 'usage: node test-web-bootstrap.mjs SEED STAGED_DIRECTORY');
const seed = resolve(seedArg);
const directory = resolve(directoryArg);
const staged = await validateStaged(seed, directory);
await guardedReexport(seed, directory, staged);
console.log(JSON.stringify({ environment: 'desktop-node-not-webkit', phase: 'official-module-bootstrap-assets',
  release: staged.graph.release, resources: staged.resources.length, loaderTransitionVerified: true,
  noTransportAttempts: true, badBaselinesRejected: true }));
