import { Buffer } from 'node:buffer';
import { randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { chmod, link, lstat, mkdir, mkdtemp, open, realpath, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { boot } from '@deepseek-ai/dsh-app-boot';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';
import { SessionPersistence } from '@deepseek-ai/dsh-session-persistence';
import { createChatApproval } from './chat-approval.mjs';
import { CHAT_CHANNEL_PROVIDER, createChatChannelAdapter, guardChatChannelStream, normalizeChatChannel } from './chat-model-channel.mjs';
import { registerChatWorkspaceTools } from './chat-workspace-tools.mjs';
import {
  CHAT_MAX_TOKENS, CHAT_MODEL, CHAT_PROVIDER,
  chatFailureCode, createDeepSeekAdapter,
} from './chat-deepseek-provider.mjs';

const UUID_V4 = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const roots = [
  ['session-projection', 'dsh-session-projection'], ['session', 'dsh-session'],
  ['system-prompt', 'dsh-system-prompt', { includeHarnessIdentity: false, includeRuntimeContext: false,
    personaPrefix: 'You are a helpful assistant in the DeepSeek iOS chat app. Reply in text.' }],
  ['tools', 'dsh-tools'], ['tool-executor-native', 'dsh-tool-executor-native'], ['llm', 'dsh-llm'],
  ['agent', 'dsh-agent'], ['agent-loop', 'dsh-agent-loop', { agents: [] }],
  ['session-checkpoint-policy', 'dsh-session-checkpoint-policy'],
  ['user-approval', 'dsh-user-approval', { policy: 'ask' }],
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

// Publish exactly one complete UUID before the SQLite backend can create data.
// A racing starter can only adopt that UUID; a missing/corrupt identity next
// to existing storage never causes a replacement conversation.
async function durableSessionId(directory, work) {
  const path = join(directory, 'session-id');
  const inspect = async () => {
    let file;
    try { file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK); }
    catch (error) { if (error?.code === 'ENOENT') return undefined; throw error; }
    try {
      const info = await file.stat();
      if (!info.isFile() || (info.mode & 0o077) !== 0 || info.size !== 36) throw chatError('IOS_CHAT_STORAGE_FAILED');
      const raw = Buffer.alloc(37);
      const { bytesRead } = await file.read(raw, 0, raw.length, 0);
      const id = raw.subarray(0, bytesRead).toString('utf8');
      if (bytesRead !== 36 || !UUID_V4.test(id)) throw chatError('IOS_CHAT_STORAGE_FAILED');
      return SessionId(id);
    } finally { await file.close(); }
  };
  let id = await inspect();
  if (!id) {
    let existing = false;
    try { await lstat(join(directory, 'sessions.sqlite')); existing = true; }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    if (!existing) {
      const staged = join(work, 'new-session-id');
      await writeFile(staged, randomUUID(), { flag: 'wx', mode: 0o600, flush: true });
      try { await link(staged, path); }
      catch (error) { if (error?.code !== 'EEXIST') throw error; }
      finally { await rm(staged, { force: true }); }
    }
    id = await inspect();
    if (!id) throw chatError('IOS_CHAT_STORAGE_FAILED');
  }
  // Each contender syncs the same parent before allowing database creation;
  // the loser cannot commit a DB before the winning link is durable.
  const parent = await open(directory, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { await parent.sync(); } finally { await parent.close(); }
  return id;
}

export async function createChatEngine({ directory, apiKey, channel } = {}) {
  if (typeof apiKey !== 'string' || !apiKey.length || apiKey.length > 1024 || /[^!-~]/.test(apiKey)) {
    throw chatError('IOS_CHAT_KEY_INVALID');
  }
  const route = channel === undefined ? null : normalizeChatChannel(channel);
  if (route && [route.baseUrl, route.modelId].some(value => value.includes(apiKey))) throw chatError('IOS_CHAT_CHANNEL_INVALID');
  const provider = route ? CHAT_CHANNEL_PROVIDER : CHAT_PROVIDER;
  const model = route?.modelId ?? CHAT_MODEL;
  const approval = createChatApproval();
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
    } else if (event.type === 'tool/result') {
      const content = event.data.message.content.filter(block => block.type === 'text').map(block => block.text).join('');
      if (content) {
        history.push({ role: 'tool', text: clip(redact(content), MAX_TEXT_BYTES) });
        if (history.length > MAX_MESSAGES) history.shift();
      }
    } else if (observeTurnErrors && event.type === 'turn/end' && event.data.reason.kind === 'error') {
      errorCode = chatFailureCode(event.data.reason.error.code);
    }
  }
  function view(override) {
    const draft = clip(redact([...draftParts.entries()].sort(([a], [b]) => a - b)
      .map(([, part]) => part).join('')), MAX_TEXT_BYTES);
    const result = { state: active || cancellation ? 'running' : 'ready', messages: [], draft,
      errorCode: storageFault ? 'IOS_CHAT_STORAGE_FAILED' : override ?? errorCode,
      approval: approval.snapshot() };
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
    approval.close();
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
    const sessionId = await durableSessionId(directory, work);
    const rows = buildRows(directory);
    const config = join(work, 'cordis.json');
    await writeFile(config, JSON.stringify(rows), { flag: 'wx', mode: 0o600 });
    failure = 'IOS_CHAT_BOOT_FAILED';
    ctx = await boot('dsh-ios-chat', config, []);
    const tree = ctx.get('loader')?.resolve('include')?.subtree;
    const store = ctx.get('sessionPersistence');
    if (!(store instanceof SessionPersistence)) { failure = 'IOS_CHAT_STORAGE_FAILED'; throw chatError(failure); }
    if (ctx.fiber.state !== 2 || rows.some(({ id }) => tree?.resolve(id)?.fiber?.state !== 2)) throw chatError(failure);

    const workspace = join(directory, 'Workspace');
    await mkdir(workspace, { mode: 0o700 }).catch((error) => { if (error.code !== 'EEXIST') throw error; });
    const actions = new WeakMap();
    ctx.on('approval/request', (request, next) => {
      const action = actions.get(request.agent);
      if (request.agent.session.id !== sessionId || !action || request.toolName !== action.toolName) return next();
      return approval.ask(action, request.signal);
    });
    await registerChatWorkspaceTools(ctx, {
      directory: workspace,
      containsSecret: text => !!key && typeof text === 'string' && text.includes(key),
      approve: async (action, signal, execution) => {
        const agent = execution?.agent;
        if (!agent || agent.session.id !== sessionId || actions.has(agent)) return false;
        actions.set(agent, action);
        try {
          return await ctx.approval.request({ agent, signal, toolName: action.toolName,
            callId: execution.callId, reason: 'Create a new file in this app’s workspace' }) === 'allowed-once';
        } finally { actions.delete(agent); }
      },
    });
    const adapter = route ? createChatChannelAdapter(directory, route, () => key) : createDeepSeekAdapter(directory, () => key);
    ctx.llm.registerAdapter([provider], adapter);
    ctx.on('llm/stream', (options, next) => {
      if (options.sessionId !== sessionId || options.provider !== provider || options.model !== model || !key) {
        throw chatError('IOS_CHAT_MODEL_FAILED');
      }
      return guardChatChannelStream(next, key, options.signal, options.tools);
    }, { prepend: true });
    ctx.on('session/event', (session, event) => { if (session.id === sessionId) project(event); });
    ctx.on('agent/error', ({ agent, error }) => {
      if (agent.id === sessionId) errorCode = chatFailureCode(error?.code);
    });
    ctx.on('agent/assistant-stream', ({ agent, frame }) => {
      if (agent.id !== sessionId) return;
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
    const agentOptions = { provider, model, maxTokens: CHAT_MAX_TOKENS };
    if (await store.stat(sessionId) === undefined) {
      if ((await store.list()).length !== 0) throw chatError(failure);
      handle = await ctx.agents.create({ sessionId, meta: { cwd: directory }, agentOptions });
    } else {
      handle = await ctx.agents.resume({ resumeSessionId: sessionId, agentOptions });
      // A historical last-used route takes precedence over constructor defaults.
      // The channel explicitly chosen for this run owns subsequent model calls.
      handle.agent.model.select({ provider, model });
    }
    await checkpoint();
    const reader = await store.open(sessionId, 'read');
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
    async answerApproval(params) {
      assertOpen();
      if (!approval.answer(params)) throw chatError('IOS_CHAT_APPROVAL_STALE');
      return view();
    },
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
