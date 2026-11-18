import { AsyncLocalStorage } from 'node:async_hooks';
import { Buffer } from 'node:buffer';
import { TextDecoder } from 'node:util';

const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
const forbidden = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/u;
const basename = /^[\p{L}\p{M}\p{N}_(). -]{1,120}\.(?:txt|md|csv|json|log|tsv)$/iu;
const base64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u;
const hash = /^sha256:[0-9a-f]{64}$/u;
export const TEXT_ATTACHMENT_MAX = 12 * 1024;
export const TEXT_ATTACHMENT_PROMPT_MAX = 3;
const CONTEXT_MAX = 48 * 1024;
const CONTEXT_FILES_MAX = 12;

function decode(bytes, containsSecret) {
  try {
    const text = decoder.decode(bytes);
    return forbidden.test(text) || containsSecret(text) ? undefined : text;
  } catch { return undefined; }
}

export function decodeOfficialTextAttachment(request, containsSecret) {
  if (typeof request?.name !== 'string' || !basename.test(request.name) || request.name.startsWith('.')
      || Buffer.byteLength(request.name) > 180 || containsSecret(request.name)
      || typeof request.data !== 'string' || !request.data || request.data.length > 4 * Math.ceil(TEXT_ATTACHMENT_MAX / 3)
      || !base64.test(request.data)) return undefined;
  const bytes = Buffer.from(request.data, 'base64');
  if (bytes.length > TEXT_ATTACHMENT_MAX || bytes.toString('base64') !== request.data || decode(bytes, containsSecret) === undefined) return undefined;
  return bytes;
}

/** Capture only typed durable user FileBlocks. The official LLM layer projects
 * them to handles before adapter dispatch; replace the exact handle at the
 * exact durable message id/position, never parse paths out of generated text. */
export function createOfficialTextMaterializer(scope, containsSecret, lifetime) {
  const captures = new AsyncLocalStorage();
  async function* run(options, next) {
    const wanted = new Map();
    let count = 0;
    let total = 0;
    const signal = options.signal ? AbortSignal.any([lifetime, options.signal]) : lifetime;
    for (const message of [...options.messages].reverse()) {
      if (message.role !== 'user' || typeof message.id !== 'string' || wanted.has(message.id)) continue;
      const slots = new Map();
      for (const [index, block] of message.content.entries()) {
        const ref = block.type === 'file' ? block.attachment : undefined;
        if (!ref || typeof ref.name !== 'string' || !basename.test(ref.name) || containsSecret(ref.name)
            || !hash.test(ref.attachmentId) || !Number.isSafeInteger(ref.bytes) || ref.bytes < 1 || ref.bytes > TEXT_ATTACHMENT_MAX) continue;
        const handle = scope.llm.fileRequestText(ref);
        let value = '[Text attachment omitted: context limit.]';
        if (count < CONTEXT_FILES_MAX && total + ref.bytes <= CONTEXT_MAX) {
          count++;
          total += ref.bytes;
          try {
            const bytes = Buffer.alloc(ref.bytes);
            let offset = 0;
            for await (const chunk of scope.attachments.readFileStream(ref, signal)) {
              signal.throwIfAborted();
              if (offset + chunk.byteLength > bytes.length) throw new Error('attachment byte length changed');
              bytes.set(chunk, offset);
              offset += chunk.byteLength;
            }
            const text = offset === ref.bytes ? decode(bytes, containsSecret) : undefined;
            bytes.fill(0);
            value = text === undefined ? '[Text attachment no longer available.]'
              : `\n[User attachment: ${JSON.stringify(ref.name)}]\n${text}\n[End attachment]\n`;
          } catch {
            if (signal.aborted) signal.throwIfAborted();
            value = '[Text attachment no longer available.]';
          }
        }
        slots.set(index, { handle, value });
      }
      if (slots.size) wanted.set(message.id, slots);
    }
    const cursor = captures.run(wanted, () => next()[Symbol.asyncIterator]());
    try {
      while (true) {
        const item = await captures.run(wanted, () => cursor.next());
        if (item.done) return;
        yield item.value;
      }
    } finally { await captures.run(wanted, () => cursor.return?.()); }
  }
  function project(options) {
    const wanted = captures.getStore();
    if (!wanted?.size) return options;
    const messages = options.messages.map(message => {
      const slots = message.role === 'user' ? wanted.get(message.id) : undefined;
      if (!slots) return message;
      const content = message.content.map((block, index) => {
        const replacement = slots.get(index);
        return replacement && block.type === 'text' && block.text === replacement.handle
          ? { type: 'text', text: replacement.value } : block;
      });
      return { ...message, content };
    });
    return { ...options, messages };
  }
  return { run, project };
}
