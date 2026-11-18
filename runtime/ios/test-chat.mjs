import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
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
assert.deepEqual(manifest.files.map(({ path }) => path).filter((path) => !path.startsWith('node_modules/')).sort(), [
  'chat-approval.mjs', 'chat-deepseek-provider.mjs', 'chat-engine.mjs', 'chat-mailbox.mjs',
  'chat-model-channel.mjs', 'chat-workspace-tools.mjs', 'sqlite-session-persistence.mjs',
]);
await mkdir(mailbox, { mode: 0o700 });
const fetchCount = fixture.installFetchFixture();
const { startChatMailbox } = await fixture.bundled(bundle, 'chat-mailbox.mjs');
const stop = startChatMailbox(report, { pollMs: 25 });
const workspaceRoot = join(scratch, 'ChatData', 'Workspace');

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
    assert.ok(!raw.includes(fixture.reasoning) && !raw.includes(fixture.signature), 'DEEPSEEK_REASONING_PRESENT_IN_CHAT_REPLY');
    assert.ok(!(await readdir(mailbox)).includes(`request-${id}.json`), 'REQUEST_NOT_CONSUMED');
    const value = JSON.parse(raw);
    assert.equal(value.id, id);
    if (expectedError) { assert.deepEqual(value, { id, errorCode: expectedError }); return; }
    assert.equal(value.errorCode, undefined, `${method}:${JSON.stringify(value)}`);
    assert.deepEqual(Object.keys(value.result).sort(), ['approval', 'draft', 'errorCode', 'messages', 'state']);
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

async function expectMissing(path) {
  await assert.rejects(lstat(join(workspaceRoot, path)), { code: 'ENOENT' });
}

async function expectApproval(path) {
  const { state, approval, errorCode } = await until((s) => s.approval !== null || s.state === 'ready');
  assert.equal(state, 'running');
  assert.equal(errorCode, null);
  assert.match(approval?.id, /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.deepEqual(approval, { id: approval.id, toolName: 'workspace_create_text', path,
    byteLength: fixture.workspace.byteLength, preview: fixture.workspace.text, previewTruncated: false });
  await expectMissing(path);
  return approval;
}

try {
  assert.deepEqual(await call('snapshot'), { state: 'stopped', messages: [], draft: '', errorCode: null, approval: null });
  await call('send', { text: fixture.first }, 'IOS_CHAT_NOT_STARTED');
  await call('start', { apiKey: fixture.key, adapterFactory: 'not allowed' }, 'IOS_CHAT_BAD_REQUEST');
  assert.equal((await call('start', { apiKey: fixture.key })).state, 'ready');
  assert.equal((await call('send', { text: fixture.first })).state, 'running');
  await until((s) => s.state === 'running' && s.draft === 'ci-provider-stream-');
  const finished = await until((s) => s.state === 'ready');
  const history = [ { role: 'user', text: fixture.first }, { role: 'assistant', text: fixture.output } ];
  assert.deepEqual(finished.messages, history);
  assert.equal(finished.errorCode, null);
  assert.equal(finished.approval, null);
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

  const { deny, allow, cancel, deniedPath, allowedPath, cancelledPath, text, byteLength, preamble, complete, denied } = fixture.workspace;
  const expectedBytes = Buffer.from(text, 'utf8');
  assert.equal(expectedBytes.length, byteLength);
  const callsBeforeCustom = fetchCount();
  await call('start', { ...fixture.custom, baseUrl: 'http://models.example/v1' }, 'IOS_CHAT_CHANNEL_INVALID');
  assert.equal((await call('snapshot')).state, 'stopped');
  assert.equal(fetchCount(), callsBeforeCustom);
  const customStarted = await call('start', fixture.custom);
  assert.equal(customStarted.state, 'ready');
  assert.equal(customStarted.approval, null);
  assert.deepEqual(customStarted.messages, failed.messages);
  assert.deepEqual(await readdir(workspaceRoot), []);
  assert.equal(fetchCount(), callsBeforeCustom);

  await call('send', { text: deny });
  const deniedApproval = await expectApproval(deniedPath);
  const wrongId = '00000000-0000-4000-8000-000000000000';
  await call('answerApproval', { id: wrongId, allowed: true }, 'IOS_CHAT_APPROVAL_STALE');
  assert.deepEqual((await call('snapshot')).approval, deniedApproval);
  await expectMissing(deniedPath);
  assert.equal((await call('answerApproval', { id: deniedApproval.id, allowed: false })).approval, null);
  const deniedTurn = await until((s) => s.state === 'ready');
  assert.equal(deniedTurn.errorCode, null);
  assert.equal(deniedTurn.approval, null);
  assert.deepEqual(deniedTurn.messages, [...customStarted.messages, { role: 'user', text: deny },
    { role: 'tool', text: denied }, { role: 'assistant', text: complete }]);
  await expectMissing(deniedPath);

  await call('send', { text: allow });
  const allowedApproval = await expectApproval(allowedPath);
  assert.notEqual(allowedApproval.id, deniedApproval.id);
  await call('answerApproval', { id: deniedApproval.id, allowed: true }, 'IOS_CHAT_APPROVAL_STALE');
  assert.deepEqual((await call('snapshot')).approval, allowedApproval);
  await expectMissing(allowedPath);
  assert.equal((await call('answerApproval', { id: allowedApproval.id, allowed: true })).approval, null);
  const allowedTurn = await until((s) => s.state === 'ready');
  assert.equal(allowedTurn.errorCode, null);
  assert.equal(allowedTurn.approval, null);
  const toolMessage = (value) => ({ role: 'tool', text: JSON.stringify(value) });
  assert.deepEqual(allowedTurn.messages, [...deniedTurn.messages, { role: 'user', text: allow },
    { role: 'assistant', text: preamble }, toolMessage({ path: allowedPath, byteLength }),
    toolMessage({ path: allowedPath, text, byteLength }),
    toolMessage({ path: '.', entries: [{ name: allowedPath, kind: 'file' }], truncated: false }),
    { role: 'assistant', text: complete }]);
  assert.deepEqual(await readFile(join(workspaceRoot, allowedPath)), expectedBytes);
  assert.equal(fetchCount() - callsBeforeCustom, 6); // 2 deny requests; 4 create/read/list/final requests.

  await call('send', { text: cancel });
  const cancelledApproval = await expectApproval(cancelledPath);
  const cancelledTurn = await call('cancel');
  assert.equal(cancelledTurn.state, 'ready');
  assert.equal(cancelledTurn.approval, null);
  await call('answerApproval', { id: cancelledApproval.id, allowed: true }, 'IOS_CHAT_APPROVAL_STALE');
  await expectMissing(cancelledPath);
  assert.equal(fetchCount() - callsBeforeCustom, 7);

  assert.equal((await call('stop')).state, 'stopped');
  const reopened = await call('start', fixture.custom);
  assert.equal(reopened.state, 'ready');
  assert.equal(reopened.approval, null);
  assert.deepEqual(reopened.messages, cancelledTurn.messages);
  assert.deepEqual(reopened.messages.slice(0, allowedTurn.messages.length), allowedTurn.messages);
  assert.deepEqual(await readFile(join(workspaceRoot, allowedPath)), expectedBytes);
  assert.deepEqual(await readdir(workspaceRoot), [allowedPath]);
  assert.equal(fetchCount() - callsBeforeCustom, 7); // Reopening must neither rerun tools nor call the model.
  assert.equal((await call('stop')).state, 'stopped');
  console.log('IOS_CHAT_CUSTOM_HTTPS_TOOL_RESULTS_APPROVAL_AND_REOPEN_VERIFIED');
} finally {
  await stop();
  await rm(scratch, { recursive: true, force: true });
}
