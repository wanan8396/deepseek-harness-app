import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';

const seed = resolve(process.argv[2]);
const { startOfficialAppMailbox } = await import(pathToFileURL(join(seed, 'official-app-mailbox.mjs')).href);
const dir = await mkdtemp(join(tmpdir(), 'dsh-ios-app-wire-'));
const report = join(dir, 'test.json');
const wire = `${report}.official`;
const apiKey = 'wire-test-key-not-a-credential';
const configuration = { apiKey, channel: { protocol: 'openai-chat', baseUrl: 'https://models.example/v1', modelId: 'wire-model' } };
const control = new AbortController();
const runner = startOfficialAppMailbox(report, seed, control.signal);
void runner.catch(() => {});
const gone = error => { if (error.code !== 'ENOENT') throw error; };
async function receive(name, timeout = 8000) {
  const file = join(wire, name);
  const deadline = Date.now() + timeout;
  for (;;) {
    const bytes = await readFile(file).catch(gone);
    if (bytes) { await rm(file); return JSON.parse(bytes); }
    if (Date.now() >= deadline) assert.fail(`App mailbox reply missing: ${name}`);
    await sleep(20);
  }
}
async function publish(name, body) {
  const temporary = join(wire, `${name}.tmp`);
  await writeFile(temporary, JSON.stringify(body), { flag: 'wx', mode: 0o600 });
  await rename(temporary, join(wire, name));
}
async function call(path, body) {
  const id = randomUUID().replaceAll('-', '');
  await publish(`official-call-${id}.json`, { path, method: 'POST', headers: [['content-type', 'application/json']], body: JSON.stringify(body) });
  const response = await receive(`official-reply-${id}.json`);
  assert.equal(response.status, 200, `${path}: ${response.body}`);
  return JSON.parse(response.body);
}
async function rpc(method, args) {
  const response = await call(`/api/${method}`, { type: 'client-request', rpcId: randomUUID(), method, payload: { args } });
  assert.equal(response.result.ok, true, `${method}: ${JSON.stringify(response.result)}`);
  return response.result.value;
}
const id = 's0123456789abcdef0123456789abcdef';
try {
  await mkdir(wire, { mode: 0o700 });
  await publish('official-start.json', configuration);
  assert.deepEqual(await receive('official-ready.json'), { ok: true });
  await assert.rejects(lstat(join(wire, 'official-start.json')), { code: 'ENOENT' });
  const { sessionId } = await rpc('session/create', { request: {} });
  assert.deepEqual(await call('/api/ios-app/stream', { type: 'open', id, endpoint: 'session/follow', payload: { args: {
    request: { address: { kind: 'session', sessionId } },
  } } }), { opened: true });
  const next = () => call('/api/ios-app/stream', { type: 'next', id });
  assert.equal((await next()).value.header.id, sessionId);
  const waiting = next();
  void waiting.catch(() => {});
  await rpc('session/rename', { request: { sessionId, title: 'wire rename' } });
  assert.equal((await waiting).value.event.data.title, 'wire rename');
  await publish('official-stop', 1);
  assert.equal(await receive('official-stopped'), 1);
  await publish('official-start.json', configuration);
  assert.deepEqual(await receive('official-ready.json'), { ok: true });
  assert.deepEqual((await rpc('session/list', { _request: {} })).items.map(row => row.sessionId), [sessionId]);
  await publish('official-stop', 1);
  assert.equal(await receive('official-stopped'), 1);
  console.log(JSON.stringify({ officialProductionMailboxVerified: true, appStreamAndConcurrentRpcVerified: true,
    restartAndSqliteSessionVerified: true, transientCredentialConsumed: true }));
} finally {
  control.abort();
  try { await runner; } finally { await rm(dir, { recursive: true, force: true }); }
}
