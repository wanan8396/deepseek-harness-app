import { Buffer } from 'node:buffer';
import { chmod, lstat, mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { boot } from '@deepseek-ai/dsh-app-boot';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';
import { SessionPersistence } from '@deepseek-ai/dsh-session-persistence';
import {
  CHAT_ENDPOINT, CHAT_MAX_TOKENS, CHAT_MODEL, CHAT_PROVIDER,
  chatFailureCode, chatStream, createDeepSeekAdapter,
} from './chat-deepseek-provider.mjs';

// The private database is the namespace for this one App-owned conversation.
// A reserved id needs no second durable index or crash-prone identity sidecar.
const SESSION = SessionId('887b19df-46de-41ac-8ba1-fafb63957a5c');
const roots = [
  ['session-projection', 'dsh-session-projection'], ['session', 'dsh-session'],
  ['system-prompt', 'dsh-system-prompt', { includeHarnessIdentity: false, includeRuntimeContext: false,
    personaPrefix: 'You are a helpful assistant in the DeepSeek iOS chat app. Reply in text.' }],
  ['tools', 'dsh-tools'], ['tool-executor-native', 'dsh-tool-executor-native'], ['llm', 'dsh-llm'],
  ['agent', 'dsh-agent'], ['agent-loop', 'dsh-agent-loop', { agents: [] }],
  ['session-checkpoint-policy', 'dsh-session-checkpoint-policy'],
];
const MAX_PROMPT_BYTES = 8192;
const MAX_TEXT_BYTES = 12 * 1024;
const MAX_MESSAGES = 40;
const SNAPSHOT_BYTES = 48 * 1024;

function chatError(code) { return Object.assign(new Error(code), { code }); }
function byteLength(value) { return Buffer.byteLength(value, 'utf8'); }
function jsonBytes(value) { return byteLength(JSON.stringify(value)); }

// Bound the serialized JSON, not only JS string length. Control characters
// cost six bytes and emoji up to four; do not emit half a surrogate pair.
function clip(text, limit) {
  text = text.slice(0, limit).toWellFormed();
  if (jsonBytes(text) <= limit) return text;
  let lo = 0;
  let hi = text.length;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (jsonBytes(text.slice(0, mid)) <= limit) lo = mid;
    else hi = mid - 1;
  }
  if (lo > 0 && /[\uD800-\uDBFF]/u.test(text[lo - 1])) lo--;
  return text.slice(0, lo);
}

function textOf(message) {
  return message.content.filter(block => block.type === 'text').map(block => block.text).join('');
}

function buildRows(directory) {
  const rows = roots.map(([id, pkg, config]) => ({
    id, name: new URL(`./node_modules/@deepseek-ai/${pkg}/lib/index.js`, import.meta.url).href,
    ...(config ? { config } : {}),
  }));
  rows.push({ id: 'session-persistence', name: new URL('./sqlite-session-persistence.mjs', import.meta.url).href,
    config: { directory } });
  return rows;
}

export async function createChatEngine({ directory, apiKey, adapterFactory } = {}) {
  if (typeof apiKey !== 'string' || apiKey.length > 1024 || !/^[!-~]+$/.test(apiKey)) {
    throw chatError('IOS_CHAT_KEY_INVALID');
  }
  let key = apiKey;
  apiKey = undefined;
  let work;
  let ctx;
  let handle;
  let failure = 'IOS_CHAT_STORAGE_FAILED';
  const history = [];
  let draftParts = new Map();
  let draftLength = 0;
  let attempt;
  let errorCode = null;
  let storageFault = false;
  let active;
  let cancellation;
  let stopping;
  let observeTurnErrors = false;

  const redact = text => key ? text.replaceAll(key, '[redacted]') : text;
  const clearDraft = () => { attempt = undefined; draftParts.clear(); draftLength = 0; };
  function remember(role, message) {
    const text = textOf(message);
    if (!text) return;
    history.push({ role, text: clip(redact(text), MAX_TEXT_BYTES) });
    if (history.length > MAX_MESSAGES) history.shift();
  }
  function project(event) {
    // Inbox insertion is the durable admission record, even when cancellation
    // occurs before the same message is admitted into model-visible history.
    if (event.type === 'agent/inbox/spliced') {
      for (const message of event.data.inserted) {
        if (message.source.kind === 'user') remember('user', message);
      }
    } else if (event.type === 'assistant/message') {
      clearDraft();
      remember('assistant', event.data.message);
    } else if (observeTurnErrors && event.type === 'turn/end' && event.data.reason.kind === 'error') {
      errorCode = chatFailureCode(event.data.reason.error.code);
    }
  }
  function view(override) {
    const draft = clip(redact([...draftParts.entries()].sort(([a], [b]) => a - b)
      .map(([, part]) => part).join('')), MAX_TEXT_BYTES);
    const result = { state: active || cancellation ? 'running' : 'ready', messages: [], draft,
      errorCode: storageFault ? 'IOS_CHAT_STORAGE_FAILED' : override ?? errorCode };
    let remaining = SNAPSHOT_BYTES - jsonBytes(result) - 1;
    for (let i = history.length - 1; i >= 0; i--) {
      const message = history[i];
      const cost = jsonBytes(message) + 1; // Reserve the array separator too.
      if (cost > remaining) break;
      remaining -= cost;
      result.messages.push({ ...message });
    }
    result.messages.reverse();
    return result;
  }
  async function checkpoint() {
    if (await ctx.sessions.flush(handle.agent.session) !== true) throw chatError('IOS_CHAT_STORAGE_FAILED');
  }
  async function cleanup() {
    let failed = false;
    key = undefined;
    try { await handle?.dispose(); } catch { failed = true; }
    try { await ctx?.fiber.dispose(); } catch { failed = true; }
    try { if (work) await rm(work, { recursive: true, force: true }); } catch { failed = true; }
    handle = ctx = work = undefined;
    history.length = 0;
    clearDraft();
    if (failed) throw chatError('IOS_CHAT_STOP_FAILED');
  }

  try {
    if (typeof directory !== 'string' || !isAbsolute(directory)) throw chatError(failure);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    if (!(await lstat(directory)).isDirectory()) throw chatError(failure);
    directory = await realpath(directory);
    await chmod(directory, 0o700);
    work = await mkdtemp(join(directory, '.chat-boot-'));
    await chmod(work, 0o700);
    const rows = buildRows(directory);
    const config = join(work, 'cordis.json');
    await writeFile(config, JSON.stringify(rows), { flag: 'wx', mode: 0o600 });
    failure = 'IOS_CHAT_BOOT_FAILED';
    ctx = await boot('dsh-ios-chat', config, []);
    const tree = ctx.get('loader')?.resolve('include')?.subtree;
    const store = ctx.get('sessionPersistence');
    if (!(store instanceof SessionPersistence)) { failure = 'IOS_CHAT_STORAGE_FAILED'; throw chatError(failure); }
    if (ctx.fiber.state !== 2 || rows.some(({ id }) => tree?.resolve(id)?.fiber?.state !== 2)) throw chatError(failure);

    // This optional function is a Node-only fixture seam, never a field in
    // mailbox messages or a choice controlled by launch environment/config.
    const adapter = adapterFactory === undefined ? createDeepSeekAdapter(directory, () => key)
      : await adapterFactory({ apiKey: key, endpoint: CHAT_ENDPOINT });
    ctx.llm.registerAdapter([CHAT_PROVIDER], adapter);
    ctx.on('llm/stream', (options, next) => {
      if (options.sessionId !== SESSION || options.provider !== CHAT_PROVIDER || options.model !== CHAT_MODEL || !key) {
        throw chatError('IOS_CHAT_MODEL_FAILED');
      }
      return chatStream(next, key, options.signal);
    }, { prepend: true });
    ctx.on('session/event', (session, event) => { if (session.id === SESSION) project(event); });
    ctx.on('agent/error', ({ agent, error }) => {
      if (agent.id === SESSION) errorCode = chatFailureCode(error?.code);
    });
    ctx.on('agent/assistant-stream', ({ agent, frame }) => {
      if (agent.id !== SESSION) return;
      if (frame.type === 'start') { clearDraft(); attempt = frame.attemptId; }
      else if (frame.attemptId === attempt) {
        if (frame.type === 'end') clearDraft();
        else if (frame.type === 'chunk' && frame.chunk.type === 'text-delta') {
          const { index, text } = frame.chunk;
          const part = text.slice(0, MAX_TEXT_BYTES - draftLength);
          if (part) { draftParts.set(index, (draftParts.get(index) ?? '') + part); draftLength += part.length; }
        }
      }
    });

    failure = 'IOS_CHAT_STORAGE_FAILED';
    const agentOptions = { provider: CHAT_PROVIDER, model: CHAT_MODEL, maxTokens: CHAT_MAX_TOKENS };
    handle = await store.stat(SESSION) === undefined
      ? await ctx.agents.create({ sessionId: SESSION, meta: { cwd: directory }, agentOptions })
      : await ctx.agents.resume({ resumeSessionId: SESSION, agentOptions });
    await checkpoint();
    const reader = await store.open(SESSION, 'read');
    try {
      history.length = 0;
      for (const event of (await reader.read()).events) project(event);
    } finally { await reader.close(); }
    // Crash recovery repairs the committed stream but does not reissue any
    // undelivered queue entry automatically or on the next fresh user prompt.
    handle.agent.cancel({ kind: 'disposed' });
    await checkpoint();
    observeTurnErrors = true;
  } catch {
    try { await cleanup(); } catch { throw chatError('IOS_CHAT_STOP_FAILED'); }
    throw chatError(failure);
  }

  function assertOpen() { if (stopping) throw chatError('IOS_CHAT_STOPPED'); }
  async function settle() {
    await handle.agent.whenIdle();
    await checkpoint();
  }
  return Object.freeze({
    async snapshot() { assertOpen(); return view(); },
    async send({ text } = {}) {
      assertOpen();
      if (storageFault) return view();
      if (active || cancellation) return view('IOS_CHAT_BUSY');
      if (typeof text !== 'string' || text.length > MAX_PROMPT_BYTES || !text.isWellFormed()
          || byteLength(text) > MAX_PROMPT_BYTES || !text.trim() || text.includes(key)) {
        return view('IOS_CHAT_INPUT_INVALID');
      }
      errorCode = null;
      clearDraft();
      try {
        handle.agent.followup(createUserMessage({ content: [{ type: 'text', text }], source: { kind: 'user' } }));
      } catch {
        storageFault = true;
        return view();
      }
      active = settle().catch(() => { storageFault = true; }).finally(() => { clearDraft(); active = undefined; });
      try { await checkpoint(); } catch {
        storageFault = true;
        try { handle.agent.cancel({ kind: 'disposed' }); } catch { /* stop still owns cleanup */ }
      }
      return view();
    },
    async cancel() {
      assertOpen();
      cancellation ??= (async () => {
        try { handle.agent.cancel({ kind: 'user' }); } catch { storageFault = true; }
        try { await active; await settle(); } catch { storageFault = true; }
        finally { clearDraft(); cancellation = undefined; }
      })();
      await cancellation;
      return view();
    },
    async stop() {
      stopping ??= (async () => {
        let failed = false;
        try { handle.agent.cancel({ kind: 'disposed' }); } catch { failed = true; }
        try { await cancellation; await active; await settle(); } catch { failed = true; }
        await cleanup();
        if (failed) throw chatError('IOS_CHAT_STOP_FAILED');
      })();
      await stopping;
    },
  });
}
