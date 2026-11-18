// RunnerTests only: a single bounded request/reply slot, never exposed by the App.
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
      if (wire.stop === true) return;
      let reply;
      try {
        if (typeof wire.body !== 'string') throw new Error('IOS_HOST_CI_INVALID_BODY');
        const request = JSON.parse(wire.body);
        if (wire.path === '/api/session/create' && request.payload?.args?.request?.cwd === undefined) {
          request.payload.args.request.cwd = workspace;
        }
        if (wire.path !== '/api/session/list' && !(wire.path === '/api/session/create'
            && request.payload?.args?.request?.cwd === workspace)) throw new Error('IOS_HOST_CI_INVALID_ROUTE');
        const response = await host.fetch(new Request(`dsh-app://bundle${wire.path}`, {
          method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(request),
        }));
        reply = { status: response.status, body: await response.text() };
      } catch {
        reply = { status: 500, body: 'IOS_HOST_CI_RPC_FAILED' };
      }
      const temp = join(directory, `official-rpc-${randomUUID()}.tmp`);
      await writeFile(temp, JSON.stringify(reply), { flag: 'wx', mode: 0o600 });
      await rename(temp, responsePath);
    }
  } finally { await host.dispose(); }
}
