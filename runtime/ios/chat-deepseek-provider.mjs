import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import {
  DeepSeekAdapter, DeepSeekFileStore, DeepSeekUploadIndex, PUBLIC_BASE_URL, resolveAdapterOptions,
} from '@deepseek-ai/dsh-llm-deepseek';
import { LlmError } from '@deepseek-ai/dsh-llm';

export const CHAT_PROVIDER = 'ios-deepseek';
export const CHAT_MODEL = 'deepseek-flash';
export const CHAT_ENDPOINT = PUBLIC_BASE_URL;
export const CHAT_MAX_TOKENS = 4096;

export function createDeepSeekAdapter(directory, getKey) {
  const options = resolveAdapterOptions({
    baseURL: CHAT_ENDPOINT,
    models: [{ id: CHAT_MODEL, name: 'DeepSeek V4.1 Flash', inputModalities: ['text'], contextWindow: 1_048_576 }],
    maxTokens: CHAT_MAX_TOKENS,
    thinking: 'disabled',
    reasoningEffort: 'off',
    retryPolicy: { mode: 'normal', maxRetries: 0 },
    streamIdleTimeoutMs: 60_000,
  });
  const userId = randomUUID();
  // Do not resolve Harness home. Files are outside this text-only surface;
  // even an accidental future Files call must never perform egress.
  const files = new DeepSeekFileStore({
    index: new DeepSeekUploadIndex(join(directory, 'unused-deepseek-files.json')),
    fetch: async () => { throw new Error('IOS_CHAT_FILES_DISABLED'); },
  });
  return new DeepSeekAdapter({
    options: () => options,
    admit: (_connection, model) => {
      if (model !== CHAT_MODEL) throw new LlmError('IOS_CHAT_MODEL_FAILED', 'UNKNOWN_MODEL');
    },
    resolveAuth: async () => {
      const key = getKey();
      if (!key) throw new LlmError('IOS_CHAT_AUTH_FAILED', 'MISSING_CREDENTIAL');
      return { headers: { 'x-api-key': key } };
    },
    resolveUserId: () => userId,
    resolveFiles: () => files,
    prepareExtensions: async () => ({ fields: {}, accept() {} }),
  });
}

export function chatFailureCode(code) {
  switch (code) {
    case 'AUTH': case 'MISSING_CREDENTIAL': case 'INVALID_CREDENTIAL': case 'IOS_CHAT_AUTH_FAILED':
      return 'IOS_CHAT_AUTH_FAILED';
    case 'QUOTA': case 'RATE_LIMIT': case 'IOS_CHAT_RATE_LIMITED':
      return 'IOS_CHAT_RATE_LIMITED';
    case 'TIMEOUT': case 'IOS_CHAT_TIMEOUT':
      return 'IOS_CHAT_TIMEOUT';
    case 'TRANSPORT': case 'STREAM_CLOSED': case 'IOS_CHAT_NETWORK_FAILED':
      return 'IOS_CHAT_NETWORK_FAILED';
    case 'IOS_CHAT_STORAGE_FAILED': return 'IOS_CHAT_STORAGE_FAILED';
    default: return 'IOS_CHAT_MODEL_FAILED';
  }
}

function failureChunk(code, kind = 'error') {
  return { type: 'finish', reason: { kind, failure: { code, message: code } } };
}

// Redact provider failure envelopes before AgentLoop logs them. Prevent even
// a credential echoed in pieces within one text block from reaching the log.
// Never pass through tool calls: the iOS chat surface has no executable tools.
export async function* chatStream(next, key, signal) {
  const tails = new Map();
  try {
    for await (const chunk of next()) {
      if (chunk.type === 'finish' && ['error', 'aborted'].includes(chunk.reason.kind)) {
        yield failureChunk(chatFailureCode(chunk.reason.failure.code), chunk.reason.kind);
        return;
      }
      if (chunk.type === 'tool-call-delta' || (chunk.type === 'block-start' && chunk.blockType === 'tool-call')
          || (chunk.type === 'block-end' && chunk.block.type === 'tool-call')
          || (chunk.type === 'finish' && chunk.reason.kind === 'tool-calls')) {
        yield failureChunk('IOS_CHAT_MODEL_FAILED');
        return;
      }
      if (chunk.type === 'text-delta' || chunk.type === 'reasoning-delta') {
        const combined = (tails.get(chunk.index)?.text ?? '') + chunk.text;
        if (combined.includes(key)) {
          yield failureChunk('IOS_CHAT_MODEL_FAILED');
          return;
        }
        let tail = Math.min(key.length - 1, combined.length);
        while (tail > 0 && !key.startsWith(combined.slice(-tail))) tail--;
        if (tail > 0) tails.set(chunk.index, { ...chunk, text: combined.slice(-tail) });
        else tails.delete(chunk.index);
        const text = combined.slice(0, combined.length - tail);
        if (text) yield { ...chunk, text };
        continue;
      }
      if (chunk.type === 'block-end') {
        if (chunk.block.text?.includes(key)) {
          yield failureChunk('IOS_CHAT_MODEL_FAILED');
          return;
        }
        const tail = tails.get(chunk.index);
        tails.delete(chunk.index);
        if (tail) yield tail;
      }
      // Thinking is off; an upstream replay signature or other metadata is
      // not a place where this text-only route should accept the secret either.
      if (chunk.type === 'finish' && chunk.replayState !== undefined
          && JSON.stringify(chunk.replayState).includes(key)) {
        yield failureChunk('IOS_CHAT_MODEL_FAILED');
        return;
      }
      yield chunk;
    }
  } catch {
    // The official adapter turns transport failures into finish chunks. Here
    // a thrown downstream failure belongs to the outer request/checkpoint chain.
    yield failureChunk(signal?.aborted ? 'IOS_CHAT_MODEL_FAILED' : 'IOS_CHAT_STORAGE_FAILED', signal?.aborted ? 'aborted' : 'error');
  }
}
