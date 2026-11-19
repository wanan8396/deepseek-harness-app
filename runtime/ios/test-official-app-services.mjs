import assert from 'node:assert/strict';
import { lstat, mkdtemp, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Standalone CI fixture: point this script at the locked, exported Host seed.
// The actual DSH adapter, registry, native executor, AgentLoop, and approval
// audit are used. Only upstream HTTPS and the browser's answer are simulated.
const seed = resolve(process.argv[2]);
const load = (file) => import(pathToFileURL(join(seed, file)).href);
const entry = (pkg) => `node_modules/@deepseek-ai/dsh-${pkg}/lib/index.js`;
const { boot } = await load(entry('app-boot'));
const { createUserMessage } = await load(entry('llm'));
const nativeListen = Server.prototype.listen;
const nativeConnect = Socket.prototype.connect;
const socketAttempts = [];
const { registerOfficialAppServices, officialAppModelSelection } = await load('official-app-services.mjs');
const rows = ['session-projection', 'session', 'system-prompt', 'tools', 'tool-executor-native', 'llm',
  'agent', 'agent-loop', 'user-approval'].map(pkg => ({ id: pkg, name: pathToFileURL(join(seed, entry(pkg))).href,
  ...(pkg === 'agent-loop' ? { config: { agents: [] } } : {}),
  ...(pkg === 'user-approval' ? { config: { policy: 'ask' } } : {}),
}));
const channel = Object.freeze({ protocol: 'openai-chat', baseUrl: 'https://models.example/v1', modelId: 'fixture-model' });
const apiKey = 'ci-test-only-not-a-credential';
const text = 'fixture 雪🧪\nsecond line\n';
const toolName = 'write';
const toolNames = ['edit', 'read', 'workspace_search', toolName];
const stateDirectory = await mkdtemp(join(await realpath(tmpdir()), 'dsh-ios-app-services-'));
const workspace = join(stateDirectory, 'Workspace');
const config = join(stateDirectory, 'cordis.json');
const lifetime = new AbortController();
const opts = { workspace, stateDirectory, channel, apiKey, lifetimeSignal: lifetime.signal };
const nativeFetch = globalThis.fetch;
let ctx;
let handle;
let services;
let answerMode;
let requestCount = 0;
const asks = [];
const events = [];
const calls = [];
const absent = (file) => assert.rejects(lstat(join(workspace, file)), { code: 'ENOENT' });

function sse(deltas, finishReason) {
  const frames = [...deltas.map(delta => ({ delta, finish_reason: null })), { delta: {}, finish_reason: finishReason }];
  return new Response(`${frames.map(choice => `data: ${JSON.stringify({ model: channel.modelId,
    choices: [{ index: 0, ...choice }] })}\n\n`).join('')}data: [DONE]\n\n`, {
    headers: { 'content-type': 'text/event-stream' },
  });
}

async function bounded(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('CI_APP_SERVICES_DEADLINE')), 5000);
    })]);
  } finally { clearTimeout(timer); }
}

try {
  assert.throws(() => officialAppModelSelection({ ...channel, baseUrl: `https://models.example/${apiKey}` }, apiKey), {
    code: 'IOS_CHAT_CHANNEL_INVALID',
  });
  assert.throws(() => officialAppModelSelection({ ...channel, baseUrl: `https://models.example/%63${apiKey.slice(1)}` }, apiKey), {
    code: 'IOS_CHAT_CHANNEL_INVALID',
  });
  assert.throws(() => officialAppModelSelection({ ...channel, baseUrl: 'http://models.example' }, apiKey), {
    code: 'IOS_CHAT_CHANNEL_INVALID',
  });
  const denySocket = kind => () => { socketAttempts.push(kind); throw new Error('CI_APP_SERVICES_NETWORK'); };
  Server.prototype.listen = denySocket('listen');
  Socket.prototype.connect = denySocket('connect');
  await writeFile(config, JSON.stringify(rows), { flag: 'wx', mode: 0o600 });
  ctx = await boot('dsh-ios-app-services-fixture', config, []);
  await assert.rejects(registerOfficialAppServices(ctx, { ...opts, workspace: join(stateDirectory, 'Other') }), {
    code: 'IOS_OFFICIAL_WORKSPACE_UNAVAILABLE',
  });
  await symlink(stateDirectory, workspace, 'dir');
  await assert.rejects(registerOfficialAppServices(ctx, opts), { code: 'IOS_OFFICIAL_WORKSPACE_UNAVAILABLE' });
  await rm(workspace);
  services = await registerOfficialAppServices(ctx, opts);
  const selection = officialAppModelSelection(channel, apiKey);
  assert.deepEqual(services.modelSelection, selection);
  assert.equal(services.containsSensitiveText(`prefix:${apiKey}`), true);
  assert.equal(services.containsSensitiveText(text), false);
  assert.equal((await ctx.get('llm').listModels(selection.provider))[0].id, channel.modelId);
  await assert.rejects(registerOfficialAppServices(ctx, opts), { code: 'IOS_OFFICIAL_APP_SERVICES_ALREADY_MOUNTED' });

  globalThis.fetch = async (url, init) => {
    requestCount++;
    assert.equal(String(url), `${channel.baseUrl}/chat/completions`);
    assert.equal(init.redirect, 'error');
    assert.equal(new Headers(init.headers).get('authorization'), `Bearer ${apiKey}`);
    assert.ok(!init.body.includes(apiKey));
    const { messages, model, tools } = JSON.parse(init.body);
    assert.equal(model, channel.modelId);
    assert.deepEqual(tools.map(item => item.function.name).sort(), toolNames);
    const callId = `ci-${answerMode}`;
    if (messages.some(message => message.role === 'tool' && message.tool_call_id === callId)) {
      return sse([{ role: 'assistant', content: 'ci-tools-complete' }], 'stop');
    }
    calls.push(callId);
    return sse([{ role: 'assistant' }, {
      tool_calls: [{ index: 0, id: callId, type: 'function', function: {
        name: toolName, arguments: JSON.stringify({ file_path: `${answerMode}.txt`, content: text }),
      } }],
    }], 'tool_calls');
  };
  ctx.on('session/event', (session, event) => { if (session.id === 'ci-official-app') events.push(event); });
  ctx.on('approval/request', async (request) => {
    const mode = answerMode;
    const preexisting = await lstat(join(workspace, `${mode}.txt`)).then(() => true, error => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (mode === 'cancel') lifetime.abort();
    asks.push({ request, preexisting, cancelled: request.signal.aborted });
    // On cancellation, deliver an explicit but late grant; it cannot authorize.
    return { deny: 'rejected', invalid: true, allow: 'allowed-once', cancel: 'allowed-once' }[mode];
  });
  handle = await ctx.get('agents').create({ sessionId: 'ci-official-app', meta: { cwd: services.workspace }, agentOptions: selection });
  assert.deepEqual(ctx.get('tools').definitions().map(tool => tool.name), []);
  assert.deepEqual(ctx.get('tools').definitions(handle.agent).map(tool => tool.name).sort(), toolNames);
  const outside = await ctx.get('agents').create({ sessionId: 'ci-outside-workspace', meta: { cwd: stateDirectory }, agentOptions: selection });
  try { assert.deepEqual(ctx.get('tools').definitions(outside.agent).map(tool => tool.name), []); }
  finally { await outside.dispose(); }
  for (answerMode of ['deny', 'invalid', 'allow', 'cancel']) {
    handle.agent.followup(createUserMessage({ content: [{ type: 'text', text: `fixture ${answerMode}` }], source: { kind: 'user' } }));
    await bounded(handle.agent.whenIdle());
    if (answerMode === 'allow') assert.equal(await readFile(join(workspace, 'allow.txt'), 'utf8'), text);
    else await absent(`${answerMode}.txt`);
  }
  assert.deepEqual(calls, ['ci-deny', 'ci-invalid', 'ci-allow', 'ci-cancel']);
  assert.equal(asks.length, 4);
  for (const [index, mode] of ['deny', 'invalid', 'allow', 'cancel'].entries()) {
    const { request, preexisting, cancelled } = asks[index];
    assert.equal(request.agent, handle.agent);
    assert.equal(request.callId, `ci-${mode}`);
    assert.equal(request.toolName, toolName);
    assert.equal(preexisting, false);
    assert.equal(cancelled, mode === 'cancel');
    assert.ok(Buffer.byteLength(request.displayReason.en) <= 1536);
    assert.ok(request.displayReason.en.includes(`${mode}.txt`));
    assert.ok(request.displayReason.en.includes('fixture 雪🧪'));
    assert.ok(!request.reason.includes(text) && !request.reason.includes(`${mode}.txt`));
  }
  assert.equal(requestCount, 7);
  const asked = events.filter(event => event.type === 'approval/asked').map(event => event.data);
  const decided = events.filter(event => event.type === 'approval/decided').map(event => event.data);
  assert.deepEqual(asked.map(item => item.callId), calls);
  assert.deepEqual(decided.map(item => item.id), asked.map(item => item.id));
  assert.deepEqual(decided.map(item => item.outcome), ['rejected', 'unavailable', 'allowed-once', 'cancelled']);
  assert.equal(new Set(asked.map(item => item.reason)).size, 1);
  assert.ok(asked.every(item => !Object.hasOwn(item, 'displayReason')));
  assert.ok(!JSON.stringify(events).includes(apiKey));
  await services.dispose();
  assert.ok(!ctx.get('llm').listProviders().some(provider => provider.id === selection.provider));
  assert.deepEqual(ctx.get('tools').definitions(handle.agent), []);
  await handle.dispose();
  handle = undefined;
  await ctx.fiber.dispose();
  ctx = undefined;
  assert.deepEqual(socketAttempts, []);
  console.log(JSON.stringify({ officialAppModelRouteVerified: true, officialNativeToolExecutionVerified: true,
    oneAuditPairPerCall: true, invalidAndLateGrantsDenied: true, toolMutationVerified: true, noSocketAttempts: true }));
} finally {
  try {
    await handle?.dispose();
    await services?.dispose();
    await ctx?.fiber.dispose();
  } finally {
    globalThis.fetch = nativeFetch;
    Server.prototype.listen = nativeListen;
    Socket.prototype.connect = nativeConnect;
    await rm(stateDirectory, { recursive: true, force: true });
  }
}
