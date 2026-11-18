import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createOfficialHost } from './official-host.mjs';

const seed = resolve(process.argv[2]);
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
    assert.deepEqual(attempts, [], 'official Host must not open a socket');
    console.log(JSON.stringify({
      environment: 'desktop-node-not-webkit', phase: 'official-host-shared-fetch',
      crossOriginStatus: crossOrigin.status, unknownStatus: unknown.status,
      noTransportAttempts: true, webServerMounted: false,
    }));
  } finally { await host.dispose(); }
} finally {
  Server.prototype.listen = listen;
  Socket.prototype.connect = connect;
  globalThis.fetch = nativeFetch;
  await rm(state, { recursive: true, force: true });
}
