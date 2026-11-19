import { Buffer } from 'node:buffer';
import { lstat, mkdir, realpath } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { apply as applyObservationPolicy } from '@deepseek-ai/dsh-fs-observation-policy';
import { LlmAdapter } from '@deepseek-ai/dsh-llm';
import { createScope, scopeOf } from '@deepseek-ai/dsh-scope';
import { apply as applyFsTools } from '@deepseek-ai/dsh-tool-fs';
import {
  CHAT_CHANNEL_PROVIDER, createChatChannelAdapter, guardChatChannelStream, normalizeChatChannel,
} from './chat-model-channel.mjs';
import {
  createOfficialWorkspaceFileSystem, OFFICIAL_WORKSPACE_PATH, registerOfficialWorkspaceSearch,
} from './official-workspace-fs.mjs';

const WORKSPACE = 'Workspace';
const MUTATIONS = new Set(['write', 'edit']);
const FS_TOOL_CONFIG = Object.freeze({
  read: true, write: true, edit: true, readImage: false, applyPatch: false,
  readLimit: 200, readMaxLineLength: 2000, readMaxBytes: 8192, readStreamMinSize: 4096,
});
const APPROVAL_REASON = 'Change a file in this app’s workspace';
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
  const operation = action.operation === 'create' ? 'Create' : 'Update';
  const title = `${operation} ${JSON.stringify(action.path)} (${action.byteLength} UTF-8 bytes)`;
  const preview = JSON.stringify(action.preview).replace(/[\p{Cf}\p{Zl}\p{Zp}]/gu, char => {
    const code = char.codePointAt(0);
    return code <= 0xFFFF ? `\\u${code.toString(16).padStart(4, '0')}` : `\\u{${code.toString(16)}}`;
  });
  const detail = `${title}\nPreview: ${preview}${action.previewTruncated ? ' …' : ''}`;
  return Buffer.byteLength(detail) <= DISPLAY_LIMIT ? detail : title;
}

function mountAgentWorkspace(owner, agent, directory, containsSensitiveText, life, mounts) {
  // The physical session directory is assigned by the App Host, not by the
  // model. Non-Workspace agents must never inherit a filesystem tool layer.
  if (agent.session.header.cwd !== directory || mounts.has(agent)) return;
  if (scopeOf(agent.ctx) !== agent || life.aborted) throw failure('IOS_OFFICIAL_APP_SERVICES_CLOSED');
  const mount = createScope(agent.ctx, agent);
  mounts.set(agent, mount);
  const isolated = mount.ctx.isolate('fs').isolate('workingDirectory');
  const controller = new AbortController();
  const signal = AbortSignal.any([life, controller.signal]);
  let dispatch;
  isolated.effect(() => () => {
    controller.abort();
    mounts.delete(agent);
  });

  createOfficialWorkspaceFileSystem(isolated, {
    directory, containsSensitiveText, lifetimeSignal: signal,
    async approve(action, approvalSignal, callerSignal) {
      const active = dispatch;
      const live = () => dispatch === active && active.exec.agent === agent
        && active.exec.name === action.tool && active.exec.callId === active.callId
        && active.exec.signal === callerSignal && !signal.aborted && !approvalSignal.aborted;
      if (!active || active.requested || !live()) return false;
      active.requested = true;
      const display = approvalDisplay(action);
      if (containsSensitiveText(display)) return false;
      const decision = await owner.approval.request({
        agent, callId: active.callId, toolName: action.tool, signal: approvalSignal,
        reason: APPROVAL_REASON, displayReason: { en: display },
      });
      return decision === 'allowed-once' && live();
    },
  });
  isolated.provide('workingDirectory', Object.freeze({
    async ensure(requester, callerSignal) {
      if (requester !== agent || signal.aborted || callerSignal?.aborted) {
        throw failure('IOS_OFFICIAL_WORKSPACE_UNAVAILABLE');
      }
      return OFFICIAL_WORKSPACE_PATH;
    },
  }));
  isolated.systemPrompt.context({
    name: 'ios-workspace:current', order: isolated.systemPrompt.getContextOrder('WORKING_DIRECTORY'),
    interpolate: false, text: `Current working directory: ${JSON.stringify(OFFICIAL_WORKSPACE_PATH)}.`,
  });
  isolated.on('tools/execute', async (exec, next) => {
    if (exec.agent !== agent || !MUTATIONS.has(exec.name)) return next();
    if (signal.aborted || dispatch || exec.parent !== undefined || typeof exec.callId !== 'string'
        || !exec.callId || containsSensitiveText(exec.callId)) throw failure('IOS_OFFICIAL_WORKSPACE_UNAVAILABLE');
    const previous = exec.signal;
    // Giving each dispatch its own wrapper signal makes the rc.3 pipeline fuse
    // a fresh body signal. The provider compares the *live* exec.signal above,
    // not this wrapper signal or a model-supplied tool ID alone.
    exec.signal = AbortSignal.any([signal, previous]);
    dispatch = { exec, callId: exec.callId, requested: false };
    try { return await next(); }
    finally {
      dispatch = undefined;
      exec.signal = previous;
    }
  }, { prepend: true });
  applyFsTools(isolated, FS_TOOL_CONFIG);
  registerOfficialWorkspaceSearch(isolated);
}

// Join the lifetime at adapter dispatch, where the actual HTTP request sees it.
// The official llm/stream waterfall receives a frozen request and a nullary next.
class LifetimeChannelAdapter extends LlmAdapter {
  #adapter;
  #life;
  constructor(adapter, life) { super(); this.#adapter = adapter; this.#life = life; }
  providerInfo(provider) { return this.#adapter.providerInfo(provider); }
  providerRetryPolicy(provider) { return this.#adapter.providerRetryPolicy(provider); }
  listModels(provider) { return this.#adapter.listModels(provider); }
  resolveModel(provider, model) { return this.#adapter.resolveModel(provider, model); }
  stream(options) {
    const signal = options.signal ? AbortSignal.any([this.#life, options.signal]) : this.#life;
    return this.#adapter.stream({ ...options, signal });
  }
}

/**
 * One observation-policy installation per live Host. Only admitted Agents
 * receive the official text tools; the Host needs its native executor row and,
 * for browser answers, the official dsh-api-remotes event source and answering peer.
 * Native inputs must never come from the WebKit page. The Host must use
 * containsSensitiveText before accepting RPC content into a durable Session.
 */
export async function registerOfficialAppServices(ctx, { workspace, stateDirectory, channel, apiKey, lifetimeSignal } = {}) {
  const route = checkedChannel(channel, apiKey);
  channel = undefined;
  if (!ctx || typeof ctx.plugin !== 'function' || typeof ctx.get !== 'function'
      || typeof ctx.get('llm')?.registerAdapter !== 'function'
      || typeof ctx.get('tools')?.register !== 'function'
      || typeof ctx.get('agents')?.list !== 'function'
      || typeof ctx.get('systemPrompt')?.context !== 'function'
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
  const mounts = new Map();
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
    fiber = ctx.plugin({ name: 'ios-official-app-services', inject: ['llm', 'tools', 'agents', 'systemPrompt', 'approval'],
      apply(scope) {
        scope.effect(() => async () => {
          deactivate();
          await Promise.all([...mounts.values()].map(mount => mount.dispose()));
        });
        scope.on('llm/stream', (options, next) => {
          if (options.provider !== CHAT_CHANNEL_PROVIDER) return next();
          const signal = options.signal ? AbortSignal.any([life, options.signal]) : life;
          return guardChatChannelStream(next, key, signal, options.tools);
        }, { prepend: true });
        // The rc.3 filesystem intent waterfalls are unbound; the official
        // policy owns these event slots once, not once per Agent. Its state is
        // keyed by Session plus the isolated provider's salted target key.
        applyObservationPolicy(scope);
        const mount = agent => mountAgentWorkspace(scope, agent, directory, containsSensitiveText, life, mounts);
        scope.on('agent/created', ({ agent }) => { mount(agent); });
        for (const agent of scope.agents.list()) mount(agent);
        if (life.aborted) throw failure('IOS_OFFICIAL_APP_SERVICES_CLOSED');
        const adapter = createChatChannelAdapter(directory, route, () => key);
        scope.llm.registerAdapter([CHAT_CHANNEL_PROVIDER], new LifetimeChannelAdapter(adapter, life));
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
