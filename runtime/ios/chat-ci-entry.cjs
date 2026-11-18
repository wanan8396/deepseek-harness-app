'use strict';

// Tests only, never part of the unsigned App or enabled by an App request.
// Feed the official adapter a measured SSE response at its fetch boundary.
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');

const key = 'ci-test-only-not-a-credential';
const first = 'chat-ci-first';
const second = 'chat-ci-resumed';
const cancelled = 'chat-ci-cancel';
const invalid = 'chat-ci-auth-error';
const output = 'ci-provider-stream-complete';
const encoder = new TextEncoder();
const sse = (value) => encoder.encode(`event: ${value.type}\ndata: ${JSON.stringify(value)}\n\n`);

function installFetchFixture() {
  globalThis.fetch = async (url, init) => {
    try { return await respond(url, init); }
    catch (error) {
      // Debugging output exists only in this unshipped, credential-free test.
      console.error('IOS_CHAT_CI_HTTP_FIXTURE_FAILED', error.message);
      throw error;
    }
  };
  async function respond(url, init) {
    assert.equal(String(url), 'https://api.deepseek.com/anthropic/v1/messages');
    assert.equal(init.method, 'POST');
    assert.equal(init.redirect, 'error');
    const headers = new Headers(init.headers);
    assert.equal(headers.get('accept'), 'text/event-stream');
    assert.equal(headers.get('x-api-key'), key);
    assert.equal(headers.get('anthropic-version'), '2023-06-01');
    assert.match(headers.get('x-deepseek-harness-session-id'), /^[a-f0-9-]{36}$/);
    const { model, messages, stream, tools } = JSON.parse(init.body);
    assert.equal(model, 'deepseek-flash');
    assert.equal(stream, true);
    assert.ok(tools === undefined || tools.length === 0);
    const history = messages.map((message) => [message.role,
      message.content.filter((block) => block.type === 'text').map((block) => block.text).join('')]);
    const prompt = history.at(-1)[1];
    assert.deepEqual(history.at(-1), ['user', prompt]);
    assert.ok([first, second, cancelled, invalid].includes(prompt));
    if (prompt === second) {
      assert.deepEqual(history, [['user', first], ['assistant', output], ['user', second]]);
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
        put({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
        put({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'ci-provider-stream-' } });
        if (prompt === cancelled) return;
        timer = setTimeout(() => {
          dispose();
          put({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'complete' } });
          put({ type: 'content_block_stop', index: 0 });
          put({ type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 5 } });
          put({ type: 'message_stop' });
          controller.close();
        }, 1500);
      },
      cancel() { dispose(); },
    });
    return new Response(readable, { status: 200, headers: { 'content-type': 'text/event-stream' } });
  }
}

if (require.main === module) {
  // XCTest writes the visited App bundle's verified probe path into a private
  // test directory. The fixture lives in RunnerTests, not Runner.app resources.
  installFetchFixture();
  const probePath = require('node:fs').readFileSync(path.join(__dirname, 'probe-path.txt'), 'utf8');
  void require(probePath).main(process.argv[2]);
}
module.exports = { installFetchFixture, key, first, second, cancelled, invalid, output,
  bundled: (root, file) => import(pathToFileURL(path.join(root, file)).href) };
