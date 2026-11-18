import { randomUUID } from 'node:crypto';

// App-owned presentation/decision carrier for the official ApprovalService.
// This object is intentionally separate from tool execution; no implicit grant.
export function createChatApproval({ timeoutMs = 120_000 } = {}) {
  let pending;
  let closed = false;

  function ask(action, signal) {
    if (closed || pending || signal?.aborted) return Promise.resolve(signal?.aborted ? 'cancelled' : 'unavailable');
    const { promise, resolve } = Promise.withResolvers();
    const request = Object.freeze({ id: randomUUID(), toolName: action.toolName, path: action.path,
      byteLength: action.byteLength, preview: action.preview, previewTruncated: action.previewTruncated });
    const settle = (outcome) => {
      if (pending?.request !== request) return;
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      pending = undefined;
      resolve(outcome);
    };
    const abort = () => settle('cancelled');
    const timer = setTimeout(() => settle('unavailable'), timeoutMs);
    pending = { request, settle, signal };
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    return promise;
  }

  return Object.freeze({
    ask,
    snapshot() { return pending?.request ?? null; },
    answer({ id, allowed } = {}) {
      const current = pending;
      if (closed || !current || current.request.id !== id || typeof allowed !== 'boolean') return false;
      if (current.signal?.aborted) { current.settle('cancelled'); return false; }
      current.settle(allowed ? 'allowed-once' : 'rejected');
      return true;
    },
    close() {
      closed = true;
      pending?.settle('cancelled');
    },
  });
}
