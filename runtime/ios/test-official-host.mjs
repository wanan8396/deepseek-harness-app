import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { copyFile, mkdtemp, rm } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createOfficialHost } from './official-host.mjs';

const seed = resolve(process.argv[2]);
// Match the embedded bundle layout. Copy only this reviewed adapter from the
// already-exported persistence bundle; third-party imports resolve in the seed.
await copyFile(join(resolve(process.argv[3]), 'sqlite-session-persistence.mjs'),
  join(seed, 'sqlite-session-persistence.mjs'));

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
    assert.deepEqual(attempts, [], 'official Host must not open a socket');
    console.log(JSON.stringify({
      environment: 'desktop-node-not-webkit', phase: 'official-host-shared-fetch',
      crossOriginStatus: crossOrigin.status, unknownStatus: unknown.status,
      sessionsCreated: 2, sessionsAfterHostReopen: 2, followSnapshotVerified: true,
      noTransportAttempts: true, webServerMounted: false,
    }));
  } finally { await host.dispose(); }
} finally {
  Server.prototype.listen = listen;
  Socket.prototype.connect = connect;
  globalThis.fetch = nativeFetch;
  await rm(state, { recursive: true, force: true });
}
