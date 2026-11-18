// RunnerTests-only command slot; this carrier is not part of Runner.app.
import { randomUUID } from 'node:crypto';
import { lstat, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

export async function serveOfficialHostCi(seed, reportPath) {
  const directory = dirname(reportPath);
  const workspace = join(directory, 'OfficialHostCI');
  const requestPath = join(directory, 'official-rpc-request.json');
  const responsePath = join(directory, 'official-rpc-response.json');
  const { createOfficialHost } = await import(pathToFileURL(join(seed, 'official-host.mjs')).href);
  const host = await createOfficialHost({ seed, stateDirectory: workspace });
  const streams = new Map();
  let cleanStop = false;
  const close = async (id) => {
    const stream = streams.get(id);
    if (!stream) return;
    streams.delete(id);
    stream.controller.abort();
    await stream.iterator.return?.();
  };
  async function dispatch(wire) {
    if (typeof wire.body !== 'string') throw new Error('IOS_HOST_CI_INVALID_BODY');
    const request = JSON.parse(wire.body);
    if (wire.path === '/api/ios-ci/stream') {
      const { type, id } = request;
      if (typeof id !== 'string' || !/^s[1-9][0-9]{0,5}$/.test(id)) throw new Error('IOS_HOST_CI_INVALID_STREAM');
      if (type === 'open') {
        if (request.endpoint !== 'session/follow' || streams.has(id) || streams.size >= 4) {
          throw new Error('IOS_HOST_CI_INVALID_STREAM');
        }
        const controller = new AbortController();
        const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(15_000)]);
        const source = await host.openStream(request.endpoint, request.payload, signal);
        streams.set(id, { controller, iterator: source[Symbol.asyncIterator]() });
        return { status: 200, body: JSON.stringify({ opened: true }) };
      }
      if (type === 'close') {
        await close(id);
        return { status: 200, body: JSON.stringify({ closed: true }) };
      }
      if (type === 'next' && streams.has(id)) {
        const item = await streams.get(id).iterator.next();
        if (item.done) await close(id);
        return { status: 200, body: JSON.stringify(item) };
      }
      throw new Error('IOS_HOST_CI_INVALID_STREAM');
    }
    if (wire.path === '/api/session/create' && request.payload?.args?.request?.cwd === undefined) {
      request.payload.args.request.cwd = workspace;
    }
    if (!['/api/session/list', '/api/session/rename'].includes(wire.path) && !(wire.path === '/api/session/create'
        && request.payload?.args?.request?.cwd === workspace)) throw new Error('IOS_HOST_CI_INVALID_ROUTE');
    const response = await host.fetch(new Request(`dsh-app://bundle${wire.path}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(request),
    }));
    return { status: response.status, body: await response.text() };
  }
  try {
    const deadline = Date.now() + 90_000;
    while (Date.now() < deadline) {
      const info = await lstat(requestPath).catch(error => {
        if (error.code !== 'ENOENT') throw error;
      });
      if (!info) { await sleep(25); continue; }
      if (!info.isFile() || info.size > 8192) throw new Error('IOS_HOST_CI_INVALID_REQUEST');
      const wire = JSON.parse(await readFile(requestPath, 'utf8'));
      await rm(requestPath);
      if (wire.stop === true) { cleanStop = true; break; }
      let reply;
      try { reply = await dispatch(wire); }
      catch (error) {
        console.error('IOS_HOST_CI_RPC_FAILED', error);
        reply = { status: 500, body: 'IOS_HOST_CI_RPC_FAILED' };
      }
      const temp = join(directory, `official-rpc-${randomUUID()}.tmp`);
      await writeFile(temp, JSON.stringify(reply), { flag: 'wx', mode: 0o600 });
      await rename(temp, responsePath);
    }
  } finally {
    await Promise.allSettled([...streams.keys()].map(close));
    await host.dispose();
  }
  if (cleanStop) await writeFile(join(directory, 'official-host-ci-stopped'), '1', { flag: 'wx', mode: 0o600 });
}
