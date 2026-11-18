import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// App-owned Host for the stock frontend: official services only, reached through
// a shared fetch handler. No webServer row exists, so nothing binds a port.
const ROWS = [
  ['sessions', '@deepseek-ai/dsh-session'],
  ['sessionPersistence', './sqlite-session-persistence.mjs'],
  ['storage', '@deepseek-ai/dsh-storage'],
  ['storageJson', '@deepseek-ai/dsh-storage-json'],
  ['storageDomain', '@deepseek-ai/dsh-storage-domain'],
  ['commands', '@deepseek-ai/dsh-commands'],
  ['sessionProjections', '@deepseek-ai/dsh-session-projection'],
  ['sessionTitle', '@deepseek-ai/dsh-session-title', { fallbackMaxWords: 5, fallbackMaxBytes: 40, maxTitleBytes: 80 }],
  ['sessionQuery', '@deepseek-ai/dsh-session-query-sqlite', { path: ':memory:', openAt: 'never' }],
  ['systemPrompt', '@deepseek-ai/dsh-system-prompt'],
  ['tools', '@deepseek-ai/dsh-tools'],
  ['toolExecutorNative', '@deepseek-ai/dsh-tool-executor-native'],
  ['llm', '@deepseek-ai/dsh-llm'],
  ['agents', '@deepseek-ai/dsh-agent'],
  ['agentLoop', '@deepseek-ai/dsh-agent-loop', { agents: [] }],
  ['userApproval', '@deepseek-ai/dsh-user-approval', { policy: 'ask' }],
  ['agentDefaultModel', '@deepseek-ai/dsh-agent-default-model'],
  ['attachments', '@deepseek-ai/dsh-attachment-local'],
  ['fs', '@deepseek-ai/dsh-fs-local'],
  ['workspace', '@deepseek-ai/dsh-workspace'],
  ['fileUploads', '@deepseek-ai/dsh-client-file-upload'],
  ['credentials', '@deepseek-ai/dsh-credentials-local'],
  ['connection', '@deepseek-ai/dsh-client-connection'],
  ['typert', '@deepseek-ai/dsh-typert-registry'],
  ['remoteAccess', '@deepseek-ai/dsh-api-remote-access'],
  ['apiRemotes', '@deepseek-ai/dsh-api-remotes'],
  ['workspaceController', '@deepseek-ai/dsh-api-workspace-controller'],
  ['gateway', '@deepseek-ai/dsh-api-gateway'],
  ['sessionController', '@deepseek-ai/dsh-api-session-controller'],
];

/**
 * Boot the official Host services the stock frontend expects, with no listener.
 * `stateDirectory` must be an absolute App-private directory; it holds the
 * official credential store and any service-private files.
 */
export async function createOfficialHost({ seed, stateDirectory, clientPackages = [], fixtureChallenge, appChannel }) {
  if (typeof seed !== 'string' || !isAbsolute(seed)) throw new TypeError('seed must be absolute');
  if (typeof stateDirectory !== 'string' || !isAbsolute(stateDirectory)) {
    throw new TypeError('stateDirectory must be absolute');
  }
  const extraPackages = [...new Set(clientPackages)].filter(pkg => !ROWS.some(([, name]) => name === pkg));
  if (extraPackages.some(pkg => typeof pkg !== 'string' || !/^@deepseek-ai\/dsh-[a-z0-9-]+$/u.test(pkg))) {
    throw new TypeError('invalid official Client package');
  }
  const root = resolve(seed);
  const state = resolve(stateDirectory);
  if (fixtureChallenge !== undefined && appChannel !== undefined) throw new TypeError('Select exactly one model route');
  const app = appChannel === undefined ? undefined
    : await import(pathToFileURL(join(root, 'official-app-services.mjs')).href);
  const modelSelection = app?.officialAppModelSelection(appChannel.channel, appChannel.apiKey);
  await mkdir(state, { recursive: true, mode: 0o700 });
  await chmod(state, 0o700);
  const work = await mkdtemp(join(state, '.host-'));
  await chmod(work, 0o700);
  const entry = (pkg, artifact = 'lib/index.js') =>
    pathToFileURL(join(root, 'node_modules', pkg, artifact)).href;
  // Keep writable configuration in the private state directory; place the
  // adapter beside the locked node_modules so its bare ESM imports resolve.
  const config = join(work, 'cordis.json');
  await writeFile(join(work, 'package.json'), '{}\n', { flag: 'wx' });
  const hostRows = [...ROWS, ...extraPackages.map(pkg => [pkg.slice('@deepseek-ai/dsh-'.length), pkg])];
  if (fixtureChallenge !== undefined) {
    hostRows.push(['iosFixtureModel', './core-fixture-model.mjs', { challenge: fixtureChallenge }]);
  }
  const rows = hostRows.map(([id, pkg, extra]) => {
    const row = { id, name: pkg.startsWith('./') ? pathToFileURL(resolve(root, pkg)).href : entry(pkg) };
    if (id === 'credentials') {
      row.config = { path: join(state, '.credentials.yaml'), dshHome: state, watch: false };
    } else if (id === 'attachments') {
      row.config = { dshHome: state };
    } else if (id === 'fs') {
      // A resolution default only. The carrier separately limits workspace routes.
      row.config = { cwd: state };
    } else if (id === 'sessionPersistence') {
      row.config = { directory: join(state, 'sessions') };
    } else if (id === 'storageJson') {
      row.config = { root: join(state, 'storage') };
    } else if (id === 'storageDomain') {
      row.config = { backend: 'json' };
    } else if (id === 'agentDefaultModel') {
      // The stock frontend picks a route from its own Models page; this default
      // only satisfies the service contract so the session API can mount.
      row.config = modelSelection ?? (fixtureChallenge === undefined ? { provider: 'ios-custom', model: 'deepseek-flash' }
        : { provider: 'ios-offline-fixture', model: 'deterministic-text' });
    } else if (id === 'sessionController') {
      row.config = { nativeOpen: false };
    } else if (pkg === '@deepseek-ai/dsh-api-workspace-controller') {
      row.config = { documentsDirectory: state };
    } else if (extra !== undefined) {
      row.config = extra;
    }
    return row;
  });
  await writeFile(config, JSON.stringify(rows), { flag: 'wx', mode: 0o600 });
  const { boot } = await import(entry('@deepseek-ai/dsh-app-boot'));
  let ctx;
  try {
    ctx = await boot('dsh-ios-official-host', config, []);
    // Rows use absolute URLs so the configuration can live outside the seed.
    // Register the official generated schema explicitly instead of letting
    // Gateway fall back to inferring the contract from JS parameter names.
    const typert = ctx.get('typert');
    if (!typert) throw new Error('IOS_HOST_TYPERT_MISSING');
    for (const owner of ['@deepseek-ai/dsh-api-remote-access', '@deepseek-ai/dsh-api-session-controller',
      '@deepseek-ai/dsh-api-workspace-controller']) {
      const { TYPERT } = await import(entry(owner, 'lib/typert.host.js'));
      ctx.effect(() => typert.register(TYPERT));
    }
  } catch (error) {
    await ctx?.fiber.dispose();
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
  const lifetime = new AbortController();
  let appServices;
  let appRoutes;
  if (app) {
    try {
      appServices = await app.registerOfficialAppServices(ctx, {
        workspace: join(state, 'Workspace'), stateDirectory: state,
        channel: appChannel.channel, apiKey: appChannel.apiKey, lifetimeSignal: lifetime.signal,
      });
      const { createOfficialAppRoutePolicy } = await import(pathToFileURL(join(root, 'official-app-routes.mjs')).href);
      const registry = ctx.get('workspaceRegistry');
      const workspace = await registry.resolveByPath(appServices.workspace)
        ?? await registry.create(appServices.workspace);
      // This initial App composition owns a single private Workspace store.
      // If the directory was written by an incompatible build, never expose
      // other registries through the owner peer's baseline.
      if (registry.list().some(item => item.id !== workspace.id)) throw new Error('IOS_HOST_CONFLICTING_WORKSPACE');
      appRoutes = createOfficialAppRoutePolicy({ workspaceId: workspace.id,
        containsSensitiveText: appServices.containsSensitiveText,
        hasSession: id => workspace.sessionIds.includes(id),
      });
    } catch (error) {
      lifetime.abort();
      try { await appServices?.dispose(); }
      finally {
        try { await ctx.fiber.dispose(); }
        finally { await rm(work, { recursive: true, force: true }); }
      }
      throw error;
    } finally { appChannel = undefined; }
  }
  const peer = connection.createPeer({ principal: { kind: 'owner' }, interactions: 'answer' });
  const shared = connection.createSharedFetchHandler('/api');
  const gateway = ctx.get('typertGateway');
  async function* emptyUplink() {}
  let disposed;
  return Object.freeze({
    // The caller must also scope its published method/file routes and every
    // workspace argument; the generated owner Peer alone is not an ACL.
    async fetch(request) {
      if (!(request instanceof Request)) throw new TypeError('Request required');
      const url = new URL(request.url);
      if (url.protocol !== 'dsh-app:' || url.host !== 'bundle' || url.port) {
        return new Response('forbidden', { status: 403 });
      }
      const endpointURL = `http://bundle${url.pathname}${url.search}`;
      if (!appRoutes) return shared.fetch(new Request(endpointURL, request), peer);
      if (lifetime.signal.aborted) return new Response('closed', { status: 503 });
      if (request.method !== 'POST' || request.headers.get('content-type')?.split(';')[0]?.trim() !== 'application/json') {
        return new Response('unsupported', { status: 415 });
      }
      const admitted = appRoutes.admitRequest(request.method, `${url.pathname}${url.search}`, await request.text());
      if (!admitted.ok) return new Response('not available', { status: admitted.status });
      return shared.fetch(new Request(endpointURL, { method: 'POST', body: admitted.body,
        headers: { 'content-type': 'application/json' }, signal: AbortSignal.any([request.signal, lifetime.signal]),
      }), peer);
    },
    appWorkspace: appServices?.workspace,
    containsSensitiveText: appServices?.containsSensitiveText,
    // Used by the cloud exporter; no Web server needs to listen for this graph.
    clientGraph() { return ctx.get('clientModules')?.graph(); },
    clientBundle(request) { return ctx.get('clientModules')?.fetchBundle(request); },
    openStream(endpoint, payload, signal, uplink = emptyUplink()) {
      if (appRoutes && !appRoutes.admitStream(endpoint, payload)) throw new Error('IOS_APP_STREAM_NOT_AVAILABLE');
      const scopedSignal = signal ? AbortSignal.any([signal, lifetime.signal]) : lifetime.signal;
      return gateway.wireStream.open(endpoint, payload, uplink, peer, scopedSignal);
    },
    dispose() {
      disposed ??= (async () => {
        lifetime.abort();
        try { await peer.dispose(); }
        finally {
          try { await appServices?.dispose(); }
          finally {
            try { await ctx.fiber.dispose(); }
            finally { await rm(work, { recursive: true, force: true }); }
          }
        }
      })();
      return disposed;
    },
  });
}
