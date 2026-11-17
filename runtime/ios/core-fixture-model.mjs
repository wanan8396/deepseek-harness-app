import { LlmAdapter, LlmError } from '@deepseek-ai/dsh-llm';
import { setTimeout as delay } from 'node:timers/promises';

// This substitutes only the external model endpoint. DSH's Loader, AgentLoop,
// transcript fold, chunk assembly and cancellation remain the actual suppliers.
export const name = 'ios-fixture-model';
export const inject = ['llm'];
export const PROVIDER = 'ios-offline-fixture';
export const MODEL = 'deterministic-text';
const textOf = (message) => message.content.filter((block) => block.type === 'text').map((block) => block.text).join('');

class OfflineFixture extends LlmAdapter {
  constructor(challenge) {
    super();
    this.challenge = challenge;
    this.requests = [];
    this.cancelObserved = false;
    this.errorObserved = false;
    this.cancelStarted = Promise.withResolvers();
  }
  providerInfo(provider) { return { id: provider, name: 'Offline iOS test fixture (not a live model)' }; }
  async resolveModel(provider, model) {
    if (provider !== PROVIDER || model !== MODEL) throw new Error('IOS_FIXTURE_ROUTE_INVALID');
    return { provider, id: model, name: 'Offline test fixture', inputModalities: ['text'],
      context: { contextWindow: 32768 }, defaultMaxTokens: 128 };
  }
  async *stream(options) {
    if (options.provider !== PROVIDER || options.model !== MODEL || !options.signal) {
      throw new Error('IOS_FIXTURE_REQUEST_INVALID');
    }
    options.signal.throwIfAborted();
    const messages = options.messages.map((message) => ({ role: message.role, text: textOf(message) }));
    const input = messages.findLast((message) => message.role === 'user' && message.text.startsWith('probe-'))?.text;
    this.requests.push({ messages, input });
    if (input === `probe-error:${this.challenge}`) {
      this.errorObserved = true;
      throw new LlmError('IOS_FIXTURE_EXPECTED_ERROR', 'AUTH');
    }
    if (input === `probe-cancel:${this.challenge}`) {
      yield { type: 'block-start', index: 0, blockType: 'text' };
      yield { type: 'text-delta', index: 0, text: 'partial-fixture-output' };
      this.cancelStarted.resolve();
      const aborted = Promise.withResolvers();
      const onAbort = () => aborted.resolve();
      options.signal.addEventListener('abort', onAbort, { once: true });
      try {
        if (!options.signal.aborted) await aborted.promise;
        this.cancelObserved = options.signal.aborted;
        options.signal.throwIfAborted();
      } finally {
        options.signal.removeEventListener('abort', onAbort);
      }
      throw new Error('IOS_FIXTURE_CANCEL_DID_NOT_ABORT');
    }
    let answer;
    if (input === `probe-first:${this.challenge}`) answer = `${this.challenge}:first`;
    else if (input === `probe-second:${this.challenge}`) answer = `${this.challenge}:second`;
    else if (input === `probe-recover:${this.challenge}`) answer = `${this.challenge}:recovered`;
    else throw new Error('IOS_FIXTURE_INPUT_INVALID');
    const cut = Math.floor(answer.length / 2);
    yield { type: 'block-start', index: 0, blockType: 'text' };
    yield { type: 'text-delta', index: 0, text: answer.slice(0, cut) };
    await delay(1, undefined, { signal: options.signal });
    yield { type: 'text-delta', index: 0, text: answer.slice(cut) };
    yield { type: 'block-end', index: 0, block: { type: 'text', text: answer } };
    yield { type: 'usage', usage: { inputTokens: 8, outputTokens: 8 } };
    yield { type: 'finish', reason: { kind: 'stop' } };
  }
}

export function apply(ctx, config) {
  if (!/^[a-f0-9]{64}$/.test(config?.challenge)) throw new Error('IOS_FIXTURE_CHALLENGE_INVALID');
  const fixture = new OfflineFixture(config.challenge);
  ctx.provide('iosFixtureModel', fixture);
  ctx.llm.registerAdapter([PROVIDER], fixture);
}
