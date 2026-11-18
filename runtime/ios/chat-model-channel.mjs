import { Buffer } from 'node:buffer';
import { createHash, randomUUID } from 'node:crypto';
import {
  attributionHeaders, LLM_FAILURE_CODES, LlmAdapter, LlmError, resolveRetryPolicy, ToolCallId,
} from '@deepseek-ai/dsh-llm';
import { DeepSeekAdapter, resolveAdapterOptions } from '@deepseek-ai/dsh-llm-deepseek';
import { idleWatchdog, timeoutOf } from '@deepseek-ai/dsh-timeout';
import { createParser } from 'eventsource-parser';
import { CHAT_MAX_TOKENS, chatFailureCode } from './chat-deepseek-provider.mjs';

export const CHAT_CHANNEL_PROVIDER = 'ios-custom';
const RETRY_CONFIG = Object.freeze({ mode: 'normal', maxRetries: 0 });
const RETRY = resolveRetryPolicy(RETRY_CONFIG, 'iOS chat channel');
const IDLE_MS = 60_000;
const IDLE_CODE = 'IOS_CHAT_COMPLETIONS_IDLE';
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const MAX_RESPONSE_CHUNKS = 8192;
const MAX_FRAME_BYTES = 128 * 1024;
const MAX_TOOL_ARGUMENT_BYTES = 64 * 1024;
const MAX_TOOLS = 32;
const TOOL_NAME = /^[A-Za-z0-9_-]{1,64}$/u;
const TOOL_ID = /^[!-~]{1,256}$/u;

function routeError() {
  return Object.assign(new Error('IOS_CHAT_CHANNEL_INVALID'), { code: 'IOS_CHAT_CHANNEL_INVALID' });
}

// The caller owns apiKey separately. Nothing in this result contains credentials
// or a mutable URL object; request construction needs only this start snapshot.
export function normalizeChatChannel(value) {
  const { protocol, baseUrl, modelId } = value ?? {};
  if ((protocol !== 'deepseek' && protocol !== 'openai-chat')
      || typeof modelId !== 'string' || !modelId.length || modelId.length > 256
      || /[\s\p{C}]/u.test(modelId)
      || typeof baseUrl !== 'string' || baseUrl.length > 2048 || !/^https:\/\/[^/]/iu.test(baseUrl)
      || /[\s\p{C}?#\\]/u.test(baseUrl) || /^https:\/\/[^/]*@/iu.test(baseUrl)) throw routeError();
  let url;
  try { url = new URL(baseUrl); } catch { throw routeError(); }
  const host = url.hostname.replace(/\.$/u, '');
  if (url.protocol !== 'https:' || !host || url.username || url.password || url.search || url.hash
      || host === 'localhost' || host.endsWith('.localhost') || host === '0.0.0.0'
      || /^127\.(?:\d{1,3}\.){2}\d{1,3}$/u.test(host)
      || /^\[::(?:\]|1\]|(?:ffff:)?(?:7f[\da-f]{2}|0):)/u.test(host)) throw routeError();
  return Object.freeze({ protocol, baseUrl: url.href.replace(/\/+$/u, ''), modelId });
}

function llmError(code) { return new LlmError(code, code); }
function malformed() { throw llmError('MALFORMED_RESPONSE'); }
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function byteLength(value) { return Buffer.byteLength(value, 'utf8'); }
function readKey(channel, getKey) {
  const key = getKey();
  if (!key) throw llmError('MISSING_CREDENTIAL');
  if (typeof key !== 'string' || key.length > 1024 || /[^!-~]/u.test(key)) throw llmError('INVALID_CREDENTIAL');
  if (channel.modelId.includes(key) || channel.baseUrl.includes(key)) throw llmError('INVALID_REQUEST');
  return key;
}

// Scope official native replay to this protocol/address/model without retaining
// the address in the replay envelope or including credentials in its identity.
function deepSeekReplayScope(channel) {
  return createHash('sha256').update(JSON.stringify([channel.protocol, channel.baseUrl, channel.modelId])).digest('hex');
}

function withoutForeignDeepSeekReplay(options, scope) {
  let changed = false;
  const messages = options.messages.map((message) => {
    if (message.role !== 'assistant' || message.source.replayState?.response?.iosChatScope === scope) return message;
    const { replayState: _replay, ...source } = message.source;
    const content = message.content.filter((block) => block.type !== 'reasoning');
    if (_replay === undefined && content.length === message.content.length) return message;
    changed = true;
    return { ...message, source, content };
  });
  return changed ? { ...options, messages } : options;
}

function deepSeekAdapter(channel, getKey) {
  const options = resolveAdapterOptions({
    baseURL: channel.baseUrl,
    models: [{ id: channel.modelId, inputModalities: ['text'] }],
    maxTokens: CHAT_MAX_TOKENS,
    // Unknown custom capacity: use a conservative compaction threshold, not discovery.
    defaultContextWindow: 32_768,
    thinking: 'disabled', reasoningEffort: 'off',
    retryPolicy: RETRY_CONFIG, streamIdleTimeoutMs: IDLE_MS,
  });
  for (const model of options.models) {
    Object.freeze(model.inputModalities);
    Object.freeze(model);
  }
  Object.freeze(options.models);
  Object.freeze(options.defaults);
  Object.freeze(options.filePolicy);
  Object.freeze(options);
  const userId = randomUUID();
  const disabled = async () => { throw llmError('UNSUPPORTED_CONTENT'); };
  const noFiles = Object.freeze({ ensureUploaded: disabled, invalidate: disabled });
  return new DeepSeekAdapter({
    options: () => options,
    resolveAuth: async () => ({ headers: { 'x-api-key': readKey(channel, getKey) } }),
    resolveUserId: () => userId,
    resolveFiles: () => noFiles,
    prepareExtensions: async () => ({ fields: {}, accept() {} }),
  });
}

function openAiBody(options, officialHost) {
  const messages = [];
  const pending = new Set();
  const system = (content) => { if (content) messages.push({ role: 'system', content }); };
  system(options.system);
  for (const { role, content, toolCallId } of options.messages) {
    const text = content.filter((block) => block.type === 'text').map((block) => block.text).join('');
    if (role === 'tool') {
      if (!pending.delete(toolCallId)) throw llmError('INVALID_REQUEST');
      messages.push({ role, tool_call_id: toolCallId, content: text });
      continue;
    }
    if (pending.size) throw llmError('INVALID_REQUEST');
    if (role === 'system' || role === 'developer') system(text);
    else if (role === 'user' && text) messages.push({ role, content: text });
    else if (role === 'assistant') {
      const calls = content.filter((block) => block.type === 'tool-call').map(({ id, name, arguments: args }) => {
        if (pending.has(id) || !TOOL_ID.test(id) || !TOOL_NAME.test(name)) throw llmError('INVALID_REQUEST');
        pending.add(id);
        return { id, type: 'function', function: { name, arguments: args } };
      });
      if (text || calls.length) messages.push({ role, content: text || null, ...(calls.length ? { tool_calls: calls } : {}) });
    }
  }
  if (pending.size) throw llmError('INVALID_REQUEST');
  const tools = options.tools?.map(({ name, description, parameters }) => {
    if (!TOOL_NAME.test(name)) throw llmError('INVALID_REQUEST');
    return { type: 'function', function: { name, description, parameters } };
  });
  const maxTokens = options.maxTokens ?? CHAT_MAX_TOKENS;
  return {
    model: options.model, stream: true, messages,
    [officialHost ? 'max_completion_tokens' : 'max_tokens']: maxTokens,
    ...(officialHost ? { stream_options: { include_usage: true } } : {}),
    ...(options.temperature === undefined ? {} : { temperature: options.temperature }),
    ...(options.stop === undefined ? {} : { stop: options.stop }),
    ...(tools?.length ? { tools } : {}),
  };
}

async function* sseFrames(body, activity) {
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let bytes = 0;
  let reads = 0;
  let count = 0;
  const frames = [];
  const parser = createParser({
    maxBufferSize: MAX_FRAME_BYTES,
    onError(error) { if (error.type === 'max-buffer-size-exceeded') malformed(); },
    onEvent({ data }) {
      if (++count > MAX_RESPONSE_CHUNKS || byteLength(data) > MAX_FRAME_BYTES) malformed();
      frames.push(data);
    },
  });
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) { decoder.decode(); return; }
      bytes += value.byteLength;
      if (++reads > MAX_RESPONSE_CHUNKS * 2 || bytes > MAX_RESPONSE_BYTES) malformed();
      if (value.byteLength > 0) activity();
      // Bound both the parser's pending frame and the queue before yielding.
      for (let offset = 0; offset < value.byteLength; offset += 16 * 1024) {
        const text = decoder.decode(value.subarray(offset, offset + 16 * 1024), { stream: true });
        if (text) parser.feed(text);
        yield* frames;
        frames.length = 0;
      }
    }
  } finally {
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

function tokenUsage(value) {
  if (!object(value)) malformed();
  const natural = (n) => Number.isSafeInteger(n) && n >= 0;
  const { prompt_tokens: input, completion_tokens: output } = value;
  const cached = value.prompt_tokens_details?.cached_tokens;
  const reasoning = value.completion_tokens_details?.reasoning_tokens;
  if (!natural(input) || !natural(output)) malformed();
  const cacheRead = natural(cached) && cached <= input ? cached : undefined;
  const total = input + output;
  return {
    inputTokens: input - (cacheRead ?? 0), outputTokens: output,
    ...(cacheRead === undefined ? {} : { cacheReadTokens: cacheRead }),
    ...(natural(reasoning) && reasoning <= output ? { reasoningTokens: reasoning } : {}),
    ...(natural(total) ? { totalTokens: total } : {}),
  };
}

function statusCode(status) {
  if (status === 401 || status === 403) return 'AUTH';
  if (status === 402) return 'QUOTA';
  if (status === 429) return 'RATE_LIMIT';
  if (status >= 500) return 'SERVER';
  return 'INVALID_RESPONSE';
}

async function* openAiRequest(channel, getKey, options, signal, activity) {
  const key = readKey(channel, getKey);
  const officialHost = new URL(channel.baseUrl).hostname === 'api.openai.com';
  const body = JSON.stringify(openAiBody(options, officialHost));
  signal.throwIfAborted();
  const response = await fetch(`${channel.baseUrl}/chat/completions`, {
    method: 'POST', redirect: 'error', signal, body,
    headers: { ...attributionHeaders(), 'content-type': 'application/json', accept: 'text/event-stream', authorization: `Bearer ${key}` },
  });
  if (!response.ok || !/^text\/event-stream(?:\s*;|$)/iu.test(response.headers.get('content-type') ?? '') || !response.body) {
    void response.body?.cancel().catch(() => {});
    throw llmError(statusCode(response.status));
  }
  let index = 0;
  let text;
  let finish;
  let usage;
  const calls = new Map();
  for await (const data of sseFrames(response.body, activity)) {
    if (data === '[DONE]') {
      if (!finish) malformed();
      if ((finish === 'tool-calls' && !calls.size) || (finish === 'stop' && calls.size)) malformed();
      if (finish === 'stop' && !text) throw llmError('EMPTY_RESPONSE');
      if (text) yield { type: 'block-end', index: text.index, block: { type: 'text', text: text.value } };
      for (const { index, id, name, args } of calls.values()) {
        yield { type: 'block-end', index, block: { type: 'tool-call', id, name, arguments: args } };
      }
      if (usage) yield { type: 'usage', usage };
      yield { type: 'finish', reason: { kind: finish } };
      return;
    }
    let frame;
    try { frame = JSON.parse(data); } catch { malformed(); }
    if (!object(frame) || frame.error || !Array.isArray(frame.choices) || frame.choices.length > 1) malformed();
    if (frame.usage != null) usage = tokenUsage(frame.usage);
    if (!frame.choices.length) continue;
    if (!object(frame.choices[0])) malformed();
    const { index: choiceIndex, delta, finish_reason: reason } = frame.choices[0];
    if (finish || (choiceIndex !== undefined && choiceIndex !== 0) || !object(delta)) malformed();
    if (delta.role !== undefined && delta.role !== 'assistant') malformed();
    if (delta.function_call != null) malformed();
    if ((delta.content != null && typeof delta.content !== 'string')
        || (delta.refusal != null && typeof delta.refusal !== 'string')) malformed();
    const piece = (delta.content ?? '') + (delta.refusal ?? '');
    if (piece) {
      if (!text) {
        text = { index: index++, value: '' };
        yield { type: 'block-start', index: text.index, blockType: 'text' };
      }
      text.value += piece;
      yield { type: 'text-delta', index: text.index, text: piece };
    }
    if (delta.tool_calls != null) {
      if (!Array.isArray(delta.tool_calls) || delta.tool_calls.length > MAX_TOOLS) malformed();
      for (const tool of delta.tool_calls) {
        if (!object(tool) || !Number.isSafeInteger(tool.index) || tool.index < 0 || tool.index >= MAX_TOOLS
            || (tool.type !== undefined && tool.type !== 'function') || !object(tool.function)) malformed();
        const { name, arguments: args } = tool.function;
        let call = calls.get(tool.index);
        if (!call) {
          if (typeof tool.id !== 'string' || !TOOL_ID.test(tool.id) || typeof name !== 'string' || !TOOL_NAME.test(name)) malformed();
          call = { index: index++, id: ToolCallId(tool.id), name, args: '', bytes: 0 };
          calls.set(tool.index, call);
          yield { type: 'block-start', index: call.index, blockType: 'tool-call' };
        }
        if ((tool.id != null && tool.id !== call.id) || (name != null && name !== call.name)
            || (args != null && typeof args !== 'string')) malformed();
        const argumentsDelta = args ?? '';
        call.bytes += byteLength(argumentsDelta);
        if (call.bytes > MAX_TOOL_ARGUMENT_BYTES) malformed();
        call.args += argumentsDelta;
        yield { type: 'tool-call-delta', index: call.index, id: call.id, name: call.name, argumentsDelta };
      }
    }
    if (reason != null) {
      finish = reason === 'stop' ? 'stop' : reason === 'tool_calls' ? 'tool-calls' : reason === 'length' ? 'max-tokens' : undefined;
      if (!finish) malformed();
    }
  }
  throw llmError('STREAM_CLOSED');
}

async function* openAiStream(channel, getKey, options) {
  const consumer = new AbortController();
  const signal = options.signal ? AbortSignal.any([options.signal, consumer.signal]) : consumer.signal;
  const watchdog = idleWatchdog(signal, IDLE_MS, IDLE_CODE);
  const iterator = openAiRequest(channel, getKey, options, watchdog.signal, () => watchdog.pulse());
  try {
    while (true) {
      const item = await watchdog.next(iterator);
      if (item.done) return;
      yield item.value;
    }
  } catch (error) {
    if (timeoutOf(watchdog.signal, IDLE_CODE)) throw llmError('TIMEOUT');
    if (options.signal?.aborted) throw llmError('ABORTED');
    throw error instanceof LlmError ? error : llmError('TRANSPORT');
  } finally {
    consumer.abort();
    watchdog[Symbol.dispose]();
    void iterator.return().catch(() => {});
  }
}

class ChatChannelAdapter extends LlmAdapter {
  #channel;
  #getKey;
  #deepSeek;
  #replayScope;
  constructor(channel, getKey) {
    super();
    this.#channel = channel;
    this.#getKey = getKey;
    if (channel.protocol === 'deepseek') {
      this.#deepSeek = deepSeekAdapter(channel, getKey);
      this.#replayScope = deepSeekReplayScope(channel);
    }
  }
  providerInfo(provider) {
    return { id: provider, name: this.#deepSeek ? 'DeepSeek' : 'OpenAI-compatible' };
  }
  providerRetryPolicy() { return RETRY; }
  async listModels(provider) {
    if (provider !== CHAT_CHANNEL_PROVIDER) return [];
    const id = this.#channel.modelId;
    return [{ provider, id, name: id, inputModalities: ['text'] }];
  }
  #admit(provider, model) {
    if (provider !== CHAT_CHANNEL_PROVIDER || model !== this.#channel.modelId) throw llmError('UNKNOWN_MODEL');
  }
  async resolveModel(provider, model) {
    this.#admit(provider, model);
    if (this.#deepSeek) return this.#deepSeek.resolveModel(provider, model);
    return { provider, id: model, name: model, inputModalities: ['text'], context: { contextWindow: 32_768 }, defaultMaxTokens: CHAT_MAX_TOKENS };
  }
  async *stream(options) {
    this.#admit(options.provider, options.model);
    try {
      options.signal?.throwIfAborted();
      if (this.#deepSeek) {
        const request = withoutForeignDeepSeekReplay(options, this.#replayScope);
        for await (const chunk of this.#deepSeek.stream(request)) {
          if (chunk.type === 'finish' && chunk.replayState) {
            yield { ...chunk, replayState: {
              ...chunk.replayState, response: { ...chunk.replayState.response, iosChatScope: this.#replayScope },
            } };
          } else yield chunk;
        }
      } else yield* openAiStream(this.#channel, this.#getKey, options);
    } catch (error) {
      // The official transport may carry server messages, headers and causes.
      if (options.signal?.aborted) throw llmError('ABORTED');
      if (!(error instanceof LlmError)) throw llmError('TRANSPORT');
      throw llmError(Object.hasOwn(LLM_FAILURE_CODES, error.code) ? error.code : 'INVALID_RESPONSE');
    }
  }
}

export function createChatChannelAdapter(_directory, channel, getKey) {
  if (typeof getKey !== 'function') throw routeError();
  return new ChatChannelAdapter(normalizeChatChannel(channel), getKey);
}

function failureChunk(code, kind = 'error') {
  return { type: 'finish', reason: { kind, failure: { code, message: code } } };
}

function containsKey(value, key) {
  const pending = [value];
  while (pending.length) {
    const entry = pending.pop();
    if (typeof entry === 'string' && entry.includes(key)) return true;
    if (entry && typeof entry === 'object') {
      for (const [name, child] of Object.entries(entry)) {
        if (name.includes(key)) return true;
        pending.push(child);
      }
    }
  }
  return false;
}

// Used before AgentLoop sees provider output. Retain normal text streaming,
// but expose executable call data only after full JSON and terminal validation.
export async function* guardChatChannelStream(next, key, signal, tools = []) {
  if (typeof key !== 'string' || !key) { yield failureChunk('IOS_CHAT_AUTH_FAILED'); return; }
  const names = new Set(tools.map((tool) => tool.name));
  const tails = new Map();
  const calls = new Map();
  const ids = new Set();
  const started = new Map();
  const closed = new Set();
  const failed = () => failureChunk('IOS_CHAT_MODEL_FAILED');
  let count = 0;
  let bytes = 0;
  try {
    for await (const chunk of next()) {
      if (++count > MAX_RESPONSE_CHUNKS || !object(chunk)
          || (chunk.type !== 'finish' && chunk.type !== 'usage'
            && (!Number.isSafeInteger(chunk.index) || chunk.index < 0))) { yield failed(); return; }
      if (chunk.type === 'finish' && ['error', 'aborted'].includes(chunk.reason.kind)) {
        yield failureChunk(chatFailureCode(chunk.reason.failure.code), chunk.reason.kind);
        return;
      }
      if (chunk.type === 'block-start') {
        if (started.has(chunk.index) || !['text', 'reasoning', 'tool-call'].includes(chunk.blockType)) { yield failed(); return; }
        started.set(chunk.index, chunk.blockType);
        if (chunk.blockType === 'tool-call') {
          if (!names.size || calls.size >= MAX_TOOLS) { yield failed(); return; }
          calls.set(chunk.index, { args: '', bytes: 0 });
        }
      }
      if (chunk.type === 'block-end') {
        if (closed.has(chunk.index) || started.get(chunk.index) !== chunk.block.type) { yield failed(); return; }
        closed.add(chunk.index);
      }
      if (chunk.type === 'tool-call-delta') {
        const call = calls.get(chunk.index);
        if (!call || call.block || typeof chunk.argumentsDelta !== 'string'
            || typeof chunk.id !== 'string' || !TOOL_ID.test(chunk.id) || chunk.id.includes(key)
            || (call.id !== undefined && call.id !== chunk.id)
            || (chunk.name !== undefined && (typeof chunk.name !== 'string' || !TOOL_NAME.test(chunk.name)
              || !names.has(chunk.name) || chunk.name.includes(key)
              || (call.name !== undefined && call.name !== chunk.name)))) { yield failed(); return; }
        call.id = chunk.id;
        call.name ??= chunk.name;
        const size = byteLength(chunk.argumentsDelta);
        call.bytes += size;
        bytes += size;
        if (call.bytes > MAX_TOOL_ARGUMENT_BYTES || bytes > MAX_RESPONSE_BYTES) { yield failed(); return; }
        call.args += chunk.argumentsDelta;
        continue;
      }
      if (chunk.type === 'block-end' && chunk.block.type === 'tool-call') {
        const call = calls.get(chunk.index);
        const { id, name, arguments: args } = chunk.block;
        if (!call || call.block || call.id !== id || call.name !== name || ids.has(id)
            || !names.has(name) || typeof args !== 'string' || byteLength(args) > MAX_TOOL_ARGUMENT_BYTES
            || (call.args && call.args !== args) || args.includes(key)) { yield failed(); return; }
        bytes += Math.max(0, byteLength(args) - call.bytes);
        if (bytes > MAX_RESPONSE_BYTES) { yield failed(); return; }
        ids.add(id);
        call.block = { type: 'tool-call', id, name, arguments: args };
        continue;
      }
      if (chunk.type === 'text-delta' || chunk.type === 'reasoning-delta') {
        const blockType = chunk.type === 'text-delta' ? 'text' : 'reasoning';
        if (closed.has(chunk.index) || started.get(chunk.index) !== blockType || typeof chunk.text !== 'string') { yield failed(); return; }
        bytes += byteLength(chunk.text);
        const combined = (tails.get(chunk.index)?.text ?? '') + chunk.text;
        if (bytes > MAX_RESPONSE_BYTES || combined.includes(key)) { yield failed(); return; }
        let tail = Math.min(key.length - 1, combined.length);
        while (tail > 0 && !key.startsWith(combined.slice(-tail))) tail--;
        if (tail > 0) tails.set(chunk.index, { type: chunk.type, index: chunk.index, text: combined.slice(-tail) });
        else tails.delete(chunk.index);
        const text = combined.slice(0, combined.length - tail);
        if (text) yield { type: chunk.type, index: chunk.index, text };
        continue;
      }
      if (chunk.type === 'block-end') {
        const { type, text } = chunk.block;
        if (typeof text !== 'string' || text.includes(key)) { yield failed(); return; }
        bytes += byteLength(text);
        if (bytes > MAX_RESPONSE_BYTES) { yield failed(); return; }
        const tail = tails.get(chunk.index);
        tails.delete(chunk.index);
        if (tail) yield tail;
        yield { type: 'block-end', index: chunk.index, block: { type, text } };
        continue;
      }
      if (chunk.type === 'finish') {
        if (started.size !== closed.size) { yield failed(); return; }
        const replay = chunk.replayState;
        if (replay !== undefined) {
          const serialized = JSON.stringify(replay);
          if (!object(replay) || !Object.hasOwn(replay, 'response') || typeof serialized !== 'string'
              || byteLength(serialized) > MAX_FRAME_BYTES || serialized.includes(key) || containsKey(replay, key)) {
            yield failed(); return;
          }
          if (replay.blocks !== undefined && (!Array.isArray(replay.blocks) || replay.blocks.length !== started.size)) {
            yield failed(); return;
          }
        }
        if (chunk.reason.kind === 'tool-calls') {
          if (!calls.size || [...calls.values()].some(({ block }) => !block)) { yield failed(); return; }
          for (const { block } of calls.values()) {
            let args;
            try { args = JSON.parse(block.arguments); } catch { yield failed(); return; }
            if (!object(args) || containsKey(args, key)) { yield failed(); return; }
          }
          for (const [index, { block }] of calls) {
            yield { type: 'tool-call-delta', index, id: block.id, name: block.name, argumentsDelta: block.arguments };
            yield { type: 'block-end', index, block };
          }
        } else if (chunk.reason.kind !== 'max-tokens' && (chunk.reason.kind !== 'stop' || calls.size)) {
          yield failed(); return;
        }
        // For max-tokens the official assembler drops the empty physical tool
        // block and its aligned replay entry together.
        yield { type: 'finish', reason: { kind: chunk.reason.kind }, ...(replay === undefined ? {} : { replayState: replay }) };
        return;
      }
      if (chunk.type === 'block-start') {
        yield { type: 'block-start', index: chunk.index, blockType: chunk.blockType };
      } else if (chunk.type === 'usage') {
        const usage = {};
        for (const field of ['inputTokens', 'outputTokens', 'totalTokens', 'cacheReadTokens', 'cacheWriteTokens', 'reasoningTokens']) {
          const value = chunk.usage[field];
          if (Number.isSafeInteger(value) && value >= 0) usage[field] = value;
        }
        if (usage.inputTokens === undefined || usage.outputTokens === undefined) { yield failed(); return; }
        yield { type: 'usage', usage };
      } else { yield failed(); return; }
    }
    yield failed();
  } catch {
    yield failureChunk(signal?.aborted ? 'IOS_CHAT_MODEL_FAILED' : 'IOS_CHAT_STORAGE_FAILED', signal?.aborted ? 'aborted' : 'error');
  }
}
