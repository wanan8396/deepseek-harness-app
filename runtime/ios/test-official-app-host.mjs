import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lstat, mkdtemp, readFile, realpath, rm } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const seed = resolve(process.argv[2]);
const { createOfficialHost } = await import(pathToFileURL(join(seed, 'official-host.mjs')).href);
const directory = await mkdtemp(join(tmpdir(), 'dsh-ios-official-app-host-'));
const apiKey = 'cloud-fixture-secret-not-a-credential';
const appChannel = { channel: { protocol: 'openai-chat', baseUrl: 'https://models.example/v1', modelId: 'test-local-model' }, apiKey };
const attempts = [];
const original = { fetch: globalThis.fetch, listen: Server.prototype.listen, connect: Socket.prototype.connect };
const deny = name => () => { attempts.push(name); throw new Error(`test unexpectedly attempted ${name}`); };
Server.prototype.listen = deny('listen');
Socket.prototype.connect = deny('connect');
globalThis.fetch = deny('fetch');
let host;
let stream;
let eventStream;
const control = new AbortController();
function query(method, args) {
  return host.fetch(new Request(`dsh-app://bundle/api/${method}`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method, payload: { args } }) }));
}
async function rpc(method, args) {
  const response = await query(method, args);
  assert.equal(response.status, 200, method);
  const reply = await response.json();
  assert.equal(reply.result.ok, true, `${method}: ${JSON.stringify(reply.result)}`);
  return reply.result.value;
}
try {
  host = await createOfficialHost({ seed, stateDirectory: directory, appChannel });
  assert.equal(host.appWorkspace, await realpath(join(directory, 'Workspace')));
  const catalog = await rpc('session/modelCatalog', {});
  assert.deepEqual(catalog.default, { provider: 'ios-custom', model: appChannel.channel.modelId });
  assert.equal(catalog.groups[0].models[0].id, appChannel.channel.modelId);
  assert.equal((await query('session/create', { request: { cwd: directory } })).status, 403);
  assert.equal((await query('file', {})).status, 404);
  const { sessionId } = await rpc('session/create', { request: {} });
  const document = 'Original attached text fixture 雪\n';
  const upload = { agentId: sessionId, request: { name: 'reference.txt', data: Buffer.from(document).toString('base64') } };
  assert.equal((await query('fileUploads/upload', { ...upload, agentId: 'session-550e8400-e29b-41d4-a716-446655440001' })).status, 403);
  assert.equal((await query('fileUploads/upload', { ...upload, request: { ...upload.request, name: '../reference.txt' } })).status, 415);
  assert.equal((await query('fileUploads/upload', { ...upload, request: { ...upload.request, name: 'image.png' } })).status, 415);
  assert.equal((await query('fileUploads/upload', { ...upload, request: { ...upload.request, data: Buffer.from(apiKey).toString('base64') } })).status, 415);
  const fileReceipt = await rpc('fileUploads/upload', upload);
  assert.equal(fileReceipt.file.name, 'reference.txt');
  assert.equal(fileReceipt.file.bytes, Buffer.byteLength(document));
  assert.match(fileReceipt.file.attachmentId, /^sha256:[a-f0-9]{64}$/u);
  const other = await rpc('session/create', { request: {} });
  const crossSession = await query('session/prompt', { request: { requestId: randomUUID(), sessionId: other.sessionId,
    mode: 'queue', content: [{ type: 'file', receiptId: fileReceipt.receiptId }] } });
  assert.equal(crossSession.status, 200);
  assert.equal((await crossSession.json()).result.ok, false, 'Receipt must be scoped to its originating session');
  const prompt = { requestId: randomUUID(), sessionId, mode: 'queue', content: [{ type: 'text', text: apiKey }] };
  assert.equal((await query('session/prompt', { request: prompt })).status, 400);
  const follow = await host.openStream('session/follow', { args: { request: { address: { kind: 'session', sessionId } } } },
    AbortSignal.any([control.signal, AbortSignal.timeout(4000)]));
  stream = follow[Symbol.asyncIterator]();
  assert.equal((await stream.next()).value.header.id, sessionId);
  const sessions = (await rpc('session/list', { _request: {} })).items;
  assert.equal(sessions.find(row => row.sessionId === sessionId)?.cwd, host.appWorkspace);

  let calls = 0;
  const toolId = 'ci-host-approval-1';
  const filename = 'approved-host-fixture.txt';
  const expected = 'official Host approval fixture 雪\n';
  globalThis.fetch = async (url, init) => {
    calls++;
    assert.equal(String(url), 'https://models.example/v1/chat/completions');
    assert.equal(new Headers(init.headers).get('authorization'), `Bearer ${apiKey}`);
    const body = JSON.parse(init.body);
    assert.equal(body.model, appChannel.channel.modelId);
    assert(!init.body.includes(apiKey));
    assert.ok(body.messages.some(message => message.role === 'user' && message.content.includes(document)),
      'Verified text attachment did not reach the actual model adapter');
    assert.ok(body.messages.every(message => message.role !== 'user' || typeof message.content !== 'string'
      || !message.content.includes('/attachments/v1/')));
    const response = body.messages.some(message => message.role === 'tool' && message.tool_call_id === toolId)
      ? { delta: { role: 'assistant', content: 'approved-result-fixture' }, finish_reason: 'stop' }
      : { delta: { role: 'assistant', tool_calls: [{ index: 0, id: toolId, type: 'function', function: {
        name: 'workspace_create_text', arguments: JSON.stringify({ path: filename, text: expected }),
      } }] }, finish_reason: 'tool_calls' };
    return new Response(`data: ${JSON.stringify({ model: body.model, choices: [{ index: 0,
      delta: response.delta, finish_reason: null }] })}\n\ndata: ${JSON.stringify({ model: body.model, choices: [{ index: 0,
      delta: {}, finish_reason: response.finish_reason }] })}\n\ndata: [DONE]\n\n`, { headers: { 'content-type': 'text/event-stream' } });
  };
  const eventSource = await host.openStream('$events', { args: {} }, AbortSignal.any([control.signal, AbortSignal.timeout(7000)]));
  eventStream = eventSource[Symbol.asyncIterator]();
  const ready = (await eventStream.next()).value;
  assert.equal(ready.type, 'ready');
  const sender = await rpc('session/prompt', { request: { ...prompt, requestId: randomUUID(),
    content: [{ type: 'text', text: 'tool fixture' }, { type: 'file', receiptId: fileReceipt.receiptId }] } });
  assert.equal(sender.accepted, true);
  let ask;
  while (!ask) {
    const item = await eventStream.next();
    assert.equal(item.done, false);
    if (item.value.type === 'waterfall' && item.value.event === 'approval/request') ask = item.value;
  }
  assert.equal(ask.agentId, sessionId);
  assert.equal(ask.request.toolName, 'workspace_create_text');
  assert.equal(ask.request.callId, toolId);
  assert(ask.request.displayReason.en.includes(filename));
  const file = join(host.appWorkspace, filename);
  await assert.rejects(lstat(file), { code: 'ENOENT' });
  await rpc('$events/result', { clientId: ready.clientId, eventId: ask.eventId, outcome: { kind: 'result', value: 'allowed-once' } });
  const journal = await host.openStream('session/follow', { args: { request: { address: { kind: 'session', sessionId } } } },
    AbortSignal.any([control.signal, AbortSignal.timeout(7000)]));
  for await (const frame of journal) {
    if (JSON.stringify(frame).includes('approved-result-fixture')) break;
  }
  assert.equal(await readFile(file, 'utf8'), expected);
  assert.equal(calls, 2);
  assert.deepEqual(attempts, []);
  console.log(JSON.stringify({ officialAppHostPolicyVerified: true, officialModelCatalogVerified: true,
    privateWorkspaceVerified: true, secretNotAdmitted: true, nativeToolAndEventAnswerVerified: true,
    officialFileReceiptVerified: true, attachmentContentReachedModel: true, noSocketAttempts: true }));
} finally {
  control.abort();
  try { await Promise.allSettled([stream?.return?.(), eventStream?.return?.()]); }
  finally {
    try { await host?.dispose(); }
    finally {
      Server.prototype.listen = original.listen;
      Socket.prototype.connect = original.connect;
      globalThis.fetch = original.fetch;
      await rm(directory, { recursive: true, force: true });
    }
  }
}
