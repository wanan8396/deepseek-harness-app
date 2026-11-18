import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// App-owned Host for the stock frontend: official services only, reached through
// a shared fetch handler. No webServer row exists, so nothing binds a port.
const ROWS = [
  ['sessions', '@deepseek-ai/dsh-session'],
  ['sessionProjections', '@deepseek-ai/dsh-session-projection'],
  ['sessionQuery', '@deepseek-ai/dsh-session-query-sqlite', { path: ':memory:', openAt: 'never' }],
  ['systemPrompt', '@deepseek-ai/dsh-system-prompt'],
  ['tools', '@deepseek-ai/dsh-tools'],
  ['llm', '@deepseek-ai/dsh-llm'],
  ['agents', '@deepseek-ai/dsh-agent'],
  ['agentLoop', '@deepseek-ai/dsh-agent-loop', { agents: [] }],
  ['userApproval', '@deepseek-ai/dsh-user-approval', { policy: 'ask' }],
  ['agentDefaultModel', '@deepseek-ai/dsh-agent-default-model'],
  ['attachments', '@deepseek-ai/dsh-attachment'],
  ['fs', '@deepseek-ai/dsh-fs-local'],
  ['workspace', '@deepseek-ai/dsh-workspace'],
  ['fileUploads', '@deepseek-ai/dsh-client-file-upload'],
  ['credentials', '@deepseek-ai/dsh-credentials-local'],
  ['connection', '@deepseek-ai/dsh-client-connection'],
  ['typert', '@deepseek-ai/dsh-typert-registry'],
  ['remoteAccess', '@deepseek-ai/dsh-api-remote-access'],
  ['gateway', '@deepseek-ai/dsh-api-gateway'],
  ['sessionController', '@deepseek-ai/dsh-api-session-controller'],
];

/**
 * Boot the official Host services the stock frontend expects, with no listener.
 * `stateDirectory` must be an absolute App-private directory; it holds the
 * official credential store and any service-private files.
 */
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
  // Official rows resolve their own package dependencies, so the config lives
  // beside the seed rather than inside the App-private data directory.
  const config = join(work, 'cordis.json');
  await writeFile(join(work, 'package.json'), '{}\n', { flag: 'wx' });
  const rows = ROWS.map(([id, pkg, config]) => {
    const row = { id, name: entry(pkg) };
    if (id === 'credentials') {
      row.config = { path: join(state, '.credentials.yaml'), dshHome: state, watch: false };
    } else if (id === 'fs' || id === 'workspace') {
      row.config = { root: state };
    } else if (id === 'sessionController') {
      row.config = { nativeOpen: false };
    } else if (config !== undefined) {
      row.config = config;
    }
    return row;
  });
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
  const inactive = rows
    .filter(({ id }) => loader?.resolve('include')?.subtree?.resolve(id)?.fiber?.state !== 2)
    .map(({ id }) => id);
  const connection = ctx.get('connection');
  const controller = ctx.get('sessionController');
  const mountedServer = ctx.get('webServer') !== undefined;
  if (inactive.length || !connection || !controller || mountedServer) {
    await ctx.fiber.dispose();
    await rm(work, { recursive: true, force: true });
    const reason = mountedServer ? 'IOS_HOST_WEBSERVER_MOUNTED'
      : inactive.length ? `IOS_HOST_INACTIVE:${inactive.join(',')}` : 'IOS_HOST_SERVICE_MISSING';
    throw new Error(reason);
  }
  const peer = connection.createPeer({ principal: { kind: 'owner' }, interactions: 'answer' });
  const shared = connection.createSharedFetchHandler('/api');
  let disposed;
  return Object.freeze({
    // The page transport already refuses other schemes; this repeats the fence
    // so a compromised page cannot widen the Host boundary.
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
