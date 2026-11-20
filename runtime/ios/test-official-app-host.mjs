import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lstat, mkdtemp, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const seed = resolve(process.argv[2]);
const { createOfficialHost } = await import(pathToFileURL(join(seed, 'official-host.mjs')).href);
const directory = await mkdtemp(join(await realpath(tmpdir()), 'dsh-ios-official-app-host-'));
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
const deadline = setTimeout(() => control.abort(new Error('App Host fixture timed out')), 10_000);
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
  const prompt = { requestId: randomUUID(), sessionId, mode: 'queue', content: [{ type: 'text', text: apiKey }] };
  assert.equal((await query('session/prompt', { request: prompt })).status, 400);
  const follow = await host.openStream('session/follow', { args: { request: { address: { kind: 'session', sessionId } } } },
    AbortSignal.any([control.signal, AbortSignal.timeout(4000)]));
  stream = follow[Symbol.asyncIterator]();
  assert.equal((await stream.next()).value.header.id, sessionId);
  const sessions = (await rpc('session/list', { _request: {} })).items;
  assert.equal(sessions.find(row => row.sessionId === sessionId)?.cwd, host.appWorkspace);

  const filename = 'approved-host-fixture.txt';
  const virtualPath = `/workspace/${filename}`;
  const file = join(host.appWorkspace, filename);
  const initial = 'official Host fixture 雪\n';
  const outside = join(directory, 'outside.txt');
  const unread = join(host.appWorkspace, 'unread.txt');
  await writeFile(outside, 'private sentinel\n');
  await writeFile(unread, 'unread sentinel\n');
  await symlink(outside, join(host.appWorkspace, 'outside-link.txt'));
  const plan = [
    ['write', { file_path: filename, content: initial }, 'Created file'],
    ['write', { file_path: 'unread.txt', content: 'denied clobber' }, 'file has not been read'],
    ['edit', { file_path: 'unread.txt', old_string: 'unread', new_string: 'denied edit' }, 'file has not been read'],
    ['read', { file_path: '/workspace/unread.txt' }, '1: unread sentinel'],
    ['edit', { file_path: 'unread.txt', old_string: 'unread', new_string: 'edited' }, 'has been updated successfully'],
    ['write', { file_path: filename, content: 'denied replacement' }, 'The Workspace change was not approved'],
    ['read', { file_path: '../outside.txt' }, 'outside the private Workspace capability'],
    ['write', { file_path: 'outside-link.txt', content: 'denied escape' }, 'outside the private Workspace capability'],
    ['workspace_search', { mode: 'text', query: 'edited sentinel' }, '{"matches":[{"path":"/workspace/unread.txt","lines":[1]}],"truncated":false}'],
  ].map(([name, args, contains], index) => ({ name, args, contains, id: `ci-host-${index}` }));
  // The fixture substitutes only the upstream model and answers through the
  // real App Host's approval event stream.
  const fixtureFailure = Promise.withResolvers();
  fixtureFailure.promise.catch(() => {});
  const steps = new Set();
  globalThis.fetch = async (url, init) => {
    try {
      assert.equal(String(url), 'https://models.example/v1/chat/completions');
      assert.equal(new Headers(init.headers).get('authorization'), `Bearer ${apiKey}`);
      const body = JSON.parse(init.body);
      assert.equal(body.model, appChannel.channel.modelId);
      assert(!init.body.includes(apiKey));
      const tools = body.tools.map(item => item.function);
      assert.deepEqual(tools.map(tool => tool.name).sort(), ['edit', 'read', 'workspace_search', 'write']);
      assert(tools.every(tool => !Object.hasOwn(tool.parameters.properties, 'sandbox_permissions')));
      const results = body.messages.filter(message => message.role === 'tool');
      assert(results.length <= plan.length && !steps.has(results.length));
      steps.add(results.length);
      for (const [index, result] of results.entries()) {
        assert.equal(result.tool_call_id, plan[index].id);
        assert(result.content.includes(plan[index].contains), result.content);
        assert(!result.content.includes(directory) && !result.content.includes('private sentinel'));
      }
      if (results.length >= 1) assert(results[0].content.includes(virtualPath));
      if (results.length >= 4) assert(results[3].content.includes('/workspace/unread.txt'));
      const call = plan[results.length];
      const delta = call ? { role: 'assistant', tool_calls: [{ index: 0, id: call.id, type: 'function', function: {
        name: call.name, arguments: JSON.stringify(call.args),
      } }] } : { role: 'assistant', content: 'approved-result-fixture' };
      const frame = (value, finish_reason) => `data: ${JSON.stringify({ model: body.model,
        choices: [{ index: 0, delta: value, finish_reason }] })}\n\n`;
      return new Response(`${frame(delta, null)}${frame({}, call ? 'tool_calls' : 'stop')}data: [DONE]\n\n`, {
        headers: { 'content-type': 'text/event-stream' },
      });
    } catch (error) {
      fixtureFailure.reject(error);
      throw error;
    }
  };
  const fixtureSignal = control.signal;
  const eventSource = await host.openStream('$events', { args: {} }, fixtureSignal);
  eventStream = eventSource[Symbol.asyncIterator]();
  const nextEvent = () => Promise.race([eventStream.next(), fixtureFailure.promise]);
  const ready = (await nextEvent()).value;
  assert.equal(ready.type, 'ready');
  const sender = await rpc('session/prompt', { request: { ...prompt, requestId: randomUUID(), content: [{ type: 'text', text: 'tool fixture' }] } });
  assert.equal(sender.accepted, true);
  for (const [index, target, before, value] of [
    [0, file, null, 'allowed-once'], [4, unread, 'unread sentinel\n', 'allowed-once'], [5, file, initial, 'rejected'],
  ]) {
    let ask;
    while (!ask) {
      const item = await nextEvent();
      assert.equal(item.done, false);
      if (item.value.type === 'waterfall' && item.value.event === 'approval/request') ask = item.value;
    }
    assert.equal(ask.agentId, sessionId);
    assert.equal(ask.request.toolName, plan[index].name);
    assert.equal(ask.request.callId, plan[index].id);
    assert(ask.request.displayReason.en.includes(`/workspace/${plan[index].args.file_path}`));
    assert(!ask.request.displayReason.en.includes(directory));
    if (before === null) await assert.rejects(lstat(target), { code: 'ENOENT' });
    else assert.equal(await readFile(target, 'utf8'), before);
    await rpc('$events/result', { clientId: ready.clientId, eventId: ask.eventId, outcome: { kind: 'result', value } });
  }
  const journal = await host.openStream('session/follow', { args: { request: { address: { kind: 'session', sessionId } } } }, fixtureSignal);
  const complete = async () => {
    for await (const frame of journal) if (JSON.stringify(frame).includes('approved-result-fixture')) return;
    assert.fail('App Host did not publish the fixture completion');
  };
  await Promise.race([complete(), fixtureFailure.promise]);
  assert.equal(await readFile(file, 'utf8'), initial);
  assert.equal(await readFile(unread, 'utf8'), 'edited sentinel\n');
  assert.equal(await readFile(outside, 'utf8'), 'private sentinel\n');
  assert.equal(steps.size, plan.length + 1);
  assert.deepEqual(attempts, []);
  console.log(JSON.stringify({ officialAppHostPolicyVerified: true, officialModelCatalogVerified: true,
    privateWorkspaceVerified: true, secretNotAdmitted: true, nativeToolAndEventAnswerVerified: true,
    officialReadWriteEditVerified: true, boundedWorkspaceSearchVerified: true, escapeDenied: true,
     attachmentReceiptsWithheld: true, noSocketAttempts: true }));
} finally {
  clearTimeout(deadline);
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
