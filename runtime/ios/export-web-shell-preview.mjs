// Cloud-only preview of the official renderer/sidebar/composer roster.
// Does not replace the shipped singleton bootstrap or claim the UI is ready.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFile, lstat, mkdir, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createOfficialHost } from './official-host.mjs';

const prefix = '@deepseek-ai/dsh-';
const packages = [
  'client-modules', 'typert-registry', 'api-gateway', 'api-remote-access', 'api-remotes',
  'api-session-controller', 'api-workspace-controller', 'client-connection', 'client-file-upload',
  'client-locale', 'client-shortcuts', 'client-ui-context-menu', 'client-ui-conversation',
  'client-ui-layout', 'client-ui-renderer', 'client-ui-session', 'client-ui-settings',
  'client-ui-sidebar', 'client-ui-theme', 'client-ui-workspace',
].map(name => prefix + name);
const app = process.argv[5] === '--app';
const appArtifact = {
  route: '/plugins/@deepseek-ai/dsh-client-ui-chat/assets/running-whale%402x-06738fa29b2f.png',
  path: 'running-whale.png', contentType: 'image/png', bytes: 21631,
  sha256: '0fd990d118113d19af7af4480f2b55d610b103451a08be6f7bf5a146823f8bd3',
};
if (app) packages.push(...[
  'client-resources', 'client-ui-approval', 'client-ui-chat', 'client-ui-commands',
  'client-ui-file-drag', 'client-ui-input-trigger', 'client-ui-model-selection', 'client-ui-sidebar-right',
].map(name => prefix + name));
const documentURL = 'dsh-app://bundle/';
const seed = resolve(process.argv[2]);
const output = resolve(process.argv[3]);
const auditedHost = resolve(process.argv[4]);
await assert.rejects(lstat(output), { code: 'ENOENT' });
const lock = await readFile(new URL('../locks/dsh-0.2.2-rc.3/package-lock.json', import.meta.url));
assert((await readFile(join(seed, 'package-lock.json'))).equals(lock));
const locked = JSON.parse(lock).packages;
const pathFor = (pkg, path) => join(seed, 'node_modules', pkg, path);
const entry = (pkg) => pathToFileURL(pathFor(pkg, 'lib/index.js')).href;
const sha256 = (bytes, encoding = 'hex') => createHash('sha256').update(bytes).digest(encoding);
const attempts = [];
const listen = Server.prototype.listen;
const connect = Socket.prototype.connect;
const fetch = globalThis.fetch;
const block = kind => () => { attempts.push(kind); throw new Error(`preview attempted ${kind}`); };
const work = await mkdtemp(join(dirname(output), '.dsh-ios-shell-preview-'));
let host;
try {
  Server.prototype.listen = block('listen');
  Socket.prototype.connect = block('connect');
  globalThis.fetch = block('fetch');
  const manifests = new Map();
  const licenseSHA256 = 'ebb4f09972aee8608be255debaf78451a68e95c290f55c240dec2ecfa16ea6be';
  let license;
  for (const pkg of packages) {
    const key = `node_modules/${pkg}`;
    const manifest = JSON.parse(await readFile(pathFor(pkg, 'package.json')));
    assert.equal(manifest.name, pkg);
    assert.equal(manifest.version, '0.2.2-rc.3');
    assert.equal(manifest.version, locked[key].version);
    assert.equal(manifest.dsh.client.platform, 'web');
    assert.equal(manifest.license, 'MIT');
    license = await readFile(pathFor(pkg, 'LICENSE'));
    assert.equal(sha256(license), licenseSHA256, pkg);
    manifests.set(pkg, manifest.dsh.client);
  }
  // The npm-ci seed is disposable. Place the same audited persistence adapter
  // alongside its dependencies, not in the repo or the output preview.
  await copyFile(join(auditedHost, 'sqlite-session-persistence.mjs'), join(seed, 'sqlite-session-persistence.mjs'));
  host = await createOfficialHost({ seed, stateDirectory: join(work, 'state'), clientPackages: packages });
  const graph = host.clientGraph();
  assert.equal(graph.release.version, '0.2.2-rc.3');
  assert.equal(graph.entries.length, packages.length);
  assert.deepEqual(new Set(graph.entries.map(row => row.id)), new Set(packages));
  for (const row of graph.entries) {
    const manifest = manifests.get(row.id);
    assert.deepEqual(row.inject ?? [], manifest.inject ?? []);
    assert.deepEqual(row.external ?? [], manifest.external ?? []);
    assert.equal(row.immediately ?? false, manifest.immediately ?? false);
    for (const name of row.inject ?? []) assert(manifests.has(name), `${row.id}: missing ${name}`);
  }
  assert.deepEqual(graph.batches.filter(x => x.phase === 'bootstrap').flatMap(x => x.entries), [prefix + 'client-modules']);
  assert.deepEqual(new Set(graph.batches.flatMap(x => x.entries)), new Set(packages));
  assert(graph.batches.some(x => x.phase === 'application'));

  const stage = join(work, 'stage');
  await mkdir(join(stage, 'bundles'), { recursive: true });
  const resources = [];
  const references = [...new Set([...graph.batches, ...graph.entries].map(row => row.url))];
  for (const reference of references) {
    const url = new URL(reference, documentURL);
    const route = `${url.pathname}${url.search}`;
    assert.equal(url.href, documentURL + reference);
    assert(route.startsWith('/plugins/??') && route.length <= 3072);
    const response = await host.clientBundle(new Request(url));
    assert.equal(response.status, 200, route);
    const contentType = response.headers.get('content-type');
    assert.equal(contentType, 'text/javascript; charset=utf-8');
    const bytes = Buffer.from(await response.arrayBuffer());
    assert(bytes.length > 0);
    const hash = sha256(bytes);
    const path = `bundles/${resources.length}-${hash.slice(0, 12)}.js`;
    await writeFile(join(stage, path), bytes, { flag: 'wx' });
    resources.push({ url: route, path, contentType, bytes: bytes.length, sha256: hash });
  }
  if (app) {
    const asset = await host.clientBundle(new Request(new URL(appArtifact.route, documentURL)));
    assert.equal(asset.status, 200);
    assert.equal(asset.headers.get('content-type'), appArtifact.contentType);
    const bytes = Buffer.from(await asset.arrayBuffer());
    assert.equal(bytes.length, appArtifact.bytes);
    assert.equal(sha256(bytes), appArtifact.sha256);
    await writeFile(join(stage, appArtifact.path), bytes, { flag: 'wx' });
  }
  const [{ bootInjections }, { renderIndexInjections }] = await Promise.all([
    import(entry(prefix + 'client-modules')), import(entry(prefix + 'host-webserver')),
  ]);
  const stock = await readFile(pathFor(prefix + 'web-frontend', 'dist/index.html'));
  assert.equal(sha256(stock), '271698ef62d4cc9a10a5f0aa28d0f4f6cd5e16fe04734908c3eab477a8da0ec1');
  const html = renderIndexInjections(stock.toString('utf8'), bootInjections(graph));
  const cspScriptHashes = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(([, script]) => `sha256-${sha256(script, 'base64')}`);
  assert(cspScriptHashes.length >= 3);
  const htmlBytes = Buffer.from(html);
  await writeFile(join(stage, 'index.html'), htmlBytes, { flag: 'wx' });
  await writeFile(join(stage, 'LICENSE'), license, { flag: 'wx' });
  await writeFile(join(stage, 'distribution-manifest.json'), JSON.stringify({
    schemaVersion: 1, stage: 'official-shell-preview', officialUIReady: false, graph, resources, cspScriptHashes,
    index: { path: 'index.html', bytes: htmlBytes.length, sha256: sha256(htmlBytes) },
    license: { path: 'LICENSE', bytes: license.length, sha256: licenseSHA256 },
    ...(app ? { appAssets: [appArtifact] } : {}),
    sourceLockSHA256: sha256(lock),
  }, null, 2), { flag: 'wx' });
  await host.dispose();
  host = undefined;
  assert.deepEqual(attempts, []);
  await rename(stage, output);
  console.log(JSON.stringify({ stage: 'official-shell-preview', packages: packages.length, routes: resources.length,
    usesLocalTCP: false, officialUIReady: false }));
} finally {
  try { await host?.dispose(); }
  finally {
    Server.prototype.listen = listen;
    Socket.prototype.connect = connect;
    globalThis.fetch = fetch;
    await rm(work, { recursive: true, force: true });
  }
}
