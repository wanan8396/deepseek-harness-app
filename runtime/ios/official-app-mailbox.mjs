import { Buffer } from 'node:buffer';
import { constants } from 'node:fs';
import { lstat, open, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { createOfficialHost } from './official-host.mjs';

const REQUEST = /^official-call-([0-9a-f]{32})\.json$/u;
const STREAM = /^s[0-9a-f]{32}$/u;
const BYTE_CAP = 256 * 1024;
const TIME_TO_LIVE = 45_000;
const gone = error => { if (error.code !== 'ENOENT') throw error; };
const remove = path => rm(path, { force: true });
const reply = (status, body) => ({ status, headers: [['content-type', 'application/json']], body: JSON.stringify(body) });
const privateDir = value => value.isDirectory() && value.uid === process.getuid() && (value.mode & 0o077) === 0;
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const noFollow = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK;

async function claim(path, limit) {
  const handle = await open(path, noFollow).catch(gone);
  if (!handle) return undefined;
  const raw = Buffer.alloc(limit + 1);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 || (stat.mode & 0o077) !== 0
        || stat.size > limit || Date.now() - stat.mtimeMs > TIME_TO_LIVE) throw new Error('IOS_OFFICIAL_FRAME_INVALID');
    const { bytesRead } = await handle.read(raw, 0, raw.length, 0);
    if (!bytesRead || bytesRead > limit) throw new Error('IOS_OFFICIAL_FRAME_INVALID');
    // The successful unlink is admission. An expired native publisher which
    // already withdrew the file must not leave a dispatchable credential.
    await rm(path);
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw.subarray(0, bytesRead)));
    if (!record(value)) throw new Error('IOS_OFFICIAL_FRAME_INVALID');
    return value;
  } catch (error) {
    await remove(path);
    throw error;
  } finally {
    raw.fill(0);
    await handle.close();
  }
}

async function publish(path, value) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    const content = JSON.stringify(value);
    if (Buffer.byteLength(content) > 6 * BYTE_CAP + 1024) throw new Error('IOS_OFFICIAL_REPLY_TOO_LARGE');
    await writeFile(temporary, content, { flag: 'wx', mode: 0o600 });
    await rename(temporary, path);
  } finally { await remove(temporary); }
}

function createGeneration(host) {
  const streams = new Map();
  const tasks = new Map();
  const lifetime = new AbortController();
  const abort = async id => {
    const stream = streams.get(id);
    if (!stream) return;
    streams.delete(id);
    stream.control.abort();
    const iterator = await stream.open;
    await stream.next?.catch(() => {});
    await iterator.return?.();
  };
  const signal = control => AbortSignal.any([lifetime.signal, control.signal]);

  async function streamCommand(payload) {
    const { id, type, endpoint, payload: args } = payload;
    if (typeof id !== 'string' || !STREAM.test(id)) return reply(400, { error: 'IOS_OFFICIAL_STREAM_ID' });
    if (type === 'open') {
      if (streams.has(id) || streams.size >= 12) return reply(409, { error: 'IOS_OFFICIAL_STREAM_LIMIT' });
      const control = new AbortController();
      const stream = { control, next: null, pulling: false };
      stream.open = Promise.resolve(host.openStream(endpoint, args, signal(control)))
        .then(source => source[Symbol.asyncIterator]());
      streams.set(id, stream);
      try { await stream.open; }
      catch (error) { streams.delete(id); throw error; }
      return reply(200, { opened: !control.signal.aborted });
    }
    if (type === 'close') {
      await abort(id);
      return reply(200, { closed: true });
    }
    const stream = streams.get(id);
    if (type !== 'next' || !stream || stream.pulling) return reply(409, { error: 'IOS_OFFICIAL_STREAM_PULL' });
    stream.pulling = true;
    const clock = new AbortController();
    const idle = {};
    try {
      const iterator = await stream.open;
      stream.next ??= Promise.resolve().then(() => iterator.next());
      const item = await Promise.race([stream.next, sleep(2000, idle, { signal: clock.signal })]);
      if (item === idle) return reply(200, { idle: true });
      stream.next = null;
      if (item.done) await abort(id);
      return reply(200, item);
    } catch (error) {
      if (stream.control.signal.aborted || lifetime.signal.aborted) return reply(200, { done: true });
      await abort(id).catch(() => {});
      throw error;
    } finally {
      clock.abort();
      stream.pulling = false;
    }
  }

  async function dispatch(frame) {
    lifetime.signal.throwIfAborted();
    if (frame.method !== 'POST' || typeof frame.path !== 'string' || frame.path.length > 256
        || !/^\/api\/[A-Za-z0-9/$._-]+$/u.test(frame.path) || typeof frame.body !== 'string'
        || Buffer.byteLength(frame.body) > BYTE_CAP || !Array.isArray(frame.headers)
        || !frame.headers.some(pair => Array.isArray(pair) && pair[0]?.toLowerCase?.() === 'content-type'
          && typeof pair[1] === 'string' && pair[1].split(';')[0].trim().toLowerCase() === 'application/json')) {
      return reply(400, { error: 'IOS_OFFICIAL_FRAME_INVALID' });
    }
    if (frame.path === '/api/ios-app/stream') return streamCommand(JSON.parse(frame.body));
    const response = await host.fetch(new Request(`dsh-app://bundle${frame.path}`, {
      method: 'POST', body: frame.body, headers: { 'content-type': 'application/json' },
      signal: AbortSignal.any([lifetime.signal, AbortSignal.timeout(25_000)]),
    }));
    return { status: response.status, headers: [...response.headers], body: await response.text() };
  }

  return {
    schedule(directory, names) {
      for (const name of names) {
        const match = REQUEST.exec(name);
        if (!match || tasks.has(match[1]) || tasks.size >= 16) continue;
        const id = match[1];
        const promise = (async () => {
          let response;
          try {
            const value = await claim(join(directory, name), 6 * BYTE_CAP + 1024);
            if (!value) return;
            response = await dispatch(value);
          } catch { response = reply(500, { error: 'IOS_OFFICIAL_REQUEST_FAILED' }); }
          if (Buffer.byteLength(response.body) > BYTE_CAP) response = reply(413, { error: 'IOS_OFFICIAL_RESPONSE_LIMIT' });
          await publish(join(directory, `official-reply-${id}.json`), response);
        })().catch(() => {}).finally(() => tasks.delete(id));
        tasks.set(id, promise);
      }
    },
    async close() {
      lifetime.abort();
      await Promise.allSettled([...streams.keys()].map(abort));
      await Promise.allSettled(tasks.values());
      await host.dispose();
    },
  };
}

/** Native Swift owns the live process folder; no page call can configure the
 * channel, read exports from another generation, or open a listener. */
export async function startOfficialAppMailbox(reportPath, seed, lifetimeSignal) {
  if (!isAbsolute(reportPath) || !isAbsolute(seed)) throw new TypeError('Expected absolute owned paths');
  const directory = `${reportPath}.official`;
  const stateDirectory = join(dirname(reportPath), 'OfficialAppState');
  const start = join(directory, 'official-start.json');
  const ready = join(directory, 'official-ready.json');
  const stop = join(directory, 'official-stop');
  const stopped = join(directory, 'official-stopped');
  let generation;
  try {
    while (!lifetimeSignal?.aborted) {
    const entry = await lstat(directory).catch(gone);
    if (!entry) {
      if (generation) { try { await generation.close(); } finally { generation = undefined; } }
      await sleep(100);
      continue;
    }
    if (!privateDir(entry) || await realpath(directory) !== join(await realpath(dirname(directory)), basename(directory))) {
      throw new Error('IOS_OFFICIAL_MAILBOX_DIR_INVALID');
    }
    if ((await readFile(stop, 'utf8').catch(gone)) === '1') {
      await remove(start);
      try { await generation?.close(); }
      finally {
        generation = undefined;
        await remove(stop);
        await publish(stopped, 1);
      }
    } else if (!generation) {
      try {
        const command = await claim(start, 16 * 1024);
        if (command) {
          let apiKey = command.apiKey;
          command.apiKey = undefined;
          try {
            const host = await createOfficialHost({ seed, stateDirectory, appChannel: { apiKey, channel: command.channel } });
            generation = createGeneration(host);
            await publish(ready, { ok: true });
          } finally { apiKey = undefined; }
        }
      } catch (error) {
        await generation?.close();
        generation = undefined;
        const code = ['IOS_CHAT_KEY_INVALID', 'IOS_CHAT_CHANNEL_INVALID', 'IOS_OFFICIAL_WORKSPACE_UNAVAILABLE'].includes(error.code)
          ? error.code : 'IOS_OFFICIAL_START_FAILED';
        await publish(ready, { ok: false, code });
      }
    } else {
      generation.schedule(directory, await readdir(directory));
    }
    await sleep(generation ? 25 : 100);
    }
  } finally { await generation?.close(); }
}
