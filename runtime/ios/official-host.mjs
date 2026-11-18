import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// A bounded App-owned Host: official Connection + Typert Gateway, reached only
// through a shared fetch handler. No webServer row is mounted, so nothing listens.
const ROWS = [
  ['credentials', '@deepseek-ai/dsh-credentials-local'],
  ['connection', '@deepseek-ai/dsh-client-connection'],
  ['typert', '@deepseek-ai/dsh-typert-registry'],
  ['remoteAccess', '@deepseek-ai/dsh-api-remote-access'],
  ['gateway', '@deepseek-ai/dsh-api-gateway'],
];

export async function createOfficialHost({ seed, stateDirectory }) {
  if (typeof seed !== 'string' || !isAbsolute(seed)) throw new TypeError('seed must be absolute');
  if (typeof stateDirectory !== 'string' || !isAbsolute(stateDirectory)) {
    throw new TypeError('stateDirectory must be absolute');
  }
  const root = resolve(seed);
  const state = resolve(stateDirectory);
  await mkdir(state, { recursive: true, mode: 0o700 });
  await chmod(state, 0o700);
  const work = await mkdtemp(join(state, '.host-'));
  await chmod(work, 0o700);
  const entry = (pkg) => pathToFileURL(join(root, 'node_modules', pkg, 'lib/index.js')).href;
  const config = join(work, 'cordis.json');
  await writeFile(join(work, 'package.json'), '{}\n', { flag: 'wx' });
  const rows = ROWS.map(([id, pkg]) => ({
    id, name: entry(pkg),
    ...(id === 'credentials'
      ? { config: { path: join(state, '.credentials.yaml'), dshHome: state, watch: false } }
      : {}),
  }));
  await writeFile(config, JSON.stringify(rows), { flag: 'wx', mode: 0o600 });
  const { boot } = await import(entry('@deepseek-ai/dsh-app-boot'));
  let ctx;
  try {
    ctx = await boot('dsh-ios-official-host', config, []);
  } catch (error) {
    await rm(work, { recursive: true, force: true });
    throw error;
  }
  const loader = ctx.get('loader');
  const activated = rows.every(({ id }) => loader?.resolve('include')?.subtree?.resolve(id)?.fiber?.state === 2);
  const connection = ctx.get('connection');
  const gateway = ctx.get('typertGateway');
  const unavailable = ctx.get('webServer') !== undefined;
  if (!activated || !connection || !gateway || unavailable) {
    await ctx.fiber.dispose();
    await rm(work, { recursive: true, force: true });
    throw new Error(unavailable ? 'IOS_HOST_WEBSERVER_MOUNTED' : 'IOS_HOST_SERVICE_MISSING');
  }
  const peer = connection.createPeer({ principal: { kind: 'owner' }, interactions: 'answer' });
  const shared = connection.createSharedFetchHandler('/api');
  let disposed;
  return Object.freeze({
    // Only an exact App-origin request reaches the official handler. The page
    // transport already refuses every other scheme, so this repeats the fence.
    async fetch(request) {
      if (!(request instanceof Request)) throw new TypeError('Request required');
      const url = new URL(request.url);
      if (url.protocol !== 'dsh-app:' || url.host !== 'bundle' || url.port) {
        return new Response('forbidden', { status: 403 });
      }
      return shared.fetch(new Request(`http://bundle${url.pathname}${url.search}`, request), peer);
    },
    dispose() {
      disposed ??= (async () => {
        await ctx.fiber.dispose();
        await rm(work, { recursive: true, force: true });
      })();
      return disposed;
    },
  });
}
