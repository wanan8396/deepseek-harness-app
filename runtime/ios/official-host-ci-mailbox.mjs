// RunnerTests-only carrier. Each native command has its own bounded reply lane.
import { randomBytes, randomUUID } from 'node:crypto';
import { lstat, mkdir, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const STREAMS = new Set(['$events', 'remoteAccess/follow', 'workspace/follow', 'session/control', 'session/follow']);
const METHODS = new Set(['session/create', 'session/list', 'session/rename', 'session/projections',
  'session/modelCatalog', 'session/page', 'session/events', 'session/search', 'workspace/initializeDefault', '$events/result']);
const REQUEST_BYTES = 256 * 1024;
const RESPONSE_BYTES = 256 * 1024;
const ID = /^s[0-9a-f]{1,40}$/u;
const lanePattern = /^official-call-([0-9a-f]{32})\.json$/u;
const error = (status, body) => ({ status, body });
const ok = value => ({ status: 200, body: JSON.stringify(value) });
const missing = exception => { if (exception.code !== 'ENOENT') throw exception; };

export async function serveOfficialHostCi(seed, reportPath) {
  const directory = dirname(reportPath);
  const stateDirectory = join(directory, 'OfficialHostCI');
  const stopPath = join(directory, 'official-host-ci-stop');
  const requestedWorkspace = join(stateDirectory, 'iOS Test Workspace');
  await mkdir(requestedWorkspace, { recursive: true, mode: 0o700 });
  const workspace = await realpath(requestedWorkspace);
  const { createOfficialHost } = await import(pathToFileURL(join(seed, 'official-host.mjs')).href);
  const fixtureChallenge = randomBytes(32).toString('hex');
  const host = await createOfficialHost({ seed, stateDirectory, fixtureChallenge });
  const streams = new Map();
  const tasks = new Map();
  let cleanStop = false;
  let closing = false;
  let workspaceId;

  const rpc = (endpoint, request) => host.fetch(new Request(`dsh-app://bundle/api/${endpoint}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(request),
  }));
  async function callOfficial(endpoint, args) {
    const response = await rpc(endpoint, { type: 'client-request', rpcId: randomUUID(),
      method: endpoint, payload: { args } });
    const reply = await response.json();
    if (!response.ok || !reply.result?.ok) {
      throw Object.assign(new Error(`iOS test Host call failed: ${endpoint}`), { code: reply.result?.error?.code });
    }
    return reply.result.value;
  }
  const close = async id => {
    const stream = streams.get(id);
    if (!stream) return;
    streams.delete(id);
    stream.controller.abort();
    const iterator = await stream.open;
    await stream.next?.catch(() => {});
    await iterator.return?.();
  };
  async function dispatchStream({ type, id, endpoint, payload }) {
    if (typeof id !== 'string' || !ID.test(id)) return error(400, 'IOS_HOST_CI_INVALID_STREAM');
    if (type === 'open') {
      if (!STREAMS.has(endpoint) || streams.has(id) || streams.size >= 12) {
        return error(400, 'IOS_HOST_CI_INVALID_STREAM');
      }
      const controller = new AbortController();
      const stream = { controller, busy: false, next: null };
      stream.open = Promise.resolve(host.openStream(endpoint, payload, controller.signal))
        .then(source => source[Symbol.asyncIterator]());
      streams.set(id, stream);
      try { await stream.open; }
      catch (reason) { streams.delete(id); throw reason; }
      return ok({ opened: !controller.signal.aborted });
    }
    if (type === 'close') {
      await close(id);
      return ok({ closed: true });
    }
    const stream = streams.get(id);
    if (type !== 'next' || !stream || stream.busy) return error(409, 'IOS_HOST_CI_INVALID_PULL');
    stream.busy = true;
    const clock = new AbortController();
    const idle = {};
    try {
      const iterator = await stream.open;
      // Hold one iterator read across idle polls; never accumulate pending reads.
      stream.next ??= Promise.resolve().then(() => iterator.next());
      const item = await Promise.race([stream.next, sleep(2000, idle, { signal: clock.signal })]);
      if (item === idle) return ok({ idle: true });
      stream.next = null;
      if (item.done) await close(id);
      return ok(item);
    } catch (reason) {
      if (stream.controller.signal.aborted) return ok({ done: true });
      await close(id).catch(() => {});
      throw reason;
    } finally {
      clock.abort();
      stream.busy = false;
    }
  }
  async function dispatch(wire) {
    if (closing || typeof wire.path !== 'string' || typeof wire.body !== 'string') {
      return error(400, 'IOS_HOST_CI_INVALID_REQUEST');
    }
    const request = JSON.parse(wire.body);
    if (wire.path === '/api/ios-ci/stream') return dispatchStream(request);
    if (wire.path === '/api/ios-ci/engage') {
      // The official sidebar hides non-current blank sessions. Drive an
      // actual AgentLoop turn on both rows, with only inference substituted.
      const { sessionIds } = request;
      if (!Array.isArray(sessionIds) || sessionIds.length !== 2 || new Set(sessionIds).size !== 2
          || !sessionIds.every(id => typeof id === 'string' && /^session-[a-zA-Z0-9_-]{1,100}$/u.test(id))) {
        return error(400, 'IOS_HOST_CI_INVALID_SESSIONS');
      }
      for (const [index, sessionId] of sessionIds.entries()) {
        const label = index === 0 ? 'first' : 'second';
        const receipt = await callOfficial('session/prompt', { request: {
          requestId: randomUUID(), sessionId, mode: 'queue', content: [{ type: 'text', text: `probe-${label}:${fixtureChallenge}` }],
        } });
        const stable = await callOfficial('session/wait', { request: { sessionId, timeoutMs: 6000, maxMessages: 4 } });
        if (!receipt.accepted || stable.reason !== 'idle'
            || !JSON.stringify(stable.output.records).includes(`${fixtureChallenge}:${label}`)) {
          return error(500, 'IOS_HOST_CI_OFFLINE_TURN_FAILED');
        }
      }
      return ok({ engaged: true });
    }
    const endpoint = wire.path.slice(5);
    if (!wire.path.startsWith('/api/') || !METHODS.has(endpoint) || request.method !== endpoint) {
      return error(404, 'IOS_HOST_CI_INVALID_ROUTE');
    }
    if (endpoint === 'session/create') {
      const args = request.payload?.args?.request;
      if (args === null || typeof args !== 'object' || Array.isArray(args)
          || args.cwd !== undefined || (args.workspaceId !== undefined && args.workspaceId !== workspaceId)
          || args.agentPreset !== undefined) return error(403, 'IOS_HOST_CI_INVALID_WORKSPACE');
      args.workspaceId = workspaceId;
    }
    // On this fixture the App already chose the one private workspace. Do not
    // create an additional host-dependent directory for browser first-use.
    if (endpoint === 'workspace/initializeDefault') {
      const response = await rpc('workspace/create', { ...request, method: 'workspace/create',
        payload: { args: { request: { path: workspace } } } });
      const value = await response.json();
      if (value.result?.ok) value.result.value = { workspace: value.result.value.workspace };
      return { status: response.status, body: JSON.stringify(value) };
    }
    const response = await rpc(endpoint, request);
    return { status: response.status, body: await response.text() };
  }
  async function handleLane(name, id) {
    const requestPath = join(directory, name);
    const info = await lstat(requestPath).catch(missing);
    if (!info) return;
    let reply;
    try {
      if (!info.isFile() || info.size > REQUEST_BYTES) throw new Error('IOS_HOST_CI_REQUEST_LIMIT');
      const frame = JSON.parse(await readFile(requestPath, 'utf8'));
      await rm(requestPath, { force: true });
      reply = await dispatch(frame);
    } catch (exception) {
      await rm(requestPath, { force: true });
      const code = typeof exception?.code === 'string' && /^[a-z0-9/_-]{1,80}$/iu.test(exception.code)
        ? exception.code : 'unknown';
      reply = error(500, `IOS_HOST_CI_RPC_FAILED:${code}`);
    }
    if (Buffer.byteLength(reply.body) > RESPONSE_BYTES) reply = error(413, 'IOS_HOST_CI_RESPONSE_LIMIT');
    const temp = join(directory, `official-${id}.tmp`);
    try {
      await writeFile(temp, JSON.stringify(reply), { flag: 'wx', mode: 0o600 });
      await rename(temp, join(directory, `official-reply-${id}.json`));
    } finally { await rm(temp, { force: true }); }
  }
  try {
    const workspaceResult = await callOfficial('workspace/create', { request: { path: workspace } });
    workspaceId = workspaceResult?.workspace?.workspaceId;
    if (!workspaceId) throw new Error('IOS_HOST_CI_WORKSPACE_NOT_READY');
    const ready = join(directory, 'official-host-ci-ready');
    await writeFile(`${ready}.tmp`, JSON.stringify({ workspaceId, workspacePath: workspace }), { flag: 'wx', mode: 0o600 });
    await rename(`${ready}.tmp`, ready);
    const deadline = Date.now() + 120_000;
    let laneFailure;
    while (Date.now() < deadline) {
      if (laneFailure) throw laneFailure;
      if ((await readFile(stopPath, 'utf8').catch(missing)) === '1') { cleanStop = true; break; }
      for (const name of await readdir(directory)) {
        const match = lanePattern.exec(name);
        if (!match || tasks.has(match[1]) || tasks.size >= 16) continue;
        const id = match[1];
        tasks.set(id, handleLane(name, id).catch(reason => { laneFailure ??= reason; }).finally(() => tasks.delete(id)));
      }
      await sleep(25);
    }
  } finally {
    closing = true;
    await Promise.allSettled([...streams.keys()].map(close));
    await Promise.allSettled(tasks.values());
    await host.dispose();
  }
  if (cleanStop) await writeFile(join(directory, 'official-host-ci-stopped'), '1', { flag: 'wx', mode: 0o600 });
}
