import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import {
  chmod, link, lstat, mkdir, mkdtemp, readdir, readFile, realpath, rename, rm, symlink, writeFile,
} from 'node:fs/promises';
import { Server, Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Context } from '@deepseek-ai/cordis';
import { FileSystem } from '@deepseek-ai/dsh-fs';
import { createScope } from '@deepseek-ai/dsh-scope';
import { SystemPrompt } from '@deepseek-ai/dsh-system-prompt';
import { apply as applyOfficialTools } from '@deepseek-ai/dsh-tool-fs';
import { ToolsService } from '@deepseek-ai/dsh-tools';
import { ToolExecutionPipeline } from '@deepseek-ai/dsh-tools/pipeline';
import { createOfficialWorkspaceFileSystem, OFFICIAL_WORKSPACE_LIMITS, OFFICIAL_WORKSPACE_PATH } from './official-workspace-fs.mjs';

// CI-only: stage both .mjs files beside the full rc.3 `npm ci` seed, then run
// this file with Node 24.22.1 on a POSIX filesystem. No AgentLoop, production
// Host, approval UI, npm action, or network is needed by this fixture.
const temp = await mkdtemp(join(await realpath(tmpdir()), 'dsh-ios-official-fs-'));
const workspace = join(temp, 'Workspace');
const outside = join(temp, 'outside.txt');
const secret = 'fixture-app-channel-secret';
const life = new AbortController();
const noAbort = new AbortController().signal;
const ctx = new Context();
const scopeKey = {};
const asks = [];
const observers = [];
const activeCalls = new Set();
const network = [];
const nativeFetch = globalThis.fetch;
const nativeListen = Server.prototype.listen;
const nativeConnect = Socket.prototype.connect;
let scope;
let fs;
let pipeline;
let approvalMode;
let callNumber = 0;
const disk = name => readFile(join(workspace, name), 'utf8');
const missing = name => assert.rejects(lstat(join(workspace, name)), { code: 'ENOENT' });
const cleanStages = async (path = workspace) => assert.ok((await readdir(path)).every(name => !name.startsWith('.dsh-ios-')));
const denied = { code: 'FS_PERMISSION_DENIED' };
const aborted = { code: 'FS_ABORTED' };
const stale = { code: 'FS_STALE_VERSION' };
const tooLarge = { code: 'FS_TOO_LARGE' };
const forbidden = kind => () => { network.push(kind); throw new Error('unexpected network attempt'); };
const noLeaks = value => {
  const wire = JSON.stringify(value);
  assert.ok(!wire.includes(secret));
  assert.ok(!wire.includes(temp));
};

async function call(name, args, signal = noAbort) {
  const prepared = await pipeline.prepare({ name, arguments: args, callId: `fs-fixture-${++callNumber}`, signal, agent: scopeKey });
  return pipeline.complete(prepared.exec, prepared.kind === 'dispatch' ? await pipeline.dispatch(prepared.exec) : prepared);
}
async function ok(result) {
  const actual = await result;
  noLeaks(actual);
  assert.equal(actual.isError, false, JSON.stringify(actual));
  return actual;
}
async function error(result, code) {
  const actual = await result;
  noLeaks(actual);
  assert.equal(actual.isError, true);
  assert.equal(actual.error.info?.code, code, JSON.stringify(actual));
}

try {
  await chmod(temp, 0o700);
  await mkdir(workspace, { mode: 0o700 });
  await mkdir(join(workspace, 'src'), { mode: 0o700 });
  await writeFile(outside, 'outside content');
  await writeFile(join(workspace, 'protected.txt'), secret);
  await writeFile(join(workspace, 'invalid.txt'), Buffer.from([0xff]));
  await writeFile(join(workspace, 'nul.txt'), 'plain\0text');
  await writeFile(join(workspace, 'large.txt'), 'x'.repeat(OFFICIAL_WORKSPACE_LIMITS.readBytes + 1));
  await writeFile(join(workspace, 'read-cap.txt'), 'x'.repeat(OFFICIAL_WORKSPACE_LIMITS.readBytes));
  await writeFile(join(workspace, 'src', 'hello.txt'), 'hello 雪🧪\r\nrepeat\r\nrepeat\r\n');
  await writeFile(join(workspace, 'edit-expand.txt'), 'x'.repeat(OFFICIAL_WORKSPACE_LIMITS.writeBytes));
  await writeFile(join(workspace, 'secret-join.txt'), 'fixture-app-DELETEchannel-secret');
  await symlink(outside, join(workspace, 'file-link.txt'));
  await symlink(temp, join(workspace, 'dir-link'), 'dir');
  await link(outside, join(workspace, 'hard-link.txt'));

  globalThis.fetch = forbidden('fetch');
  Server.prototype.listen = forbidden('listen');
  Socket.prototype.connect = forbidden('connect');
  new SystemPrompt(ctx, { includeHarnessIdentity: false, includeRuntimeContext: false });
  new ToolsService(ctx);
  scope = createScope(ctx, scopeKey);
  const isolated = scope.ctx.isolate('fs');
  const options = {
    directory: workspace,
    lifetimeSignal: life.signal,
    containsSensitiveText: text => text.includes(secret),
    async approve(action, signal, callerSignal) {
      // Only an exact dispatched call gets access to the simulated user grant.
      const exec = [...activeCalls].find(call => call.name === action.tool && call.signal === callerSignal);
      if (!exec || signal.aborted) return false;
      asks.push(action);
      noLeaks(action);
      assert.ok(Object.isFrozen(action));
      await cleanStages();
      return approvalMode(action, signal);
    },
  };
  assert.throws(() => createOfficialWorkspaceFileSystem(ctx, options), { code: 'FS_IO_ERROR' });
  assert.throws(() => createOfficialWorkspaceFileSystem(isolated, { ...options, directory: temp }), { code: 'FS_IO_ERROR' });
  await chmod(workspace, 0o755);
  assert.throws(() => createOfficialWorkspaceFileSystem(isolated, options), { code: 'FS_IO_ERROR' });
  await chmod(workspace, 0o700);
  fs = createOfficialWorkspaceFileSystem(isolated, options);
  assert.ok(isolated.fs instanceof FileSystem);
  assert.equal(ctx.get('fs'), undefined);
  assert.equal(isolated.fs.sandboxMode, undefined);
  isolated.provide('workingDirectory', { ensure: async () => OFFICIAL_WORKSPACE_PATH });
  applyOfficialTools(isolated, { read: true, write: true, edit: true, readImage: false, applyPatch: false,
    readLimit: 20, readMaxLineLength: 200, readMaxBytes: 1024, readStreamMinSize: 1 });
  assert.deepEqual(ctx.tools.definitions(scopeKey).map(item => item.name).sort(), ['edit', 'read', 'write']);
  assert.deepEqual(ctx.tools.definitions(), []);
  assert.equal(ctx.tools.get('write', scopeKey).parameters.properties.sandbox_permissions, undefined);
  ctx.on('tools/execute', async (exec, next) => {
    // Exercise the rc.3 pipeline's caller + wrapper signal fusion. The callback
    // must compare the live execution signal, not the wrapper's initial signal.
    const before = exec.signal;
    exec.signal = new AbortController().signal;
    activeCalls.add(exec);
    try { return await next(); }
    finally { activeCalls.delete(exec); exec.signal = before; }
  });
  // Record independent observations keyed by the logical path identity and
  // supply exact rc.3 guards through the consumer's mutation-waterfall slots.
  const seen = new Map();
  ctx.on('fs/observed', (target, observation, exec) => {
    seen.set(target.targetKey, observation);
    observers.push({ target, observation, name: exec.name });
  });
  ctx.on('fs/write-intent', (target, _actor, next) => {
    const observation = seen.get(target.targetKey);
    return observation?.kind === 'present' ? { kind: 'replaceIfVersion', version: observation.version }
      : observation?.kind === 'absent' ? { kind: 'createIfAbsent' } : next();
  });
  ctx.on('fs/edit-intent', (target, _actor, next) => {
    const observation = seen.get(target.targetKey);
    return observation?.kind === 'present' ? { version: observation.version } : next();
  });
  pipeline = new ToolExecutionPipeline(ctx);

  const root = await fs.resolve(OFFICIAL_WORKSPACE_PATH);
  const hello = await fs.resolve('hello.txt', { cwd: '/workspace/src' });
  const absolute = await fs.resolve('/workspace/src/hello.txt');
  assert.equal(hello.targetKey, absolute.targetKey);
  assert.equal(fs.processPath(hello), '/workspace/src/hello.txt');
  assert.ok(fs.contains(root, hello));
  assert.equal(fs.processPathFromHostPath(workspace), undefined);
  assert.throws(() => fs.fileUrl(hello), denied);
  assert.throws(() => fs.processPath({ ...hello }), denied);
  await assert.rejects(fs.readText({ ...hello }), denied);
  for (const path of [workspace, '/workspace-other/x', '../outside.txt', '/workspace/src/../hello.txt', 'src//hello.txt',
    'file:///workspace/src/hello.txt', 'C:\\bad.txt', 'x/../../outside.txt', '.env', 'nul\0.txt', 'file-link.txt',
    'dir-link/outside.txt', 'hard-link.txt', '%2e%2e/outside.txt', 'a/b/c/d/e/f/g/h/i']) {
    await assert.rejects(fs.resolve(path), denied);
  }
  await assert.rejects(fs.resolve('src/hello.txt', { cwd: workspace }), denied);
  if (process.platform === 'darwin') {
    const aliased = await lstat(join(workspace, 'src', 'HELLO.TXT')).then(() => true, () => false);
    if (aliased) await assert.rejects(fs.resolve('/workspace/src/HELLO.TXT'), denied);
  }
  for (const fn of ['lstat', 'readBytes', 'readByteRange', 'listDir', 'watch', 'patchText', 'deleteFile', 'moveFile']) {
    await assert.rejects(fs[fn](hello, noAbort, 4096), denied);
  }
  const read = await ok(call('read', { file_path: 'src/hello.txt', offset: 2, limit: 1 }));
  assert.equal(read.value.path, '/workspace/src/hello.txt');
  assert.deepEqual(read.value.lines, [{ number: 2, text: 'repeat' }]);
  assert.match(read.content[0].text, /2: repeat/);
  assert.equal(observers.at(-1).observation.kind, 'present');
  assert.equal((await fs.readText(await fs.resolve('read-cap.txt'))).length, OFFICIAL_WORKSPACE_LIMITS.readBytes);
  for (const [path, code] of [['protected.txt', denied.code], ['invalid.txt', 'FS_NOT_TEXT'], ['nul.txt', 'FS_NOT_TEXT'],
    ['large.txt', tooLarge.code], [secret, denied.code], ['missing-subdir/x.txt', 'FS_NOT_FOUND']]) {
    await error(call('read', { file_path: path }), code);
  }

  approvalMode = async action => {
    await missing('fresh.txt');
    assert.equal(action.path, '/workspace/fresh.txt');
    assert.equal(action.operation, 'create');
    return true;
  };
  const fresh = await fs.resolve('fresh.txt');
  await assert.rejects(fs.writeText(fresh, 'unbound', undefined, noAbort), denied);
  await error(call('read', { file_path: 'fresh.txt' }), 'FS_NOT_FOUND');
  assert.equal(observers.at(-1).observation.kind, 'absent');
  const created = await ok(call('write', { file_path: 'fresh.txt', content: 'approved\n' }));
  assert.equal(created.value.operation, 'create');
  assert.equal(created.value.before, null);
  assert.equal(await disk('fresh.txt'), 'approved\n');
  const beforeEdit = await lstat(join(workspace, 'fresh.txt'));
  approvalMode = async action => {
    assert.equal(action.operation, 'update');
    assert.equal(await disk('fresh.txt'), 'approved\n');
    return true;
  };
  const edited = await ok(call('edit', { file_path: 'fresh.txt', old_string: 'approved', new_string: '$& fixed' }));
  assert.equal(edited.value.before, 'approved\n');
  assert.equal(edited.value.after, '$& fixed\n');
  assert.equal(await disk('fresh.txt'), '$& fixed\n');
  assert.notEqual((await lstat(join(workspace, 'fresh.txt'))).ino, beforeEdit.ino, 'published atomically, not in-place');
  assert.match(edited.meta.diffs[0].newText, /\$& fixed/);
  approvalMode = async () => true;
  await error(call('edit', { file_path: 'src/hello.txt', old_string: 'repeat', new_string: 'new' }), 'FS_AMBIGUOUS_EDIT');
  await error(call('edit', { file_path: 'src/hello.txt', old_string: 'unknown', new_string: 'new' }), 'FS_EDIT_NOT_FOUND');
  await ok(call('edit', { file_path: 'src/hello.txt', old_string: 'repeat', new_string: 'new', replace_all: true }));
  assert.equal(await disk('src/hello.txt'), 'hello 雪🧪\r\nnew\r\nnew\r\n');

  const approvalCount = asks.length;
  await assert.rejects(fs.writeText(fresh, 'attempt', { kind: 'createIfAbsent' }, noAbort), { code: 'FS_NOT_OBSERVED' });
  await assert.rejects(fs.editText(fresh, { oldString: 'x', newString: 'y', replaceAll: false }, { version: 'bogus' }, noAbort), stale);
  await assert.rejects(fs.writeText(fresh, 'attempt', undefined, noAbort, { mode: 'danger-full-access' }), denied);
  await error(call('write', { file_path: 'fresh.txt', content: '雪'.repeat(1400) }), tooLarge.code);
  await error(call('write', { file_path: 'fresh.txt', content: secret }), denied.code);
  await error(call('write', { file_path: 'protected.txt', content: 'public' }), denied.code);
  await error(call('edit', { file_path: 'secret-join.txt', old_string: 'DELETE', new_string: '' }), denied.code);
  await error(call('edit', { file_path: 'edit-expand.txt', old_string: 'x', new_string: 'yy', replace_all: true }), tooLarge.code);
  assert.equal(asks.length, approvalCount);
  assert.equal(await disk('protected.txt'), secret);
  assert.equal(await disk('secret-join.txt'), 'fixture-app-DELETEchannel-secret');
  assert.equal(await disk('fresh.txt'), '$& fixed\n');

  // Pre-abort, denied approval, and post-approval cancellation never stage.
  const cancelled = AbortSignal.abort(new Error(secret));
  await assert.rejects(fs.writeText(fresh, 'attempt', undefined, cancelled), aborted);
  assert.equal(asks.length, approvalCount);
  approvalMode = async () => 'allowed-once'; // truthy is not a provider grant
  await error(call('write', { file_path: 'denied.txt', content: 'this must not publish' }), denied.code);
  await missing('denied.txt');
  const afterApproval = new AbortController();
  approvalMode = async () => { afterApproval.abort(new Error(secret)); return true; };
  await error(call('write', { file_path: 'fresh.txt', content: 'must not replace' }, afterApproval.signal), aborted.code);
  assert.equal(await disk('fresh.txt'), '$& fixed\n');
  const pending = new AbortController();
  let sent;
  const requested = new Promise(resolve => { sent = resolve; });
  let lateGrant;
  approvalMode = () => new Promise(resolve => { lateGrant = resolve; sent(); });
  const waiting = call('write', { file_path: 'pending.txt', content: 'must not appear' }, pending.signal);
  await Promise.race([requested, waiting.then(result => assert.fail(JSON.stringify(result)))]);
  await missing('pending.txt');
  pending.abort(new Error(secret));
  await error(waiting, aborted.code);
  lateGrant(true);
  await missing('pending.txt');
  await cleanStages();

  approvalMode = async () => { await writeFile(join(workspace, 'fresh.txt'), 'external replacement'); return true; };
  await error(call('write', { file_path: 'fresh.txt', content: 'stale update' }), stale.code);
  assert.equal(await disk('fresh.txt'), 'external replacement');
  approvalMode = async () => { await writeFile(join(workspace, 'concurrent.txt'), 'external create'); return true; };
  await error(call('write', { file_path: 'concurrent.txt', content: 'stale create' }), stale.code);
  assert.equal(await disk('concurrent.txt'), 'external create');
  approvalMode = async () => {
    await rename(join(workspace, 'src'), join(workspace, 'old-src'));
    await symlink(temp, join(workspace, 'src'), 'dir');
    return true;
  };
  await error(call('write', { file_path: 'src/outside.txt', content: 'no escape' }), denied.code);
  assert.equal(await readFile(outside, 'utf8'), 'outside content');
  await cleanStages();
  await cleanStages(join(workspace, 'old-src'));
  life.abort(new Error(secret));
  await assert.rejects(fs.resolve('/workspace'), aborted);
  await assert.rejects(fs.readText(fresh), aborted);
  assert.deepEqual(network, []);
  console.log('Official rc.3 Workspace provider checks passed (isolated POSIX fixture).');
} finally {
  life.abort();
  globalThis.fetch = nativeFetch;
  Server.prototype.listen = nativeListen;
  Socket.prototype.connect = nativeConnect;
  try { await scope?.dispose(); }
  finally {
    try { await ctx.fiber.dispose(); }
    finally { await rm(temp, { recursive: true, force: true }); }
  }
}
