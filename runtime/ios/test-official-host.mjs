import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const seed = resolve(process.argv[2]);
const { createOfficialHost } = await import(pathToFileURL(join(seed, 'official-host.mjs')).href);

async function rpc(host, method, args) {
  const rpcId = randomUUID();
  const response = await host.fetch(new Request(`dsh-app://bundle/api/${method}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'client-request', rpcId, method, payload: { args } }),
  }));
  assert.equal(response.status, 200, method);
  const reply = await response.json();
  assert.equal(reply.type, 'server-response');
  assert.equal(reply.rpcId, rpcId);
  assert.equal(reply.result?.ok, true, `${method}: ${JSON.stringify(reply.result)}`);
  return reply.result.value;
}

async function checkMailbox(serve, seed, state) {
  const directory = join(state, 'mailbox-test');
  await mkdir(directory, { mode: 0o700 });
  const report = join(directory, 'ci.json');
  const hostTask = serve(seed, report);
  void hostTask.catch(() => {});
  const call = async (path, body) => {
    const id = randomUUID().replaceAll('-', '');
    const requestPath = join(directory, `official-call-${id}.json`);
    const responsePath = join(directory, `official-reply-${id}.json`);
    const temporary = `${requestPath}.tmp`;
    await writeFile(temporary, JSON.stringify({ path, body: JSON.stringify(body) }), { flag: 'wx', mode: 0o600 });
    await rename(temporary, requestPath);
    for (let n = 0; n < 600; n++) {
      const result = await readFile(responsePath, 'utf8').catch(error => {
        if (error.code !== 'ENOENT') throw error;
      });
      if (result) {
        await rm(responsePath);
        const reply = JSON.parse(result);
        assert.equal(reply.status, 200, `${path}: ${reply.body}`);
        return JSON.parse(reply.body);
      }
      await sleep(25);
    }
    assert.fail(`CI mailbox timed out: ${path}`);
  };
  const rpc = async (method, args) => {
    const rpcId = randomUUID();
    const result = await call(`/api/${method}`, { type: 'client-request', rpcId, method, payload: { args } });
    assert.equal(result.rpcId, rpcId);
    assert.equal(result.result.ok, true, `${method}: ${JSON.stringify(result.result)}`);
    return result.result.value;
  };
  const stream = (type, options = {}) => call('/api/ios-ci/stream', { id: 's1', type, ...options });
  try {
    await assert.rejects(call('/api/file', {}), /404/u);
    await stream('open', { id: 's2', endpoint: '$events', payload: { args: {} } });
    assert.equal((await stream('next', { id: 's2' })).value.type, 'ready');
    assert.deepEqual(await stream('close', { id: 's2' }), { closed: true });
    await stream('open', { id: 's4', endpoint: 'remoteAccess/follow', payload: { args: {} } });
    const access = (await stream('next', { id: 's4' })).value;
    assert.equal(access.type, 'baseline');
    assert.equal(access.owner, true);
    // This owner access flow emits only a baseline, so its second pull waits
    // while an independent unary RPC and cancellation use separate lanes.
    const pending = stream('next', { id: 's4' });
    void pending.catch(() => {});
    const rejectionId = randomUUID();
    await assert.rejects(call('/api/session/create', { type: 'client-request', rpcId: rejectionId,
      method: 'session/create', payload: { args: { request: { cwd: directory } } } }), /403|IOS_HOST_CI_INVALID_WORKSPACE/u);
    const { sessionId } = await rpc('session/create', { request: {} });
    assert.deepEqual(await stream('close', { id: 's4' }), { closed: true });
    assert.deepEqual(await pending, { done: true });
    await stream('open', { id: 's3', endpoint: 'workspace/follow', payload: { args: {} } });
    const workspace = (await stream('next', { id: 's3' })).value;
    assert.equal(workspace.type, 'baseline');
    assert.equal(workspace.value.items.length, 1);
    assert.deepEqual(workspace.value.items[0].sessionIds, [sessionId]);
    assert.deepEqual(await stream('close', { id: 's3' }), { closed: true });
    await stream('open', { endpoint: 'session/follow', payload: { args: {
      request: { address: { kind: 'session', sessionId }, maxMessages: 10 },
    } } });
    assert.equal((await stream('next')).value.header.id, sessionId);
    const title = 'Mailbox title';
    await rpc('session/rename', { request: { sessionId, title } });
    assert.equal((await stream('next')).value.event.data.title, title);
    assert.deepEqual(await stream('close'), { closed: true });
    const second = await rpc('session/create', { request: {} });
    assert.deepEqual(await call('/api/ios-ci/engage', { sessionIds: [sessionId, second.sessionId] }), { engaged: true });
    const { items } = await rpc('session/list', { _request: {} });
    assert.equal(items.length, 2);
    assert.ok(items.every(item => item.blank === false));
  } finally {
    await writeFile(join(directory, 'official-host-ci-stop'), '1', { flag: 'wx', mode: 0o600 });
    await hostTask;
  }
  assert.equal(await readFile(join(directory, 'official-host-ci-stopped'), 'utf8'), '1');
}

const attempts = [];
const listen = Server.prototype.listen;
const connect = Socket.prototype.connect;
const nativeFetch = globalThis.fetch;
const deny = (kind) => function denied() {
  attempts.push(kind);
  throw new Error(`IOS_HOST_TRANSPORT_ATTEMPT:${kind}`);
};
Server.prototype.listen = deny('listen');
Socket.prototype.connect = deny('connect');
globalThis.fetch = deny('fetch');
const state = await mkdtemp(join(tmpdir(), 'dsh-ios-host-test-'));
try {
  assert.throws(() => new Server().listen(0), /IOS_HOST_TRANSPORT_ATTEMPT/);
  attempts.length = 0;
  const host = await createOfficialHost({ seed, stateDirectory: state });
  try {
    const crossOrigin = await host.fetch(new Request('http://127.0.0.1/api/session/list', { method: 'POST' }));
    assert.equal(crossOrigin.status, 403);
    const unknown = await host.fetch(new Request('dsh-app://bundle/api/unknown/method', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}',
    }));
    assert.ok([404, 405].includes(unknown.status), `unexpected status ${String(unknown.status)}`);
    assert.deepEqual(await rpc(host, 'session/list', { _request: {} }), { items: [] });
    const request = { cwd: state };
    const first = await rpc(host, 'session/create', { request });
    const second = await rpc(host, 'session/create', { request });
    assert.match(first.sessionId, /^session-/u);
    assert.match(second.sessionId, /^session-/u);
    assert.notEqual(first.sessionId, second.sessionId);
    const { items } = await rpc(host, 'session/list', { _request: {} });
    assert.deepEqual(new Set(items.map(item => item.sessionId)), new Set([first.sessionId, second.sessionId]));
    const controller = new AbortController();
    const requestSignal = AbortSignal.any([controller.signal, AbortSignal.timeout(5000)]);
    const stream = await host.openStream('session/follow', {
      args: { request: { address: { kind: 'session', sessionId: first.sessionId }, maxMessages: 10 } },
    }, requestSignal);
    const iterator = stream[Symbol.asyncIterator]();
    try {
      const { done, value } = await iterator.next();
      assert.equal(done, false);
      assert.equal(value.type, 'snapshot');
      assert.equal(value.header.id, first.sessionId);
      const title = 'Host stream fixture';
      assert.equal((await rpc(host, 'session/rename', { request: { sessionId: first.sessionId, title } })).title, title);
      const update = await iterator.next();
      assert.equal(update.done, false);
      assert.equal(update.value.type, 'event');
      assert.equal(update.value.event.type, 'session/title');
      assert.equal(update.value.event.data.title, title);
    } finally {
      controller.abort();
      await iterator.return?.();
    }
    await host.dispose();
    const reopened = await createOfficialHost({ seed, stateDirectory: state });
    try {
      const cold = await rpc(reopened, 'session/list', { _request: {} });
      assert.deepEqual(new Set(cold.items.map(item => item.sessionId)), new Set([first.sessionId, second.sessionId]));
      assert.ok(cold.items.every(item => item.agentAvailable === false));
    } finally { await reopened.dispose(); }
    const { serveOfficialHostCi } = await import(pathToFileURL(join(seed, 'official-host-ci-mailbox.mjs')).href);
    await checkMailbox(serveOfficialHostCi, seed, state);
    assert.deepEqual(attempts, [], 'official Host must not open a socket');
    console.log(JSON.stringify({
      environment: 'desktop-node-not-webkit', phase: 'official-host-shared-fetch',
      crossOriginStatus: crossOrigin.status, unknownStatus: unknown.status,
      sessionsCreated: 2, sessionsAfterHostReopen: 2, followSnapshotVerified: true, followTitleEventVerified: true,
      concurrentLanesVerified: true, workspaceMembershipVerified: true, fixtureTurnsVerified: true,
      noTransportAttempts: true, webServerMounted: false,
    }));
  } finally { await host.dispose(); }
} finally {
  Server.prototype.listen = listen;
  Socket.prototype.connect = connect;
  globalThis.fetch = nativeFetch;
  await rm(state, { recursive: true, force: true });
}
