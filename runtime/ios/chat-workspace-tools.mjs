import { Buffer } from 'node:buffer';
import { closeSync, constants, fstatSync, lstatSync, openSync, writeSync } from 'node:fs';
import { lstat, open, opendir, realpath } from 'node:fs/promises';
import { isAbsolute, join, parse, resolve } from 'node:path';
import { TextDecoder } from 'node:util';
import { HarnessError } from '@deepseek-ai/dsh-llm';
import { defineTool } from '@deepseek-ai/dsh-tools';

const MAX_PATH_BYTES = 480;
const MAX_NAME_BYTES = 255;
const MAX_DEPTH = 8;
const MAX_TEXT_BYTES = 4096;
const MAX_RESULT_BYTES = 8192;
const MAX_PREVIEW_BYTES = 512;
const MAX_ENTRIES = 32;
const MAX_SCANNED = 128;
const STAT_OPTIONS = { bigint: true };
const INSPECT_OPTIONS = { ...STAT_OPTIONS, throwIfNoEntry: false };
const INVALID_NAME = /[\\/:%\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;
const INVALID_TEXT = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/u;
// Node exports O_NOFOLLOW, not Darwin's O_NOFOLLOW_ANY (XNU <sys/fcntl.h>).
// Use the latter on Apple platforms to reject links in ANY component at open.
const NO_FOLLOW_ANY = ['ios', 'darwin'].includes(process.platform) ? 0x20000000 : 0;
const NO_FOLLOW = constants.O_NOFOLLOW | NO_FOLLOW_ANY;
const CREATE_FLAGS = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | NO_FOLLOW;
const READ_FLAGS = constants.O_RDONLY | constants.O_NONBLOCK | NO_FOLLOW;
const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

const messages = {
  UNAVAILABLE: 'The private workspace is unavailable.',
  INVALID_ARGUMENTS: 'The tool arguments contain an unexpected field.',
  INVALID_PATH: 'Use a relative workspace path with valid slash-separated names.',
  NOT_FOUND: 'The workspace entry does not exist.',
  UNSAFE_ENTRY: 'The workspace entry is not an allowed file or directory.',
  CHANGED: 'The workspace entry changed during the operation. Check the workspace before retrying.',
  EXISTS: 'The destination already exists. Choose a new file name.',
  TOO_LARGE: 'The workspace text or result exceeds its byte limit.',
  INVALID_TEXT: 'The workspace accepts only valid UTF-8 plain text.',
  PROTECTED: 'The workspace operation includes protected data.',
  APPROVAL_REQUIRED: 'Creating a workspace file requires user approval.',
  APPROVAL_DENIED: 'The workspace file was not approved. No file was created.',
  CREATE_INCOMPLETE: 'File creation did not finish. A new file may remain; inspect it before retrying.',
  IO_FAILED: 'The workspace operation failed.',
};
class WorkspaceError extends HarnessError {
  constructor(kind) {
    super(messages[kind], `IOS_WORKSPACE_${kind}`);
  }
}
const fail = kind => { throw new WorkspaceError(kind); };
function checkAbort(signal) {
  if (signal.aborted) throw Object.assign(new Error('tool call aborted'), { name: 'AbortError' });
}
function mapError(error, signal) {
  if (error instanceof WorkspaceError) throw error;
  checkAbort(signal);
  switch (error?.code) {
    case 'ENOENT': return fail('NOT_FOUND');
    case 'ELOOP': case 'EMLINK': case 'ENOTDIR': return fail('UNSAFE_ENTRY');
    case 'EEXIST': return fail('EXISTS');
    default: return fail('IO_FAILED');
  }
}
function validName(name) {
  return name.length > 0 && name.length <= MAX_NAME_BYTES && name !== '.' && name !== '..'
    && name.isWellFormed() && !INVALID_NAME.test(name) && Buffer.byteLength(name) <= MAX_NAME_BYTES;
}
function pathParts(path) {
  if (path === '.') return [];
  if (typeof path !== 'string' || path.length > MAX_PATH_BYTES || Buffer.byteLength(path) > MAX_PATH_BYTES) return undefined;
  const parts = path.split('/');
  return parts.length <= MAX_DEPTH && parts.every(validName) ? parts : undefined;
}
function assertText(text) {
  if (text.length > MAX_TEXT_BYTES || Buffer.byteLength(text) > MAX_TEXT_BYTES) fail('TOO_LARGE');
  if (!text.isWellFormed() || INVALID_TEXT.test(text)) fail('INVALID_TEXT');
}
function sameEntry(a, b) {
  return a.dev === b.dev && a.ino === b.ino && a.uid === b.uid && a.birthtimeNs === b.birthtimeNs;
}
function sameVersion(a, b) {
  return sameEntry(a, b) && a.ctimeNs === b.ctimeNs && a.mtimeNs === b.mtimeNs;
}
function directoryAllowed(info, root) {
  return info.isDirectory() && info.dev === root.dev && info.uid === root.uid;
}
function fileAllowed(info, root) {
  return info.isFile() && info.nlink === 1n && info.dev === root.dev && info.uid === root.uid;
}
function requireFile(info, root) {
  if (!info) fail('NOT_FOUND');
  if (!fileAllowed(info, root)) fail('UNSAFE_ENTRY');
}
function destinationAvailable(path, root) {
  const info = lstatSync(path, INSPECT_OPTIONS);
  if (!info) return;
  if (!fileAllowed(info, root) && !directoryAllowed(info, root)) fail('UNSAFE_ENTRY');
  fail('EXISTS');
}

// Walk bounded directory components with lstat, never by following a model path
// through realpath. The dedicated root is owned by the App; no other tool or
// importer may rename or link its entries while this workspace is mounted.
function directoryChain(root, parts, signal) {
  checkAbort(signal);
  const current = lstatSync(root.path, INSPECT_OPTIONS);
  if (!current || !sameEntry(root.info, current) || !current.isDirectory() || (current.mode & 0o077n) !== 0n) {
    fail('UNAVAILABLE');
  }
  const entries = [current];
  let path = root.path;
  for (const part of parts) {
    path = join(path, part);
    const info = lstatSync(path, INSPECT_OPTIONS);
    if (!info) fail('NOT_FOUND');
    if (!directoryAllowed(info, root.info)) fail('UNSAFE_ENTRY');
    entries.push(info);
  }
  return { path, entries };
}
function assertSameChain(before, after, equal) {
  if (before.entries.some((info, index) => !equal(info, after.entries[index]))) fail('CHANGED');
}

function output(schema) {
  return {
    schema: { type: 'object', additionalProperties: false, properties: schema },
    render: (_args, value) => [{ type: 'text', text: JSON.stringify(value) }],
  };
}
const pathDescription = `Slash-separated path relative to the App workspace, at most ${MAX_PATH_BYTES} UTF-8 bytes and ${MAX_DEPTH} components.`;
const pathField = { type: 'string', required: true, description: pathDescription };
const lengthField = { type: 'integer', required: true, description: 'UTF-8 byte length of the file.' };

function approvalPreview(text) {
  let length = 0;
  let end = 0;
  for (const character of text) {
    length += Buffer.byteLength(JSON.stringify(character)) - 2;
    if (length > MAX_PREVIEW_BYTES) break;
    end += character.length;
  }
  return { preview: text.slice(0, end), previewTruncated: end < text.length };
}

/** Mount only after the official Cordis tool registry is active. `directory`
 * comes from the trusted App host, not the model or a session cwd. `approve`
 * must settle on abort; only an explicit boolean true grants this one action. */
export async function registerChatWorkspaceTools(ctx, { directory, approve, containsSecret } = {}) {
  if (typeof directory !== 'string' || !isAbsolute(directory) || typeof process.getuid !== 'function'
      || !constants.O_NOFOLLOW || !constants.O_NONBLOCK || !constants.O_EXCL
      || (approve !== undefined && typeof approve !== 'function')
      || (containsSecret !== undefined && typeof containsSecret !== 'function')) fail('UNAVAILABLE');
  let root;
  try {
    const requested = resolve(directory);
    const original = await lstat(requested, STAT_OPTIONS);
    if (!original?.isDirectory() || original.uid !== BigInt(process.getuid()) || (original.mode & 0o077n) !== 0n) {
      fail('UNAVAILABLE');
    }
    const path = await realpath(requested);
    const info = await lstat(path, STAT_OPTIONS);
    if (path === parse(path).root || !info?.isDirectory() || !sameEntry(original, info)
        || (info.mode & 0o077n) !== 0n) fail('UNAVAILABLE');
    root = { path, info };
  } catch { fail('UNAVAILABLE'); }

  function requirePublic(value) {
    if (containsSecret?.(value)) fail('PROTECTED');
  }
  function checkedResult(value) {
    const serialized = JSON.stringify(value);
    if (Buffer.byteLength(serialized) > MAX_RESULT_BYTES) fail('TOO_LARGE');
    requirePublic(serialized);
    return value;
  }
  function register(definition, keys, run) {
    ctx.tools.register(defineTool({ ...definition, async execute(args, exec) {
      const signal = exec.signal;
      try {
        checkAbort(signal);
        if (Object.keys(args).some(key => !keys.includes(key))) fail('INVALID_ARGUMENTS');
        const path = Object.hasOwn(args, 'path') ? args.path : '.';
        const parts = pathParts(path);
        if (!parts || (parts.length === 0 && definition.name !== 'workspace_list')) fail('INVALID_PATH');
        requirePublic(path);
        return await run(path, parts, args, signal, exec);
      } catch (error) { return mapError(error, signal); }
    } }));
  }

  register({
    name: 'workspace_list',
    description: `List one directory in the App-private workspace (not recursive). Returns at most ${MAX_ENTRIES} entries and may omit unsupported entries.`,
    parameters: { path: { type: 'string', description: `${pathDescription} Omit or use . for the workspace root.` } },
    output: output({ path: pathField, truncated: { type: 'boolean', required: true }, entries: {
      type: 'array', required: true, items: { type: 'object', additionalProperties: false, properties: {
        name: { type: 'string', required: true },
        kind: { type: 'string', required: true, enum: ['file', 'directory'] },
      } },
    } }),
  }, ['path'], async (path, parts, _args, signal) => {
    const before = directoryChain(root, parts, signal);
    const dir = await opendir(before.path, { encoding: 'buffer', bufferSize: 8 });
    const entries = [];
    let truncated = false;
    try {
      assertSameChain(before, directoryChain(root, parts, signal), sameVersion);
      // Reserve space for the larger false boolean and check serialized sizes,
      // including Unicode and JSON escaping, before admitting another entry.
      let bytes = Buffer.byteLength(JSON.stringify({ path, entries, truncated }));
      for (let scanned = 0; scanned <= MAX_SCANNED; scanned++) {
        checkAbort(signal);
        const dirent = await dir.read();
        checkAbort(signal);
        if (!dirent) break;
        if (scanned === MAX_SCANNED) { truncated = true; break; }
        let name;
        try { name = decoder.decode(dirent.name); } catch { continue; }
        const full = path === '.' ? name : `${path}/${name}`;
        if (!validName(name) || !pathParts(full) || containsSecret?.(full)) continue;
        const info = lstatSync(join(before.path, name), INSPECT_OPTIONS);
        if (!info) continue;
        const kind = directoryAllowed(info, root.info) ? 'directory' : fileAllowed(info, root.info) ? 'file' : undefined;
        if (!kind) continue;
        const entry = { name, kind };
        bytes += Buffer.byteLength(JSON.stringify(entry)) + (entries.length === 0 ? 0 : 1);
        if (entries.length === MAX_ENTRIES || bytes > MAX_RESULT_BYTES) { truncated = true; break; }
        entries.push(entry);
      }
    } finally { await dir.close(); }
    // opendir is pathname-based in Node. Recheck identities and versions before
    // revealing any names; no byte reads are performed on listed entries.
    assertSameChain(before, directoryChain(root, parts, signal), sameVersion);
    entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    return checkedResult({ path, entries, truncated });
  });

  register({
    name: 'workspace_read_text',
    description: `Read an existing UTF-8 text file from the App-private workspace, up to ${MAX_TEXT_BYTES} bytes and within the rendered result limit.`,
    parameters: { path: pathField },
    output: output({ path: pathField, text: { type: 'string', required: true }, byteLength: lengthField }),
  }, ['path'], async (path, parts, _args, signal) => {
    const parents = parts.slice(0, -1);
    const before = directoryChain(root, parents, signal);
    const target = join(before.path, parts.at(-1));
    const info = lstatSync(target, INSPECT_OPTIONS);
    requireFile(info, root.info);
    if (info.size > BigInt(MAX_TEXT_BYTES)) fail('TOO_LARGE');
    const file = await open(target, READ_FLAGS);
    try {
      const opened = await file.stat(STAT_OPTIONS);
      checkAbort(signal);
      requireFile(opened, root.info);
      if (!sameVersion(info, opened)) fail('CHANGED');
      assertSameChain(before, directoryChain(root, parents, signal), sameVersion);
      // Read one overflow byte, not readFile: stat is not an I/O limit.
      const buffer = Buffer.alloc(MAX_TEXT_BYTES + 1);
      let byteLength = 0;
      while (byteLength < buffer.length) {
        const { bytesRead } = await file.read(buffer, byteLength, buffer.length - byteLength, byteLength);
        checkAbort(signal);
        if (!bytesRead) break;
        byteLength += bytesRead;
      }
      if (byteLength > MAX_TEXT_BYTES) fail('TOO_LARGE');
      const final = await file.stat(STAT_OPTIONS);
      requireFile(final, root.info);
      if (!sameVersion(info, final) || final.size !== BigInt(byteLength)) fail('CHANGED');
      assertSameChain(before, directoryChain(root, parents, signal), sameVersion);
      let text;
      try { text = decoder.decode(buffer.subarray(0, byteLength)); } catch { fail('INVALID_TEXT'); }
      assertText(text);
      requirePublic(text);
      return checkedResult({ path, text, byteLength });
    } finally { await file.close(); }
  });

  register({
    name: 'workspace_create_text',
    description: `Create a new UTF-8 text file (up to ${MAX_TEXT_BYTES} bytes) under an existing App workspace directory. Explicit user approval is required; existing entries are never replaced.`,
    parameters: { path: pathField, text: { type: 'string', required: true, description: 'Complete text for the new file.' } },
    output: output({ path: pathField, byteLength: lengthField }),
  }, ['path', 'text'], async (path, parts, { text }, signal, exec) => {
    assertText(text);
    requirePublic(text);
    const bytes = Buffer.from(text, 'utf8');
    const result = checkedResult({ path, byteLength: bytes.length });
    if (!approve) fail('APPROVAL_REQUIRED');
    const parents = parts.slice(0, -1);
    const before = directoryChain(root, parents, signal);
    const target = join(before.path, parts.at(-1));
    destinationAvailable(target, root.info);
    const action = Object.freeze({ toolName: 'workspace_create_text', ...result, ...approvalPreview(text) });
    requirePublic(JSON.stringify(action));
    checkAbort(signal);
    let approved;
    try {
      const decision = approve(action, signal, exec);
      if (decision && typeof decision.then === 'function') approved = await decision;
    } catch { checkAbort(signal); fail('APPROVAL_REQUIRED'); }
    checkAbort(signal);
    if (approved !== true) fail('APPROVAL_DENIED');
    // Recheck after waiting for the human. Keep the bounded exclusive create
    // and write together, with no await after the last cancellation check.
    assertSameChain(before, directoryChain(root, parents, signal), sameEntry);
    destinationAvailable(target, root.info);
    checkAbort(signal);
    const fd = openSync(target, CREATE_FLAGS, 0o600);
    try {
      try {
        const info = fstatSync(fd, STAT_OPTIONS);
        requireFile(info, root.info);
        for (let written = 0; written < bytes.length;) {
          const count = writeSync(fd, bytes, written, bytes.length - written, written);
          if (count <= 0) fail('CREATE_INCOMPLETE');
          written += count;
        }
      } finally { closeSync(fd); }
    } catch { fail('CREATE_INCOMPLETE'); }
    return result;
  });
}
