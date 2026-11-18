import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, mkdtemp, readFile, readdir, rename, rm } from 'node:fs/promises';
import { writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import fixture from './chat-ci-entry.cjs';

const bundle = resolve(process.argv[2]);
const scratch = await mkdtemp(join(tmpdir(), 'dsh-ios-chat-'));
const report = join(scratch, `${randomUUID()}.json`);
const mailbox = `${report}.chat`;
const manifest = JSON.parse(await readFile(join(bundle, 'distribution-manifest.json'), 'utf8'));
assert.equal(manifest.distribution, 'ios-local-text-chat');
assert.ok(manifest.entryPackages.includes('@deepseek-ai/dsh-llm-deepseek'));
assert.deepEqual(manifest.files.map(({ path }) => path).filter((path) => !path.startsWith('node_modules/')).sort(),
  ['chat-deepseek-provider.mjs', 'chat-engine.mjs', 'chat-mailbox.mjs', 'sqlite-session-persistence.mjs']);
await mkdir(mailbox, { mode: 0o700 });
fixture.installFetchFixture();
const { startChatMailbox } = await fixture.bundled(bundle, 'chat-mailbox.mjs');
const stop = startChatMailbox(report, { pollMs: 25 });

async function call(method, params = {}, expectedError) {
  const id = randomUUID();
  const pending = join(mailbox, `${id}.tmp`);
  const source = join(mailbox, `request-${id}.json`);
  const dest = join(mailbox, `response-${id}.json`);
  await writeFile(pending, JSON.stringify({ id, method, params }), { flag: 'wx', mode: 0o600 });
  await rename(pending, source);
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    let raw;
    try { raw = await readFile(dest, 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; await delay(25); continue; }
    await rm(dest);
    assert.ok(!raw.includes(fixture.key), 'API_KEY_PRESENT_IN_CHAT_REPLY');
    assert.ok(!(await readdir(mailbox)).includes(`request-${id}.json`), 'REQUEST_NOT_CONSUMED');
    const value = JSON.parse(raw);
    assert.equal(value.id, id);
    if (expectedError) { assert.equal(value.errorCode, expectedError); return; }
    assert.equal(value.errorCode, undefined, JSON.stringify(value));
    assert.deepEqual(Object.keys(value.result).sort(), ['draft', 'errorCode', 'messages', 'state']);
    return value.result;
  }
  throw new Error(`IOS_CHAT_TEST_RESPONSE_TIMEOUT:${method}`);
}

async function until(predicate) {
  const deadline = Date.now() + 10_000;
  let state;
  do {
    state = await call('snapshot');
    if (predicate(state)) return state;
    await delay(35);
  } while (Date.now() < deadline);
  assert.fail(`CHAT_STATE_NOT_OBSERVED:${JSON.stringify(state)}`);
}

try {
  assert.equal((await call('snapshot')).state, 'stopped');
  await call('send', { text: fixture.first }, 'IOS_CHAT_NOT_STARTED');
  await call('start', { apiKey: fixture.key, adapterFactory: 'not allowed' }, 'IOS_CHAT_BAD_REQUEST');
  assert.equal((await call('start', { apiKey: fixture.key })).state, 'ready');
  assert.equal((await call('send', { text: fixture.first })).state, 'running');
  await until((s) => s.state === 'running' && s.draft === 'ci-provider-stream-');
  const finished = await until((s) => s.state === 'ready');
  const history = [ { role: 'user', text: fixture.first }, { role: 'assistant', text: fixture.output } ];
  assert.deepEqual(finished.messages, history);
  assert.equal(finished.errorCode, null);
  assert.equal((await call('stop')).state, 'stopped');
  assert.deepEqual((await call('start', { apiKey: fixture.key })).messages, history);
  await call('send', { text: fixture.second });
  const second = await until((s) => s.state === 'ready');
  assert.deepEqual(second.messages, [ ...history, { role: 'user', text: fixture.second }, { role: 'assistant', text: fixture.output } ]);
  await call('send', { text: fixture.cancelled });
  await until((s) => s.state === 'running' && s.draft === 'ci-provider-stream-');
  assert.equal((await call('send', { text: 'not-admitted' })).errorCode, 'IOS_CHAT_BUSY');
  assert.equal((await call('cancel')).state, 'ready');
  assert.equal((await call('snapshot')).draft, '');
  await call('send', { text: fixture.invalid });
  const failed = await until((s) => s.state === 'ready');
  assert.equal(failed.errorCode, 'IOS_CHAT_AUTH_FAILED');
  assert.equal((await call('stop')).state, 'stopped');
  console.log('IOS_CHAT_OFFICIAL_PROVIDER_SSE_CANCEL_AND_REOPEN_VERIFIED');
} finally {
  await stop();
  await rm(scratch, { recursive: true, force: true });
}
