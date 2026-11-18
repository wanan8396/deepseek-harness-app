import { constants } from 'node:fs';
import { lstat, open, readdir, realpath, unlink, writeFile, link } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createChatEngine } from './chat-engine.mjs';

const ID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const REQUEST = new RegExp(`^request-(${ID})\\.json$`);
const RESPONSE = new RegExp(`^response-(${ID})\\.json$`);
const MAX_REQUEST = 16 * 1024;
const MAX_RESPONSE = 256 * 1024;
const RESPONSE_TTL = 2 * 60_000;
const REQUEST_TTL = 30_000;
const METHODS = new Set(['start', 'snapshot', 'send', 'cancel', 'stop']);
const CHAT_ERRORS = new Set([
  'IOS_CHAT_BAD_REQUEST', 'IOS_CHAT_REQUEST_EXPIRED', 'IOS_CHAT_NOT_STARTED', 'IOS_CHAT_BUSY',
  'IOS_CHAT_START_FAILED', 'IOS_CHAT_SEND_FAILED', 'IOS_CHAT_CANCEL_FAILED', 'IOS_CHAT_STOP_FAILED',
  'IOS_CHAT_STORAGE_FAILED', 'IOS_CHAT_MODEL_FAILED', 'IOS_CHAT_RESPONSE_LIMIT', 'IOS_CHAT_UNAVAILABLE',
  'IOS_CHAT_INPUT_INVALID', 'IOS_CHAT_AUTH_FAILED', 'IOS_CHAT_RATE_LIMITED', 'IOS_CHAT_TIMEOUT',
  'IOS_CHAT_NETWORK_FAILED', 'IOS_CHAT_KEY_INVALID', 'IOS_CHAT_BOOT_FAILED', 'IOS_CHAT_STOPPED',
]);
const STOPPED = Object.freeze({ state: 'stopped', messages: [], draft: '', errorCode: null });
const missing = (err) => err?.code === 'ENOENT';
const drop = async (file) => { try { await unlink(file); } catch (err) { if (!missing(err)) throw err; } };
const publicCode = (error, fallback) => CHAT_ERRORS.has(error?.code) ? error.code : fallback;
const fail = (code) => { throw Object.assign(new Error(code), { code }); };
const isRecord = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const exactKeys = (value, keys) => Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));

async function consume(file, id) {
  let handle;
  try {
    handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const stat = await handle.stat();
    if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o077) !== 0 || stat.size > MAX_REQUEST) fail('IOS_CHAT_BAD_REQUEST');
    if (Date.now() - stat.mtimeMs > REQUEST_TTL) fail('IOS_CHAT_REQUEST_EXPIRED');
    // Read at most one byte beyond the cap even if the file changes after stat.
    const raw = Buffer.allocUnsafe(MAX_REQUEST + 1);
    const { bytesRead } = await handle.read(raw, 0, raw.length, 0);
    if (bytesRead === 0 || bytesRead > MAX_REQUEST) fail('IOS_CHAT_BAD_REQUEST');
    let value;
    try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw.subarray(0, bytesRead))); }
    catch { fail('IOS_CHAT_BAD_REQUEST'); }
    finally { raw.fill(0); }
    if (!isRecord(value) || !exactKeys(value, ['id', 'method', 'params']) || value.id !== id
        || !METHODS.has(value.method) || !isRecord(value.params)) fail('IOS_CHAT_BAD_REQUEST');
    const { method, params } = value;
    if (method === 'start') {
      if (!exactKeys(params, ['apiKey']) || typeof params.apiKey !== 'string'
          || !/^[\x21-\x7e]{1,1024}$/.test(params.apiKey)) fail('IOS_CHAT_BAD_REQUEST');
    } else if (method === 'send') {
      if (!exactKeys(params, ['text']) || typeof params.text !== 'string' || !params.text.isWellFormed()
          || !params.text.trim() || Buffer.byteLength(params.text) > 8192) fail('IOS_CHAT_BAD_REQUEST');
    } else if (!exactKeys(params, [])) fail('IOS_CHAT_BAD_REQUEST');
    // Successful unlink claims the request. If Swift times out and removes it
    // first, ENOENT prevents dispatch, even though the descriptor was opened.
    await unlink(file);
    return value;
  } finally {
    try { await drop(file); } finally { await handle?.close(); }
  }
}

async function publish(directory, id, value) {
  let body = JSON.stringify(value);
  if (Buffer.byteLength(body) > MAX_RESPONSE) body = JSON.stringify({ id, errorCode: 'IOS_CHAT_RESPONSE_LIMIT' });
  const temporary = join(directory, `.response-${randomUUID()}.tmp`);
  try {
    await writeFile(temporary, body, { flag: 'wx', mode: 0o600 });
    // Atomic no-replace publication; never replace a response with the same id.
    await link(temporary, join(directory, `response-${id}.json`));
  } finally { await drop(temporary); }
}

/** Swift owns the process UUID request folder; JS owns the DSH context and history.
 * Both production and tests dispatch into the same engine factory. */
export function startChatMailbox(reportPath, { pollMs = 80 } = {}) {
  if (!isAbsolute(reportPath)) throw new TypeError('Expected absolute report path');
  const directory = `${reportPath}.chat`;
  const dataDir = join(dirname(reportPath), 'ChatData');
  let engine;
  let active = true;
  let timer;
  let scan;
  let stopPromise;
  let nextSweep = 0;
  const seen = new Map();

  async function dispatch(value) {
    switch (value.method) {
      case 'start': {
        if (engine) return engine.snapshot();
        const apiKey = value.params.apiKey;
        value.params.apiKey = '';
        engine = await createChatEngine({ directory: dataDir, apiKey });
        return engine.snapshot();
      }
      case 'snapshot': return engine ? engine.snapshot() : STOPPED;
      case 'send':
        if (!engine) fail('IOS_CHAT_NOT_STARTED');
        return engine.send(value.params);
      case 'cancel': return engine ? engine.cancel() : STOPPED;
      case 'stop': {
        if (!engine) return STOPPED;
        const current = engine;
        try { await current.stop(); }
        finally { engine = undefined; }
        return STOPPED;
      }
    }
  }

  async function tick() {
    let entries;
    try {
      const stat = await lstat(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0) return;
      // Parents like iOS /var alias to /private/var; only the mailbox leaf must be real.
        if (await realpath(directory) !== join(await realpath(dirname(directory)), basename(directory))) return;
      entries = await readdir(directory);
    } catch { return; }
    const now = Date.now();
    if (now >= nextSweep) {
      nextSweep = now + 10_000;
      for (const [id, time] of seen) if (now - time > RESPONSE_TTL) seen.delete(id);
      for (const name of entries) {
        if (!RESPONSE.test(name) && !/^\.response-[0-9a-f-]+\.tmp$/.test(name)) continue;
        try {
          const file = join(directory, name);
          if (now - (await lstat(file)).mtimeMs > RESPONSE_TTL) await drop(file);
        } catch { /* expiry is best-effort, never a request result */ }
      }
    }
    for (const name of entries.filter((file) => REQUEST.test(file)).slice(0, 8)) {
      if (!active) break;
      const [, id] = REQUEST.exec(name);
      const file = join(directory, name);
      let result;
      let method;
      try {
        if (seen.has(id)) { await drop(file); continue; }
        const value = await consume(file, id);
        seen.set(id, Date.now());
        method = value.method;
        result = { id, result: await dispatch(value) };
      } catch (error) {
        if (missing(error)) continue;
        result = { id, errorCode: publicCode(error, ({
          start: 'IOS_CHAT_START_FAILED', send: 'IOS_CHAT_SEND_FAILED', cancel: 'IOS_CHAT_CANCEL_FAILED',
          stop: 'IOS_CHAT_STOP_FAILED', snapshot: 'IOS_CHAT_UNAVAILABLE',
        })[method] ?? 'IOS_CHAT_BAD_REQUEST') };
      }
      try { await publish(directory, id, result); } catch { /* request may have timed out */ }
    }
  }

  function schedule() {
    if (active) timer = setTimeout(() => {
      scan = tick().catch(() => {}).finally(schedule);
    }, pollMs);
  }
  schedule();
  return () => stopPromise ??= (async () => {
    active = false;
    clearTimeout(timer);
    await scan;
    if (engine) await engine.stop();
    engine = undefined;
  })();
}
