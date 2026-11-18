import { Buffer } from 'node:buffer';
import { lstat, mkdir, realpath } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { LlmAdapter } from '@deepseek-ai/dsh-llm';
import {
  CHAT_CHANNEL_PROVIDER, createChatChannelAdapter, guardChatChannelStream, normalizeChatChannel,
} from './chat-model-channel.mjs';
import { registerChatWorkspaceTools } from './chat-workspace-tools.mjs';
import { createOfficialTextMaterializer } from './official-text-attachments.mjs';

const WORKSPACE = 'Workspace';
const CREATE_TOOL = 'workspace_create_text';
const TOOLS = new Set(['workspace_list', 'workspace_read_text', CREATE_TOOL]);
const APPROVAL_REASON = 'Create a new file in this app’s workspace';
const APPROVAL_TIMEOUT_MS = 60_000;
const DISPLAY_LIMIT = 1536;
const mounted = new WeakSet();

function failure(code) { return Object.assign(new Error(code), { code }); }
function containsChannelKey(text, key) { return !!key && typeof text === 'string' && text.includes(key); }

function checkedChannel(channel, key) {
  if (typeof key !== 'string' || !key || key.length > 1024 || /[^!-~]/u.test(key)) {
    throw failure('IOS_CHAT_KEY_INVALID');
  }
  const input = { protocol: channel?.protocol, baseUrl: channel?.baseUrl, modelId: channel?.modelId };
  const route = normalizeChatChannel(input);
  const path = new URL(route.baseUrl).pathname;
  // Check escaped ASCII bytes too; a path is not a second credential field.
  const unescapedPath = path.replace(/%([\da-f]{2})/giu, (_match, byte) => String.fromCharCode(parseInt(byte, 16)));
  if ([input.baseUrl, route.baseUrl, unescapedPath, route.modelId, CHAT_CHANNEL_PROVIDER].some(text => containsChannelKey(text, key))) {
    throw failure('IOS_CHAT_CHANNEL_INVALID');
  }
  return route;
}

function selection(route) { return Object.freeze({ provider: CHAT_CHANNEL_PROVIDER, model: route.modelId }); }

/** Public selection for the Host's default-model row; never includes an endpoint or credentials. */
export function officialAppModelSelection(channel, apiKey) {
  return selection(checkedChannel(channel, apiKey));
}

function privateDirectory(stat) {
  return stat.isDirectory() && stat.uid === process.getuid() && (stat.mode & 0o077) === 0;
}

async function canonicalWorkspace(stateDirectory, workspace) {
  try {
    if (typeof process.getuid !== 'function' || typeof workspace !== 'string' || !isAbsolute(workspace)
        || typeof stateDirectory !== 'string' || !isAbsolute(stateDirectory)) throw new Error();
    const statePath = resolve(stateDirectory);
    const requested = resolve(workspace);
    const before = await lstat(statePath);
    const state = await realpath(statePath);
    const parent = await lstat(state);
    // iOS can spell native parents as /var or /private/var. Compare their real
    // paths, but never accept a symlink at the state or Workspace leaf itself.
    if (dirname(state) === state || !privateDirectory(before) || !privateDirectory(parent)
        || before.dev !== parent.dev || before.ino !== parent.ino
        || basename(requested) !== WORKSPACE || await realpath(dirname(requested)) !== state) throw new Error();
    const path = join(state, WORKSPACE);
    await mkdir(path, { mode: 0o700 }).catch(error => { if (error?.code !== 'EEXIST') throw error; });
    const entry = await lstat(path);
    if (!privateDirectory(entry) || entry.dev !== parent.dev || await realpath(path) !== path) throw new Error();
    return path;
  } catch {
    throw failure('IOS_OFFICIAL_WORKSPACE_UNAVAILABLE');
  }
}

function approvalDisplay(action) {
  // Keep invisible formatting controls visible and do not cut the path.
  const title = `${APPROVAL_REASON}\n${JSON.stringify(action.path)} (${action.byteLength} UTF-8 bytes)`;
  const preview = JSON.stringify(action.preview).replace(/[\p{Cf}\p{Zl}\p{Zp}]/gu, char => {
    const code = char.codePointAt(0);
    return code <= 0xFFFF ? `\\u${code.toString(16).padStart(4, '0')}` : `\\u{${code.toString(16)}}`;
  });
  const detail = `${title}\nPreview: ${preview}${action.previewTruncated ? ' …' : ''}`;
  return Buffer.byteLength(detail) <= DISPLAY_LIMIT ? detail : title;
}

// Join the lifetime at adapter dispatch, where the actual HTTP request sees it.
// The official llm/stream waterfall receives a frozen request and a nullary next.
class LifetimeChannelAdapter extends LlmAdapter {
  #adapter;
  #life;
  #project;
  constructor(adapter, life, project) { super(); this.#adapter = adapter; this.#life = life; this.#project = project; }
  providerInfo(provider) { return this.#adapter.providerInfo(provider); }
  providerRetryPolicy(provider) { return this.#adapter.providerRetryPolicy(provider); }
  listModels(provider) { return this.#adapter.listModels(provider); }
  resolveModel(provider, model) { return this.#adapter.resolveModel(provider, model); }
  stream(options) {
    const signal = options.signal ? AbortSignal.any([this.#life, options.signal]) : this.#life;
    return this.#adapter.stream({ ...this.#project(options), signal });
  }
}

/**
 * One installation per live Host. The three tools are registered with the real
 * tools service; the Host also needs its native executor row and, for browser
 * answers, the official dsh-api-remotes event source and answering peer.
 * Native inputs must never come from the WebKit page. The Host must use
 * containsSensitiveText before accepting RPC content into a durable Session.
 */
export async function registerOfficialAppServices(ctx, { workspace, stateDirectory, channel, apiKey, lifetimeSignal } = {}) {
  const route = checkedChannel(channel, apiKey);
  channel = undefined;
  if (!ctx || typeof ctx.plugin !== 'function' || typeof ctx.get !== 'function'
      || typeof ctx.get('llm')?.registerAdapter !== 'function'
      || typeof ctx.get('tools')?.register !== 'function'
      || typeof ctx.get('approval')?.request !== 'function'
      || !(lifetimeSignal instanceof AbortSignal)) throw failure('IOS_OFFICIAL_APP_SERVICES_UNAVAILABLE');
  if (mounted.has(ctx)) throw failure('IOS_OFFICIAL_APP_SERVICES_ALREADY_MOUNTED');
  if (lifetimeSignal.aborted) throw failure('IOS_OFFICIAL_APP_SERVICES_CLOSED');
  mounted.add(ctx);

  const controller = new AbortController();
  const life = AbortSignal.any([controller.signal, lifetimeSignal]);
  let key = apiKey;
  apiKey = undefined;
  const forgetKey = () => { key = undefined; };
  const containsSensitiveText = text => containsChannelKey(text, key);
  life.addEventListener('abort', forgetKey, { once: true });
  let fiber;
  let closing;
  const deactivate = () => {
    controller.abort();
    forgetKey();
    life.removeEventListener('abort', forgetKey);
  };
  const dispose = () => closing ??= (async () => {
    deactivate();
    try { await fiber?.dispose(); }
    finally { mounted.delete(ctx); }
  })();

  try {
    const directory = await canonicalWorkspace(stateDirectory, workspace);
    if (life.aborted) throw failure('IOS_OFFICIAL_APP_SERVICES_CLOSED');
    fiber = ctx.plugin({ name: 'ios-official-app-services', inject: ['llm', 'tools', 'approval'],
      async apply(scope) {
        scope.effect(() => deactivate);
        const files = createOfficialTextMaterializer(scope, containsSensitiveText, life);
        scope.on('llm/stream', (options, next) => {
          if (options.provider !== CHAT_CHANNEL_PROVIDER) return next();
          const signal = options.signal ? AbortSignal.any([life, options.signal]) : life;
          return guardChatChannelStream(() => files.run(options, next), key, signal, options.tools);
        }, { prepend: true });
        scope.on('tools/execute', async (exec, next) => {
          if (!TOOLS.has(exec.name)) return next();
          const previous = exec.signal;
          exec.signal = AbortSignal.any([life, previous]);
          try { return await next(); }
          finally { exec.signal = previous; }
        }, { prepend: true });
        await registerChatWorkspaceTools(scope, {
          directory,
          containsSecret: containsSensitiveText,
          approve: async (action, signal, exec) => {
            if (action.toolName !== CREATE_TOOL || exec?.name !== CREATE_TOOL || exec.signal !== signal
                || !exec.agent?.session || typeof exec.callId !== 'string' || !exec.callId
                || containsSensitiveText(exec.callId) || life.aborted || signal.aborted) return false;
            const display = approvalDisplay(action);
            if (containsSensitiveText(display)) return false;
            const combined = AbortSignal.any([signal, life, AbortSignal.timeout(APPROVAL_TIMEOUT_MS)]);
            const decision = await scope.approval.request({
              agent: exec.agent, callId: exec.callId, toolName: CREATE_TOOL, signal: combined,
              reason: APPROVAL_REASON, displayReason: { en: display },
            });
            return decision === 'allowed-once' && !combined.aborted;
          },
        });
        if (life.aborted) throw failure('IOS_OFFICIAL_APP_SERVICES_CLOSED');
        const adapter = createChatChannelAdapter(directory, route, () => key);
        scope.llm.registerAdapter([CHAT_CHANNEL_PROVIDER], new LifetimeChannelAdapter(adapter, life, files.project));
      },
    });
    const active = await fiber;
    if (life.aborted) throw failure('IOS_OFFICIAL_APP_SERVICES_CLOSED');
    if (active.state !== 2) throw failure('IOS_OFFICIAL_APP_SERVICES_UNAVAILABLE');
    return Object.freeze({ workspace: directory, modelSelection: selection(route), containsSensitiveText, dispose });
  } catch (error) {
    await dispose();
    if (error?.code === 'IOS_OFFICIAL_WORKSPACE_UNAVAILABLE' || error?.code === 'IOS_OFFICIAL_APP_SERVICES_CLOSED') throw error;
    throw failure('IOS_OFFICIAL_APP_SERVICES_UNAVAILABLE');
  }
}
