import { Buffer } from 'node:buffer';
import { createHash, randomBytes } from 'node:crypto';
import {
  closeSync, constants, fstatSync, fsyncSync, linkSync, lstatSync, opendirSync,
  openSync, readSync, realpathSync, renameSync, unlinkSync, writeSync,
} from 'node:fs';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { TextDecoder } from 'node:util';
import { Context } from '@deepseek-ai/cordis';
import { FileSystem, FsError } from '@deepseek-ai/dsh-fs';

export const OFFICIAL_WORKSPACE_PATH = '/workspace';
export const OFFICIAL_WORKSPACE_LIMITS = Object.freeze({ readBytes: 16_384, writeBytes: 4096 });
const MAX_PATH_BYTES = 480;
const MAX_DEPTH = 8;
const MAX_DIRECTORY_PROBES = 512;
const APPROVAL_TIMEOUT_MS = 60_000;
const PREVIEW_BYTES = 256;
const STATS = { bigint: true };
const LSTAT = { ...STATS, throwIfNoEntry: false };
const READ_FLAGS = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK;
const CREATE_FLAGS = constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW;
const INVALID_NAME = /[\\/:%<>&\uFFFD\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;
const INVALID_TEXT = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/u;
const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

function fail(code, message) { throw new FsError(message, code); }
const denied = () => fail('FS_PERMISSION_DENIED', 'This operation is outside the private Workspace capability.');
const unavailable = () => fail('FS_IO_ERROR', 'The private Workspace is unavailable.');
const changed = () => fail('FS_STALE_VERSION', 'The Workspace entry changed. Re-read it before retrying.');
const absent = () => fail('FS_NOT_FOUND', 'The Workspace entry does not exist.');
const tooLarge = () => fail('FS_TOO_LARGE', 'The Workspace operation exceeds its byte limit.');
const notText = () => fail('FS_NOT_TEXT', 'The Workspace accepts only plain UTF-8 text.');
const unsupported = async () => fail('FS_PERMISSION_DENIED', 'This Workspace operation is not enabled.');

function checkAbort(signal) {
  if (signal?.aborted) fail('FS_ABORTED', 'The Workspace operation was cancelled.');
}
function safeError(error) {
  if (error instanceof FsError) throw error;
  // Node filesystem error messages and abort reasons can contain host paths or secrets.
  if (error?.code === 'ENOENT') return absent();
  if (['ELOOP', 'ENOTDIR', 'EACCES', 'EPERM'].includes(error?.code)) return denied();
  if (error?.code === 'EEXIST') return changed();
  return unavailable();
}
function sameEntry(a, b) {
  return !!a && !!b && a.dev === b.dev && a.ino === b.ino
    && a.uid === b.uid && a.birthtimeNs === b.birthtimeNs;
}
function sameVersion(a, b) {
  return sameEntry(a, b) && a.ctimeNs === b.ctimeNs && a.mtimeNs === b.mtimeNs && a.size === b.size;
}
function privateDir(info, uid) {
  return info?.isDirectory() && info.uid === uid && (info.mode & 0o077n) === 0n;
}
function validName(name) {
  return name.length > 0 && !name.startsWith('.') && name === name.trim()
    && name.isWellFormed() && !INVALID_NAME.test(name) && Buffer.byteLength(name) <= 255;
}
function partsFor(path, cwd) {
  if (typeof path !== 'string' || path.length > MAX_PATH_BYTES || Buffer.byteLength(path) > MAX_PATH_BYTES) denied();
  if (cwd !== undefined && (typeof cwd !== 'string' || cwd.length > MAX_PATH_BYTES || bytes(cwd) > MAX_PATH_BYTES
      || (cwd !== OFFICIAL_WORKSPACE_PATH && !cwd.startsWith(`${OFFICIAL_WORKSPACE_PATH}/`)))) denied();
  const split = value => value.split('/');
  const base = cwd === undefined || cwd === OFFICIAL_WORKSPACE_PATH ? [] : split(cwd.slice(OFFICIAL_WORKSPACE_PATH.length + 1));
  if (base.length > MAX_DEPTH || !base.every(validName)) denied();
  const parts = path === OFFICIAL_WORKSPACE_PATH ? []
    : path.startsWith(`${OFFICIAL_WORKSPACE_PATH}/`) ? split(path.slice(OFFICIAL_WORKSPACE_PATH.length + 1))
      : path === '.' ? base : [...base, ...split(path)];
  if (parts.length > MAX_DEPTH || !parts.every(validName)
      || Buffer.byteLength(logicalPath(parts)) > MAX_PATH_BYTES) denied();
  return parts;
}
const logicalPath = parts => parts.length ? `${OFFICIAL_WORKSPACE_PATH}/${parts.join('/')}` : OFFICIAL_WORKSPACE_PATH;
const normalize = text => text.replaceAll('\r\n', '\n');
const bytes = value => Buffer.byteLength(value, 'utf8');

function checkText(text, cap) {
  if (typeof text !== 'string') notText();
  if (text.length > cap || bytes(text) > cap) tooLarge();
  if (!text.isWellFormed() || INVALID_TEXT.test(text)) notText();
}

// Reject case or Unicode spelling aliases instead of allowing distinct target keys
// for the same directory entry on APFS. This scan only verifies one known name.
function requireExactName(parent, name) {
  const dir = opendirSync(parent, { bufferSize: 16, encoding: 'buffer' });
  const encoded = Buffer.from(name, 'utf8');
  try {
    for (let i = 0; i < MAX_DIRECTORY_PROBES; i++) {
      const entry = dir.readSync();
      if (!entry) return denied();
      if (encoded.equals(entry.name)) return;
    }
    return tooLarge();
  } finally { dir.closeSync(); }
}

function literalEdit(original, edit, cap) {
  if (!edit || typeof edit.replaceAll !== 'boolean') denied();
  const old = normalize(edit.oldString);
  const replacement = normalize(edit.newString);
  const before = normalize(original);
  const first = old ? before.indexOf(old) : -1;
  if (first === -1) fail('FS_EDIT_NOT_FOUND', 'The literal search text was not found.');
  const start = first + old.length;
  if (!edit.replaceAll && before.indexOf(old, start) !== -1) {
    fail('FS_AMBIGUOUS_EDIT', 'The literal search text matched more than once.');
  }
  const pieces = before.split(old);
  // Bound replacement expansion before joining; replacement text is always literal.
  const matched = pieces.length - 1;
  if (bytes(before) - matched * bytes(old) + matched * bytes(replacement) > cap) tooLarge();
  const after = pieces.join(replacement);
  const sample = original.slice(0, 4096);
  const crlf = sample.split('\r\n').length - 1;
  const lf = sample.split('\n').length - 1;
  if (crlf > lf - crlf && bytes(after) + after.split('\n').length - 1 > cap) tooLarge();
  return crlf > lf - crlf ? after.replaceAll('\n', '\r\n') : after;
}

function previewOf(text) {
  let end = 0;
  let size = 0;
  for (const character of text) {
    size += bytes(JSON.stringify(character)) - 2;
    if (size > PREVIEW_BYTES) break;
    end += character.length;
  }
  return { preview: text.slice(0, end), previewTruncated: end < text.length };
}

// Cordis traces service receivers through proxies. Keep private state in the
// factory closure rather than in receiver-sensitive private class fields.
class IOSWorkspaceFileSystem extends FileSystem {
  constructor(ctx, api) {
    super(ctx);
    Object.assign(this, api);
  }
  // The virtual process path is for official tool output, never for subprocesses.
  fileUrl() { return denied(); }
  lstat = unsupported;
  readBytes = unsupported;
  readByteRange = unsupported;
  listDir = unsupported;
  watch = unsupported;
  patchText = unsupported;
  deleteFile = unsupported;
  moveFile = unsupported;
}

/**
 * Unmounted rc.3 model-side provider. Pass an isolated Cordis context and the
 * canonical, existing 0700 App-owned `Workspace` directly under private App state.
 * `containsSensitiveText` is synchronous and must cover App-channel secrets.
 * `approve(action, approvalSignal, callerSignal)` must authorize this exact
 * call in trusted App code; use callerSignal identity to correlate the actual
 * dispatch (after any signal fusion). Only literal `true` authorizes one change.
 * `lifetimeSignal` closes all operations. No other process/thread or importer
 * may mutate or relink this tree during provider IO: Node has no portable
 * directory-fd-relative open/rename. Each bounded IO phase is synchronous;
 * changes while external approval is pending are revalidated before staging.
 */
export function createOfficialWorkspaceFileSystem(ctx, {
  directory, containsSensitiveText, approve, lifetimeSignal,
} = {}) {
  if (!Context.is(ctx) || ctx[Context.isolate].fs === undefined || ctx[Context.isolate].fs === ctx.root[Context.isolate].fs
      || typeof directory !== 'string' || !isAbsolute(directory) || resolve(directory) !== directory
      || basename(directory) !== 'Workspace' || typeof process.getuid !== 'function'
      || !constants.O_NOFOLLOW || !constants.O_NONBLOCK || !constants.O_EXCL
      || typeof containsSensitiveText !== 'function' || typeof approve !== 'function'
      || !(lifetimeSignal instanceof AbortSignal)) unavailable();
  checkAbort(lifetimeSignal);
  const parentPath = dirname(directory);
  let root;
  let parent;
  try {
    const uid = BigInt(process.getuid());
    root = lstatSync(directory, LSTAT);
    parent = lstatSync(parentPath, LSTAT);
    if (!privateDir(root, uid) || !privateDir(parent, uid) || root.dev !== parent.dev
        || dirname(parentPath) === parentPath || realpathSync(directory) !== directory) unavailable();
  } catch { unavailable(); }
  const salt = randomBytes(32);
  const targets = new WeakMap();
  const token = value => createHash('sha256').update(salt).update(value).digest('hex');
  const version = info => token(`version:${info.dev}:${info.ino}:${info.birthtimeNs}:${info.mtimeNs}:${info.ctimeNs}:${info.size}`);
  const dirAllowed = info => info.isDirectory() && info.dev === root.dev && info.uid === root.uid && (info.mode & 0o022n) === 0n;
  const fileAllowed = info => info.isFile() && info.dev === root.dev && info.uid === root.uid && info.nlink === 1n;

  function check(signal) {
    checkAbort(lifetimeSignal);
    checkAbort(signal);
  }
  function publicText(value) {
    check(lifetimeSignal);
    try {
      if (value.includes(parentPath) || containsSensitiveText(value) !== false) denied();
    } catch { denied(); }
  }
  function checkedText(value, cap) {
    checkText(value, cap);
    publicText(value);
    publicText(normalize(value));
    publicText(JSON.stringify(value));
  }
  function locate(target) {
    const parts = targets.get(target);
    if (!parts) denied();
    return parts;
  }
  function inspect(parts) {
    const currentParent = lstatSync(parentPath, LSTAT);
    if (!sameEntry(parent, currentParent) || !privateDir(currentParent, root.uid)
        || realpathSync(parentPath) !== parentPath) unavailable();
    const currentRoot = lstatSync(directory, LSTAT);
    if (!sameEntry(root, currentRoot) || !privateDir(currentRoot, root.uid)) unavailable();
    const chain = [currentRoot];
    let path = directory;
    let info = currentRoot;
    for (let i = 0; i < parts.length; i++) {
      const name = parts[i];
      const next = join(path, name);
      info = lstatSync(next, LSTAT);
      const leaf = i === parts.length - 1;
      if (!info && !leaf) absent();
      if (info) {
        if (!dirAllowed(info) && !(leaf && fileAllowed(info))) denied();
        requireExactName(path, name);
        if (!leaf) chain.push(info);
      }
      path = next;
    }
    return { path, chain, info };
  }
  function requireSame(before, after) {
    if (before.chain.some((entry, i) => !sameEntry(entry, after.chain[i]))
        || (before.info ? !sameVersion(before.info, after.info) : Boolean(after.info))) changed();
  }
  function requireFile(info) {
    if (!info) absent();
    if (!fileAllowed(info)) fail('FS_NOT_REGULAR_FILE', 'The Workspace entry is not a regular file.');
  }
  function read(parts, snapshot, cap, signal) {
    requireFile(snapshot.info);
    if (snapshot.info.size > BigInt(cap)) tooLarge();
    const fd = openSync(snapshot.path, READ_FLAGS);
    try {
      const info = fstatSync(fd, STATS);
      if (!fileAllowed(info) || !sameVersion(snapshot.info, info)) changed();
      const buffer = Buffer.alloc(Number(info.size) + 1);
      let total = 0;
      while (total < buffer.length) {
        const count = readSync(fd, buffer, total, buffer.length - total, null);
        if (count === 0) break;
        total += count;
      }
      if (total !== Number(info.size) || !sameVersion(info, fstatSync(fd, STATS))) changed();
      requireSame(snapshot, inspect(parts));
      let text;
      try { text = decoder.decode(buffer.subarray(0, total)); } catch { notText(); }
      checkedText(text, cap);
      check(signal);
      return text;
    } finally { closeSync(fd); }
  }

  async function approval(action, callerSignal) {
    const signal = AbortSignal.any([callerSignal, lifetimeSignal, AbortSignal.timeout(APPROVAL_TIMEOUT_MS)]);
    let cancel;
    try {
      checkAbort(signal);
      const stopped = new Promise(resolve => {
        cancel = () => resolve(false);
        signal.addEventListener('abort', cancel, { once: true });
      });
      // A rejected native prompt must not surface its error or approval payload.
      const decision = Promise.resolve().then(() => {
        checkAbort(signal);
        return approve(action, signal, callerSignal);
      }).catch(() => false);
      const allowed = await Promise.race([decision, stopped]);
      checkAbort(signal);
      if (allowed !== true) fail('FS_PERMISSION_DENIED', 'The Workspace change was not approved.');
    } finally { if (cancel) signal.removeEventListener('abort', cancel); }
  }

  function publish(parts, snapshot, content, signal) {
    // A no-overwrite link for creation, a same-directory rename for replacement.
    // Both publish only after all bytes are written and flushed. Once committed,
    // do not report cancellation or a pre-commit error even if bookkeeping fails.
    const stage = join(dirname(snapshot.path), `.dsh-ios-${randomBytes(16).toString('hex')}`);
    let fd;
    let staged;
    let committed = false;
    try {
      check(signal);
      fd = openSync(stage, CREATE_FLAGS, 0o600);
      staged = fstatSync(fd, STATS);
      if (!fileAllowed(staged)) denied();
      const data = Buffer.from(content, 'utf8');
      for (let at = 0; at < data.length;) {
        const size = writeSync(fd, data, at, data.length - at, null);
        if (size <= 0) unavailable();
        at += size;
      }
      fsyncSync(fd);
      const written = fstatSync(fd, STATS);
      if (!fileAllowed(written) || !sameVersion(written, lstatSync(stage, LSTAT))) changed();
      requireSame(snapshot, inspect(parts));
      check(signal);
      if (snapshot.info) renameSync(stage, snapshot.path);
      else linkSync(stage, snapshot.path);
      committed = true;
    } finally {
      if (fd !== undefined) {
        try { closeSync(fd); } catch { /* Staged data was fsynced before publication. */ }
      }
      if (staged) {
        try {
          const parentInfo = lstatSync(dirname(snapshot.path), LSTAT);
          if (sameEntry(snapshot.chain.at(-1), parentInfo) && sameEntry(staged, lstatSync(stage, LSTAT))) unlinkSync(stage);
        } catch { /* A private stage is never model-addressable. */ }
      }
    }
    if (committed) {
      // Post-publication lstat is only bookkeeping. If another writer violated
      // the ownership contract, never bless its version as our observation.
      try {
        const info = lstatSync(snapshot.path, LSTAT);
        if (sameEntry(staged, info) && fileAllowed(info)) return version(info);
      } catch { /* An unmatchable version still reports the committed outcome. */ }
      return token(`published:${stage}`);
    }
  }

  async function mutate(tool, target, input, expected, signal, policy) {
    try {
      check(signal);
      if (policy !== undefined || !(signal instanceof AbortSignal)) denied();
      const parts = locate(target);
      if (!parts.length) denied();
      const path = logicalPath(parts);
      publicText(path);
      const cap = OFFICIAL_WORKSPACE_LIMITS.writeBytes;
      if (tool === 'edit') {
        checkedText(input?.oldString, cap);
        checkedText(input?.newString, cap);
      } else checkedText(input, cap);
      const snapshot = inspect(parts);
      const info = snapshot.info;
      if (tool === 'edit') {
        if (expected !== undefined && (typeof expected?.version !== 'string' || !info || version(info) !== expected.version)) changed();
        requireFile(info);
      } else if (expected !== undefined) {
        if (expected?.kind === 'createIfAbsent') {
          if (info) fail('FS_NOT_OBSERVED', 'The Workspace entry already exists. Read it before replacing it.');
        } else if (expected?.kind === 'replaceIfVersion') {
          if (!info || version(info) !== expected.version) changed();
        } else denied();
      }
      const original = info ? read(parts, snapshot, cap, signal) : null;
      const before = original === null ? null : normalize(original);
      const content = tool === 'edit' ? literalEdit(original, input, cap) : input;
      checkedText(content, cap);
      const after = normalize(content);
      const operation = info ? 'update' : 'create';
      const action = Object.freeze({ tool, path, operation, byteLength: bytes(content), ...previewOf(content) });
      publicText(JSON.stringify(action));
      await approval(action, signal);
      check(signal);
      // Recheck the exact original file/parent chain after the native wait.
      requireSame(snapshot, inspect(parts));
      const publishedVersion = publish(parts, snapshot, content, signal);
      return { ...(tool === 'write' ? { operation } : {}), version: publishedVersion, before, after };
    } catch (error) { return safeError(error); }
  }

  async function readText(target, signal) {
    try {
      check(signal);
      const parts = locate(target);
      publicText(logicalPath(parts));
      return read(parts, inspect(parts), OFFICIAL_WORKSPACE_LIMITS.readBytes, signal);
    } catch (error) { return safeError(error); }
  }
  return new IOSWorkspaceFileSystem(ctx, {
    // Deliberately inherit sandboxMode=undefined: rc.3 maps non-undefined to
    // an escalation protocol. This capability has no wider execution mode.
    async resolve(path, { cwd, signal } = {}) {
      try {
        check(signal);
        const parts = partsFor(path, cwd);
        const displayPath = logicalPath(parts);
        publicText(path);
        if (cwd !== undefined) publicText(cwd);
        publicText(displayPath);
        inspect(parts);
        const target = Object.freeze({ targetKey: token(`target:${displayPath}`), displayPath });
        targets.set(target, parts);
        return target;
      } catch (error) { return safeError(error); }
    },
    processPath(target) { check(); return logicalPath(locate(target)); },
    contains(parent, child) {
      check();
      const a = locate(parent);
      const b = locate(child);
      return a.length <= b.length && a.every((name, i) => b[i] === name);
    },
    async stat(target, signal) {
      try {
        check(signal);
        const { info } = inspect(locate(target));
        if (!info) return undefined;
        return info.isDirectory() ? { type: 'directory', version: version(info) }
          : { type: 'file', version: version(info), size: Number(info.size) };
      } catch (error) { return safeError(error); }
    },
    readText,
    async streamText(target, signal) {
      // Validate the whole bounded file, including the secret predicate, before
      // the first chunk becomes observable to the official read renderer.
      const text = await readText(target, signal);
      return (async function* () { check(signal); yield text; })();
    },
    writeText: (target, content, guard, signal, policy) => mutate('write', target, content, guard, signal, policy),
    editText: (target, edit, guard, signal, policy) => mutate('edit', target, edit, guard, signal, policy),
  });
}
