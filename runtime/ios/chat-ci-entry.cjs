'use strict';

// Tests only, never part of the unsigned App or enabled by an App request.
// Exercise the actual adapters and AgentLoop; only the fetch boundary is replaced.
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');

const key = 'ci-test-only-not-a-credential';
const first = 'chat-ci-first';
const second = 'chat-ci-resumed';
const cancelled = 'chat-ci-cancel';
const invalid = 'chat-ci-auth-error';
const output = 'ci-provider-stream-complete';
const reasoning = 'ci-deepseek-private-reasoning';
const signature = 'ci-deepseek-private-signature';
const custom = Object.freeze({ apiKey: key, protocol: 'openai-chat', baseUrl: 'https://models.example/v1', modelId: 'fixture-model' });
const createTool = 'workspace_create_text';
const readTool = 'workspace_read_text';
const listTool = 'workspace_list';
const toolNames = [createTool, listTool, readTool];
const workspace = Object.freeze({
  deny: 'chat-ci-workspace-deny', allow: 'chat-ci-workspace-allow', cancel: 'chat-ci-workspace-cancel',
  deniedPath: 'denied.txt', allowedPath: 'allowed.txt', cancelledPath: 'cancelled.txt',
  text: 'fixture 雪🧪\nsecond line\n', byteLength: 28,
  preamble: 'ci-workspace-create-requested', complete: 'ci-workspace-tools-complete',
  denied: 'Error: The workspace file was not approved. No file was created.',
});
const encoder = new TextEncoder();
const sse = (value) => encoder.encode(`event: ${value.type}\ndata: ${JSON.stringify(value)}\n\n`);
const streamHeaders = { 'content-type': 'text/event-stream' };

function deepSeekResponse(init, headers) {
  assert.equal(headers.get('x-api-key'), key);
  assert.equal(headers.get('anthropic-version'), '2023-06-01');
  assert.match(headers.get('x-deepseek-harness-session-id'), /^[a-f0-9-]{36}$/);
  const { model, messages, stream, tools, thinking } = JSON.parse(init.body);
  assert.equal(model, 'deepseek-flash');
  assert.equal(stream, true);
  assert.deepEqual(thinking, { type: 'disabled' });
  assert.deepEqual(tools.map(({ name }) => name).sort(), toolNames);
  const history = messages.map((message) => [message.role,
    message.content.filter((block) => block.type === 'text').map((block) => block.text).join('')]);
  const prompt = history.at(-1)[1];
  assert.deepEqual(history.at(-1), ['user', prompt]);
  assert.ok([first, second, cancelled, invalid].includes(prompt));
  if (prompt === second) {
    assert.deepEqual(history, [['user', first], ['assistant', output], ['user', second]]);
    // Prove the genuine thinking block reached durable model history, even
    // though neither the UI snapshot nor the custom route may expose it.
    assert.deepEqual(messages[1].content, [
      { type: 'thinking', thinking: reasoning, signature }, { type: 'text', text: output },
    ]);
  }
  if (prompt === invalid) {
    // The adapter will see this body; it must not cross the product bridge.
    return new Response(JSON.stringify({ error: { type: 'authentication_error', message: key } }), {
      status: 401, headers: { 'content-type': 'application/json' },
    });
  }
  let timer;
  let dispose;
  const readable = new ReadableStream({
    start(controller) {
      const put = (value) => controller.enqueue(sse(value));
      const abort = () => { dispose(); controller.error(init.signal.reason); };
      dispose = () => { clearTimeout(timer); init.signal.removeEventListener('abort', abort); };
      if (init.signal.aborted) { abort(); return; }
      init.signal.addEventListener('abort', abort, { once: true });
      put({ type: 'message_start', message: { usage: { input_tokens: 8 } } });
      const index = Number(prompt === first);
      if (index) {
        put({ type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: '' } });
        put({ type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: reasoning } });
        put({ type: 'content_block_delta', index: 0, delta: { type: 'signature_delta', signature } });
        put({ type: 'content_block_stop', index: 0 });
      }
      put({ type: 'content_block_start', index, content_block: { type: 'text', text: '' } });
      put({ type: 'content_block_delta', index, delta: { type: 'text_delta', text: 'ci-provider-stream-' } });
      if (prompt === cancelled) return;
      timer = setTimeout(() => {
        dispose();
        put({ type: 'content_block_delta', index, delta: { type: 'text_delta', text: 'complete' } });
        put({ type: 'content_block_stop', index });
        put({ type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 5 } });
        put({ type: 'message_stop' });
        controller.close();
      }, 1500);
    },
    cancel() { dispose(); },
  });
  return new Response(readable, { headers: streamHeaders });
}

const createCall = (id, file) => ({ id, name: createTool, args: { path: file, text: workspace.text } });
const denyCall = createCall('call_ci_deny', workspace.deniedPath);
const allowCall = createCall('call_ci_allow', workspace.allowedPath);
const cancelCall = createCall('call_ci_cancel', workspace.cancelledPath);
const readCall = { id: 'call_ci_read', name: readTool, args: { path: workspace.allowedPath } };
const listCall = { id: 'call_ci_list', name: listTool, args: { path: '.' } };

function openAiSse(deltas, reason, model = custom.modelId) {
  const frames = [ ...deltas.map((delta) => ({ delta, finish_reason: null })), { delta: {}, finish_reason: reason } ];
  return new Response(new ReadableStream({
    start(controller) {
      for (const choice of frames) {
        const chunk = { id: 'chatcmpl-ci', object: 'chat.completion.chunk', created: 1, model,
          choices: [{ index: 0, ...choice }] };
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(chunk)}\n\n`));
      }
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  }), { headers: streamHeaders });
}

function issueCall({ id, name, args }, content, model = custom.modelId) {
  const json = JSON.stringify(args);
  const split = Math.floor(json.length / 2);
  return openAiSse([
    { role: 'assistant', content: content ?? null },
    { tool_calls: [{ index: 0, id, type: 'function', function: { name, arguments: json.slice(0, split) } }] },
    { tool_calls: [{ index: 0, function: { arguments: json.slice(split) } }] },
  ], 'tool_calls', model);
}

function expectToolResult(messages, { id, name, args }, expected, content = null) {
  const [assistant, result] = messages;
  assert.deepEqual(assistant, { role: 'assistant', content,
    tool_calls: [{ id, type: 'function', function: { name, arguments: JSON.stringify(args) } }] });
  assert.equal(result.role, 'tool');
  assert.equal(result.tool_call_id, id);
  assert.deepEqual(typeof expected === 'string' ? result.content : JSON.parse(result.content), expected);
}

function customResponse(init, headers) {
  assert.equal(headers.get('authorization'), `Bearer ${key}`);
  assert.equal(headers.get('x-api-key'), null);
  assert.equal(headers.get('content-type'), 'application/json');
  for (const forbidden of [key, reasoning, signature]) assert.ok(!init.body.includes(forbidden));
  const { model, messages, stream, tools } = JSON.parse(init.body);
  assert.equal(model, custom.modelId);
  assert.equal(stream, true);
  assert.ok(messages.some(message => message.role === 'assistant' && message.content === output), 'TEXT_HISTORY_MISSING');
  assert.deepEqual(tools.map(({ type, function: tool }) => {
    assert.equal(type, 'function');
    assert.equal(tool.parameters.type, 'object');
    const properties = Object.keys(tool.parameters.properties).sort();
    assert.deepEqual(properties, tool.name === createTool ? ['path', 'text'] : ['path']);
    assert.ok(properties.every((name) => tool.parameters.properties[name].type === 'string'));
    return tool.name;
  }).sort(), toolNames);
  const index = messages.findLastIndex(({ role, content }) => role === 'user'
    && [workspace.deny, workspace.allow, workspace.cancel].includes(content));
  assert.ok(index >= 0, 'WORKSPACE_PROMPT_MISSING');
  const prompt = messages[index].content;
  // An official route-switch notice can follow the first custom user message.
  const followups = messages.slice(index + 1).filter(({ role, content }) => role !== 'system'
    && !(role === 'user' && content.startsWith('[model changed: ')));
  const done = () => openAiSse([{ role: 'assistant', content: workspace.complete }], 'stop');
  if (prompt === workspace.deny) {
    if (!followups.length) return issueCall(denyCall);
    assert.equal(followups.length, 2);
    expectToolResult(followups, denyCall, workspace.denied);
    return done();
  }
  if (prompt === workspace.cancel) {
    assert.equal(followups.length, 0, 'CANCELLED_APPROVAL_REENTERED_MODEL');
    return issueCall(cancelCall);
  }
  if (!followups.length) return issueCall(allowCall, workspace.preamble);
  assert.ok([2, 4, 6].includes(followups.length));
  const { allowedPath: path, text, byteLength } = workspace;
  expectToolResult(followups, allowCall, { path, byteLength }, workspace.preamble);
  if (followups.length === 2) return issueCall(readCall);
  expectToolResult(followups.slice(2), readCall, { path, text, byteLength });
  if (followups.length === 4) return issueCall(listCall);
  expectToolResult(followups.slice(4), listCall, { path: '.', entries: [{ name: path, kind: 'file' }], truncated: false });
  return done();
}

const officialModel = 'ios-production-fixture';
const officialKey = 'ios-prod-ci-not-a-credential';
const officialPrompt = 'official-tool-fixture';
const officialCall = { id: 'call_ios_prod_ci', name: 'write',
  args: { file_path: 'official-approved.txt', content: 'official simulator approved\n' } };
function officialResponse(init, headers) {
  assert.equal(headers.get('authorization'), `Bearer ${officialKey}`);
  assert.ok(!init.body.includes(officialKey));
  const { model, messages, stream, tools } = JSON.parse(init.body);
  assert.equal(model, officialModel);
  assert.equal(stream, true);
  assert.deepEqual(tools.map(item => item.function.name).sort(), ['edit', 'read', 'workspace_search', 'write']);
  const index = messages.findLastIndex(message => message.role === 'user' && message.content === officialPrompt);
  assert.ok(index >= 0, 'OFFICIAL_COMPOSER_PROMPT_UNKNOWN');
  const follow = messages.slice(index + 1).filter(message => message.role !== 'system');
  const tool = follow.findIndex(message => message.role === 'tool' && message.tool_call_id === officialCall.id);
  if (tool === -1) return issueCall(officialCall, null, officialModel);
  expectToolResult(follow.slice(tool - 1, tool + 1), officialCall,
    `<path>/workspace/${officialCall.args.file_path}</path>\n<type>file</type>\n<content>\nCreated file\n</content>`);
  return openAiSse([{ role: 'assistant', content: 'official-tool-result' }], 'stop', officialModel);
}

function installFetchFixture() {
  let calls = 0;
  globalThis.fetch = async (url, init) => {
    calls++;
    try {
      assert.equal(init.method, 'POST');
      assert.equal(init.redirect, 'error');
      const headers = new Headers(init.headers);
      assert.equal(headers.get('accept'), 'text/event-stream');
      if (String(url) === 'https://api.deepseek.com/anthropic/v1/messages') return deepSeekResponse(init, headers);
      if (String(url) === 'https://official-ios-ci.invalid/v1/chat/completions') return officialResponse(init, headers);
      assert.equal(String(url), `${custom.baseUrl}/chat/completions`);
      return customResponse(init, headers);
    } catch (error) {
      // Debugging output exists only in this unshipped, credential-free test.
      console.error('IOS_CHAT_CI_HTTP_FIXTURE_FAILED', error.message);
      throw error;
    }
  };
  return () => calls;
}

if (require.main === module) {
  // XCTest writes the visited App bundle's verified probe path into a private
  // test directory. The fixture lives in RunnerTests, not Runner.app resources.
  installFetchFixture();
  const fs = require('node:fs');
  const probePath = fs.readFileSync(path.join(__dirname, 'probe-path.txt'), 'utf8');
  const hostPath = fs.readFileSync(path.join(__dirname, 'official-host-path.txt'), 'utf8');
  const report = process.argv[2];
  void require(probePath).main(report).then(async () => {
    const { serveOfficialHostCi } = await import(pathToFileURL(path.join(hostPath, 'official-host-ci-mailbox.mjs')).href);
    await serveOfficialHostCi(hostPath, report);
  }).catch(error => {
    console.error('IOS_OFFICIAL_HOST_CI_ERROR', error);
    try { fs.writeFileSync(path.join(__dirname, 'official-host-ci-error'), String(error), { mode: 0o600 }); }
    catch (writeError) { console.error('IOS_OFFICIAL_HOST_CI_ERROR_REPORT_FAILED', writeError.code); }
  });
}
module.exports = { installFetchFixture, key, first, second, cancelled, invalid, output, reasoning, signature, custom, workspace,
  bundled: (root, file) => import(pathToFileURL(path.join(root, file)).href) };
