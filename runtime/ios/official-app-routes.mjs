import { decodeOfficialTextAttachment, TEXT_ATTACHMENT_PROMPT_MAX } from './official-text-attachments.mjs';

// Narrow owner surface for the App's text Host. This layer does
// not replace generated Typert validation or interpret filesystem paths.
const ID = /^session-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/u;
const MAX_BODY = 96 * 1024;
const MAX_TEXT = 16 * 1024;
const MAX_PARTS = 32;
const RECORD_DEPTH = 12;
const UPLOAD = 'fileUploads/upload';
const RECEIPT = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/u;
const READ = new Set(['session/list', 'session/search', 'session/modelCatalog', 'session/projections',
  'session/events', 'session/page', 'session/canOpenWorkspacePath', 'workspace/initializeDefault']);
const WRITE = new Set(['session/create', 'session/selectModel', 'session/rename', 'session/prompt',
  'session/updateQueue', 'session/cancel', '$events/result']);
const STREAM = new Set(['$events', 'remoteAccess/follow', 'workspace/follow', 'session/control', 'session/follow']);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const hasOwn = (value, key) => Object.hasOwn(value, key);
const fail = status => ({ ok: false, status });

function content(parts, containsSensitiveText, allowFiles = false) {
  if (!Array.isArray(parts) || parts.length > MAX_PARTS) return false;
  let bytes = 0;
  let stitched = '';
  const receipts = new Set();
  for (const part of parts) {
    if (!object(part) || Object.keys(part).length !== 2) return false;
    if (part.type === 'file' && allowFiles && typeof part.receiptId === 'string' && RECEIPT.test(part.receiptId)) {
      if (receipts.has(part.receiptId) || receipts.size >= TEXT_ATTACHMENT_PROMPT_MAX) return false;
      receipts.add(part.receiptId);
      continue;
    }
    if (part.type !== 'text' || typeof part.text !== 'string' || !part.text.isWellFormed()) return false;
    bytes += Buffer.byteLength(part.text);
    stitched += part.text;
  }
  return bytes <= MAX_TEXT && !containsSensitiveText(stitched);
}

function inspect(value, check, depth = 0) {
  if (depth > RECORD_DEPTH) return false;
  if (typeof value === 'string') return value.isWellFormed() && !check(value);
  if (value === null || ['number', 'boolean'].includes(typeof value)) return true;
  if (Array.isArray(value)) return value.every(item => inspect(item, check, depth + 1));
  return object(value) && Object.entries(value).every(([key, child]) => key !== '__proto__' && key !== 'constructor'
    && key !== 'prototype' && !check(key) && inspect(child, check, depth + 1));
}

/** The Workspace identity is native-selected and pre-registered against the
 * canonical private directory. Session membership must be resolved on the
 * same live Host; this admission uses no client-supplied cwd or credential. */
export function createOfficialAppRoutePolicy({ workspaceId, containsSensitiveText, hasSession }) {
  if (typeof workspaceId !== 'string' || !workspaceId || typeof containsSensitiveText !== 'function'
      || typeof hasSession !== 'function') throw new TypeError('iOS Host route policy requires live App scope');
  const owned = id => typeof id === 'string' && ID.test(id) && hasSession(id) === true;
  return Object.freeze({
    admitRequest(method, path, text) {
      if (typeof path !== 'string' || method !== 'POST' || !path.startsWith('/api/')) return fail(404);
      const endpoint = path.slice(5);
      if (endpoint !== UPLOAD && !READ.has(endpoint) && !WRITE.has(endpoint)) return fail(404);
      if (typeof text !== 'string' || Buffer.byteLength(text) > MAX_BODY) return fail(413);
      let wire;
      try { wire = JSON.parse(text); } catch { return fail(400); }
      if (!object(wire) || wire.type !== 'client-request' || wire.method !== endpoint
          || typeof wire.rpcId !== 'string' || !object(wire.payload?.args) || !inspect(wire, containsSensitiveText)) return fail(400);
      const args = wire.payload.args;
      const request = args.request;
      if (endpoint === UPLOAD) {
        if (!owned(args.agentId)) return fail(403);
        if (Object.keys(args).length !== 2 || !object(request) || Object.keys(request).length !== 2) return fail(400);
        const bytes = decodeOfficialTextAttachment(request, containsSensitiveText);
        if (!bytes) return fail(415);
        return { ok: true, endpoint, body: JSON.stringify(wire), upload: { sessionId: args.agentId } };
      } else if (endpoint === 'session/create') {
        if (!object(request) || hasOwn(request, 'cwd') || hasOwn(request, 'agentPreset')
            || (hasOwn(request, 'workspaceId') && request.workspaceId !== workspaceId)
            || (hasOwn(request, 'sessionId') && !owned(request.sessionId))) return fail(403);
        request.workspaceId = workspaceId;
      } else if (endpoint.startsWith('session/') && (hasOwn(args, 'request') || WRITE.has(endpoint))) {
        if (!object(request)) return fail(400);
        const id = request.sessionId ?? request.address?.sessionId;
        if (endpoint !== 'session/search' && (!owned(id) || (request.address && request.address.kind !== 'session'))) return fail(403);
        if (endpoint === 'session/prompt' && !content(request.content, containsSensitiveText, true)) return fail(415);
        if (endpoint === 'session/updateQueue' && request.action?.kind === 'edit'
            && !content(request.action.content, containsSensitiveText)) return fail(415);
      }
      return { ok: true, endpoint, body: JSON.stringify(wire) };
    },
    admitStream(endpoint, payload) {
      if (!STREAM.has(endpoint) || !object(payload?.args) || !inspect(payload, containsSensitiveText)) return false;
      if (endpoint !== 'session/follow') return Object.keys(payload.args).length === 0;
      const address = payload.args.request?.address;
      return address?.kind === 'session' && owned(address.sessionId);
    },
  });
}
