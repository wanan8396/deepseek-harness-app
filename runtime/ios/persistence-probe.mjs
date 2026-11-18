import { randomBytes, randomUUID } from 'node:crypto';
import { isAbsolute, join } from 'node:path';
import { lstat, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const ROOTS = [
  ['session-projection', 'dsh-session-projection'], ['session', 'dsh-session'],
  ['system-prompt', 'dsh-system-prompt'], ['tools', 'dsh-tools'],
  ['tool-executor-native', 'dsh-tool-executor-native'], ['llm', 'dsh-llm'],
  ['agent', 'dsh-agent'], ['agent-loop', 'dsh-agent-loop'],
];
const CHECKS = ['storageBooted', 'writerExclusionVerified', 'readWhileOwnedVerified',
  'atomicAppendVerified', 'flushVerified', 'coldResumeVerified', 'disposeVerified', 'badBaselineRejected'];
const json = (value) => JSON.stringify(value);
const textOf = (message) => message?.content?.filter((block) => block.type === 'text').map((block) => block.text).join('');
class ProbeFailure extends Error {}
function requireCheck(value, code) { if (!value) throw new ProbeFailure(code); }

async function bounded(pending, milliseconds = 8000) {
  let timer;
  try {
    return await Promise.race([pending, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new ProbeFailure('IOS_PERSISTENCE_TIMEOUT')), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}

async function ownedBounded(pending, retire, milliseconds = 8000) {
  let abandoned = false;
  void pending.then(async (value) => {
    if (abandoned) {
      try { await retire(value); }
      catch { console.error('IOS_PERSISTENCE_LATE_CLEANUP_FAILED'); }
    }
  }, () => {});
  try { return await bounded(pending, milliseconds); }
  catch (error) { abandoned = true; throw error; }
}

// A deadline is not cancellation: a late Loader still owns resources.
export function bootPersistenceBounded(boot, args, milliseconds = 8000) {
  return ownedBounded(Promise.resolve().then(() => boot(...args)),
    (context) => context.fiber.dispose(), milliseconds);
}

/** File-backed SQLite and official AgentLoop close/reopen verification.
 * This is not an App-kill test, a live model, or a user-facing engine. */
export async function runPersistenceProbe(privateDir, bundleDir, expectedVersion) {
  const report = { ...Object.fromEntries(CHECKS.map((key) => [key, false])),
    engineReady: false, modelKind: 'offline-fixture', persistentStore: true,
    stage: 'input', errorCode: null };
  const roots = new Set();
  const providers = new Set();
  const handles = new Set();
  const agents = new Set();
  let work;
  let completed = false;
  const acquire = async (pending) => {
    const handle = await ownedBounded(Promise.resolve(pending), (late) => late.close());
    handles.add(handle);
    return handle;
  };
  const close = async (handle) => { await bounded(handle.close()); handles.delete(handle); };
  const releaseAgent = async (handle) => { await bounded(handle.dispose()); agents.delete(handle); };
  const releaseRoot = async (context) => { await bounded(context.fiber.dispose()); roots.delete(context); };
  try {
    for (const directory of [privateDir, bundleDir]) {
      requireCheck(typeof directory === 'string' && isAbsolute(directory), 'IOS_PERSISTENCE_INPUT_INVALID');
      const info = await lstat(directory);
      requireCheck(info.isDirectory() && !info.isSymbolicLink(), 'IOS_PERSISTENCE_INPUT_INVALID');
    }
    const manifest = JSON.parse(await readFile(join(bundleDir, 'distribution-manifest.json'), 'utf8'));
    requireCheck(manifest.distribution === 'ios-adapted-persistence-probe'
      && manifest.phase === 'persistence' && manifest.engineVersion === expectedVersion
      && manifest.engineReady === false, 'IOS_PERSISTENCE_DISTRIBUTION_INVALID');
    report.stage = 'import';
    const entryUrl = (name) => pathToFileURL(join(bundleDir, 'node_modules/@deepseek-ai', name, 'lib/index.js')).href;
    const { Context } = await import(entryUrl('cordis'));
    const { Session, SessionStore } = await import(entryUrl('dsh-session'));
    const { SessionPersistence, SessionAlreadyExistsError, SessionAlreadyOwnedError,
      SessionReadOnlyError, SessionHandleClosedError, SessionPersistenceNotFoundError,
      SessionPersistenceCorruptionError, SessionFormatUnsupportedError } = await import(entryUrl('dsh-session-persistence'));
    const { IosSqliteSessionPersistence } = await import(pathToFileURL(join(bundleDir, 'sqlite-session-persistence.mjs')).href);
    const { boot } = await import(entryUrl('dsh-app-boot'));
    const { createUserMessage } = await import(entryUrl('dsh-llm'));
    const { PROVIDER, MODEL } = await import(pathToFileURL(join(bundleDir, 'core-fixture-model.mjs')).href);
    work = await mkdtemp(join(privateDir, '.dsh-persistence-'));
    const directDir = join(work, 'direct');
    const durableDir = join(work, 'durable');
    await mkdir(directDir, { mode: 0o700 });
    await mkdir(durableDir, { mode: 0o700 });
    const direct = (directory) => {
      const context = new Context();
      roots.add(context);
      new SessionStore(context);
      const persistence = new IosSqliteSessionPersistence(context, { directory });
      providers.add(persistence);
      requireCheck(persistence instanceof SessionPersistence, 'IOS_PERSISTENCE_SERVICE_INVALID');
      return { context, persistence };
    };
    const rejects = async (call, accepts, code) => {
      try { await bounded(Promise.resolve().then(call)); }
      catch (error) {
        requireCheck(!(error instanceof ProbeFailure) && accepts(error), code);
        return;
      }
      throw new ProbeFailure(code);
    };
    const rawPrefix = (directory, id) => {
      const db = new DatabaseSync(join(directory, 'sessions.sqlite'), { readOnly: true, allowExtension: false });
      try {
        const row = db.prepare('SELECT next_seq FROM sessions WHERE id = ?').get(id);
        const records = db.prepare('SELECT seq, envelope_json FROM events WHERE session_id = ? ORDER BY seq').all(id);
        return { next: row?.next_seq, records: records.map(({ seq, envelope_json }) => [seq, envelope_json]) };
      } finally { db.close(); }
    };
    const assertPrefix = (directory, id, expected) => requireCheck(json(rawPrefix(directory, id)) === json(expected),
      'IOS_PERSISTENCE_PARTIAL_BATCH_COMMITTED');

    report.stage = 'writer-exclusion';
    const a = direct(directDir);
    const b = direct(directDir);
    requireCheck(a.persistence.identity !== b.persistence.identity, 'IOS_PERSISTENCE_IDENTITIES_SHARED');
    const sample = Session.create(randomUUID());
    const batch = sample.append([
      ['turn/start', { turn: 1 }], ['step/start', { turn: 1, step: 1 }],
      ['step/end', { turn: 1, step: 1 }], ['turn/end', { turn: 1, reason: { kind: 'completed' } }],
    ]);
    const id = sample.id;
    const writer = await acquire(a.persistence.create(sample.header));
    await bounded(writer.append(batch.slice(0, 2)));
    await rejects(() => b.persistence.open(id, 'write'), (error) => error instanceof SessionAlreadyOwnedError,
      'IOS_PERSISTENCE_DOUBLE_WRITER_ACCEPTED');
    await rejects(() => b.persistence.create(sample.header), (error) => error instanceof SessionAlreadyExistsError,
      'IOS_PERSISTENCE_DUPLICATE_CREATE_ACCEPTED');
    const other = Session.create(randomUUID());
    const otherWriter = await acquire(b.persistence.create(other.header));
    requireCheck(otherWriter.access === 'write' && otherWriter.id !== writer.id, 'IOS_PERSISTENCE_UNRELATED_WRITER_BLOCKED');

    report.stage = 'read-while-owned';
    const reader = await acquire(b.persistence.open(id, 'read'));
    const initial = await bounded(reader.read());
    const stat = await bounded(b.persistence.stat(id));
    const listed = await bounded(b.persistence.list());
    report.readWhileOwnedVerified = json(initial.events) === json(batch.slice(0, 2))
      && ['detached', 'shared-frozen'].includes(initial.eventState)
      && stat?.eventCount === 2 && listed.some((entry) => entry.header.id === id && entry.eventCount === 2);
    requireCheck(report.readWhileOwnedVerified, 'IOS_PERSISTENCE_OWNED_READ_INVALID');
    await rejects(() => reader.append(batch.slice(2)), (error) => error instanceof SessionReadOnlyError,
      'IOS_PERSISTENCE_READ_ONLY_APPEND_ACCEPTED');
    await rejects(() => reader.flush(), (error) => error instanceof SessionReadOnlyError,
      'IOS_PERSISTENCE_READ_ONLY_FLUSH_ACCEPTED');
    await close(reader);
    for (const operation of [() => reader.read(), () => reader.append([]), () => reader.flush()]) {
      await rejects(operation, (error) => error instanceof SessionHandleClosedError, 'IOS_PERSISTENCE_CLOSED_HANDLE_ACCEPTED');
    }
    await close(reader); // close is idempotent, unlike read/append/flush.

    report.stage = 'atomic-append';
    const before = rawPrefix(directDir, id);
    const invalidBatches = [
      [structuredClone(batch[2]), { ...structuredClone(batch[3]), seq: 5 }],
      [{ ...structuredClone(batch[2]), seq: 1 }],
      [structuredClone(batch[2]), { type: 'ios-probe/unknown-required', seq: 3, time: 0, data: {} }],
      [structuredClone(batch[2]), { ...structuredClone(batch[3]), data: { invalid: Number.NaN } }],
      [structuredClone(batch[2]), { ...structuredClone(batch[3]), seq: Number.MAX_SAFE_INTEGER + 1 }],
    ];
    for (const [index, badBatch] of invalidBatches.entries()) {
      await rejects(() => writer.append(badBatch), (error) => index === 2
        ? error instanceof SessionFormatUnsupportedError : index === 3
          ? error instanceof TypeError : error instanceof Error,
      'IOS_PERSISTENCE_BAD_BATCH_ACCEPTED');
      assertPrefix(directDir, id, before);
    }
    // This lock and SQL oracle are independent of provider validation helpers.
    const blocker = new DatabaseSync(join(directDir, 'sessions.sqlite'), { timeout: 0, allowExtension: false });
    try {
      blocker.exec('BEGIN IMMEDIATE');
      await rejects(() => writer.append(batch.slice(2)), (error) => !(error instanceof SessionAlreadyOwnedError)
        && error?.code === 'ERR_SQLITE_ERROR' && Number.isInteger(error.errcode)
        && [5, 6].includes(error.errcode & 255), 'IOS_PERSISTENCE_BACKEND_FAULT_MASKED');
      assertPrefix(directDir, id, before);
    } finally {
      if (blocker.isTransaction) blocker.exec('ROLLBACK');
      blocker.close();
    }
    // Force the second INSERT to fail inside SQLite, after the first INSERT
    // has run. Up-front batch validation alone cannot prove transaction rollback.
    const injection = new DatabaseSync(join(directDir, 'sessions.sqlite'), { timeout: 0, allowExtension: false });
    try {
      requireCheck(/^[a-f0-9-]+$/.test(id), 'IOS_PERSISTENCE_SQL_FIXTURE_ID_INVALID');
      injection.exec(`CREATE TRIGGER ios_probe_abort_batch BEFORE INSERT ON events
        WHEN NEW.session_id = '${id}' AND NEW.seq = 3
        BEGIN SELECT RAISE(ABORT, 'IOS_PERSISTENCE_EXPECTED_SQL_ABORT'); END;`);
      await rejects(() => writer.append(batch.slice(2)), (error) => error?.code === 'ERR_SQLITE_ERROR'
        && Number.isInteger(error.errcode) && (error.errcode & 255) === 19,
      'IOS_PERSISTENCE_MID_BATCH_FAULT_MASKED');
      assertPrefix(directDir, id, before);
    } finally {
      try { injection.exec('DROP TRIGGER IF EXISTS ios_probe_abort_batch'); }
      finally { injection.close(); }
    }
    await bounded(writer.append(batch.slice(2)));
    await bounded(writer.flush());
    const readAfterAppend = await acquire(b.persistence.open(id, 'read'));
    requireCheck(json((await bounded(readAfterAppend.read())).events) === json(batch), 'IOS_PERSISTENCE_APPEND_PREFIX_INVALID');
    await close(readAfterAppend);

    report.stage = 'aborted-open';
    const cancelled = new AbortController();
    cancelled.abort(new Error('IOS_PERSISTENCE_EXPECTED_ABORT'));
    const abortedSession = Session.create(randomUUID());
    await rejects(() => a.persistence.create(abortedSession.header, { signal: cancelled.signal }),
      (error) => error === cancelled.signal.reason, 'IOS_PERSISTENCE_ABORTED_CREATE_ACCEPTED');
    requireCheck(await a.persistence.stat(abortedSession.id) === undefined, 'IOS_PERSISTENCE_ABORTED_CREATE_LEAKED');
    const afterAbort = await acquire(b.persistence.create(abortedSession.header));
    await close(afterAbort);
    await close(writer);
    await rejects(() => a.persistence.open(id, 'write', { signal: cancelled.signal }),
      (error) => error === cancelled.signal.reason, 'IOS_PERSISTENCE_ABORTED_OPEN_ACCEPTED');
    const successor = await acquire(b.persistence.open(id, 'write'));
    requireCheck(json((await bounded(successor.read())).events) === json(batch), 'IOS_PERSISTENCE_WRITER_HANDOFF_INVALID');
    await close(successor);
    await close(otherWriter);
    report.writerExclusionVerified = true;
    report.atomicAppendVerified = true;

    const challenge = randomBytes(32).toString('hex');
    const stableId = randomUUID();
    const rows = ROOTS.map(([rowId, pkg]) => ({ id: rowId, name: entryUrl(pkg),
      ...(rowId === 'system-prompt' ? { config: { includeHarnessIdentity: false, includeRuntimeContext: false,
        personaPrefix: 'Offline iOS persistence verification fixture.' } } : {}),
      ...(rowId === 'agent-loop' ? { config: { agents: [] } } : {}),
    }));
    rows.splice(rows.length - 1, 0,
      { id: 'session-persistence', name: pathToFileURL(join(bundleDir, 'sqlite-session-persistence.mjs')).href,
        config: { directory: durableDir } },
      { id: 'session-checkpoint-policy', name: entryUrl('dsh-session-checkpoint-policy') },
      { id: 'ios-fixture-model', name: pathToFileURL(join(bundleDir, 'core-fixture-model.mjs')).href, config: { challenge } });
    const configPath = join(work, 'cordis.json');
    await writeFile(configPath, json(rows), { flag: 'wx', mode: 0o600 });
    const openRoot = async (config = configPath) => {
      const context = await bootPersistenceBounded(boot, ['dsh-ios-persistence', config, [], undefined]);
      roots.add(context);
      return context;
    };
    report.stage = 'boot';
    let ctx = await openRoot();
    const tree = ctx.get('loader')?.resolve('include')?.subtree;
    report.storageBooted = ctx.fiber.state === 2 && rows.every(({ id: rowId }) => tree?.resolve(rowId)?.fiber?.state === 2)
      && ctx.get('sessionPersistence') instanceof SessionPersistence && ctx.get('iosFixtureModel') != null;
    requireCheck(report.storageBooted, 'IOS_PERSISTENCE_PLUGIN_INACTIVE');
    const durableReader = direct(durableDir);
    const liveEvents = [];
    ctx.on('session/event', (session, event) => { if (session.id === stableId) liveEvents.push(event); });
    const agentOptions = { provider: PROVIDER, model: MODEL, maxTokens: 128 };
    let handle = await ownedBounded(ctx.agents.create({ sessionId: stableId, agentOptions }), (late) => late.dispose());
    agents.add(handle);
    const input = (kind) => createUserMessage({ content: [{ type: 'text', text: `probe-${kind}:${challenge}` }], source: { kind: 'user' } });
    const send = async (active, kind) => {
      active.agent.followup(input(kind));
      await bounded(active.agent.whenIdle());
      requireCheck(active.agent.status === 'idle', 'IOS_PERSISTENCE_AGENT_NOT_IDLE');
    };
    report.stage = 'first-second-turn';
    await send(handle, 'first');
    await send(handle, 'second');
    const requests = ctx.get('iosFixtureModel').requests;
    const visible = (request) => request?.messages.filter(({ role }) => role === 'user' || role === 'assistant');
    const expectedTwo = [
      { role: 'user', text: `probe-first:${challenge}` }, { role: 'assistant', text: `${challenge}:first` },
      { role: 'user', text: `probe-second:${challenge}` },
    ];
    requireCheck(requests.length === 2 && json(visible(requests[1])) === json(expectedTwo), 'IOS_PERSISTENCE_INITIAL_HISTORY_INVALID');
    requireCheck(textOf(liveEvents.findLast((event) => event.type === 'assistant/message')?.data.message) === `${challenge}:second`,
      'IOS_PERSISTENCE_SECOND_OUTPUT_INVALID');
    report.stage = 'flush';
    requireCheck(await bounded(ctx.sessions.flush(handle.agent.session)) === true, 'IOS_PERSISTENCE_FLUSH_NOT_PARTICIPATING');
    const independent = await acquire(durableReader.persistence.open(stableId, 'read'));
    const persisted = (await bounded(independent.read())).events;
    report.flushVerified = liveEvents.length > 0 && persisted.length === liveEvents.at(-1).seq + 1
      && liveEvents.every((event) => json(persisted[event.seq]) === json(event))
      && persisted.filter((event) => event.type === 'assistant/message').length === 2;
    requireCheck(report.flushVerified, 'IOS_PERSISTENCE_FLUSH_EVENTS_MISSING');
    await close(independent);

    report.stage = 'close-reopen-not-app-kill';
    await releaseAgent(handle);
    requireCheck(ctx.agents.get(stableId) == null && ctx.sessions.get(stableId) == null, 'IOS_PERSISTENCE_AGENT_DISPOSE_INVALID');
    const firstIdentity = ctx.get('sessionPersistence').identity;
    await releaseRoot(ctx);
    const releasedLease = await acquire(durableReader.persistence.open(stableId, 'write'));
    await close(releasedLease);
    ctx = await openRoot();
    requireCheck(ctx.get('sessionPersistence').identity !== firstIdentity, 'IOS_PERSISTENCE_CONTEXT_REUSED');
    handle = await ownedBounded(ctx.agents.resume({ resumeSessionId: stableId, agentOptions }), (late) => late.dispose());
    agents.add(handle);
    const resumedEvents = [];
    ctx.on('session/event', (session, event) => { if (session.id === stableId) resumedEvents.push(event); });
    await send(handle, 'recover');
    const recoveredRequests = ctx.get('iosFixtureModel').requests;
    const expectedThree = [...expectedTwo,
      { role: 'assistant', text: `${challenge}:second` }, { role: 'user', text: `probe-recover:${challenge}` }];
    requireCheck(recoveredRequests.length === 1 && json(visible(recoveredRequests[0])) === json(expectedThree),
      'IOS_PERSISTENCE_COLD_HISTORY_INVALID');
    requireCheck(textOf(resumedEvents.findLast((event) => event.type === 'assistant/message')?.data.message) === `${challenge}:recovered`,
      'IOS_PERSISTENCE_RECOVER_OUTPUT_INVALID');
    requireCheck(await bounded(ctx.sessions.flush(handle.agent.session)) === true, 'IOS_PERSISTENCE_COLD_FLUSH_NOT_PARTICIPATING');
    const recoveredReader = await acquire(durableReader.persistence.open(stableId, 'read'));
    const recoveredEvents = (await bounded(recoveredReader.read())).events;
    report.coldResumeVerified = json(recoveredEvents.slice(0, persisted.length)) === json(persisted)
      && recoveredEvents.filter((event) => event.type === 'assistant/message').length === 3
      && resumedEvents.every((event) => json(recoveredEvents[event.seq]) === json(event));
    requireCheck(report.coldResumeVerified, 'IOS_PERSISTENCE_RECOVER_PREFIX_INVALID');
    await close(recoveredReader);
    await releaseAgent(handle);

    report.stage = 'negative-stored-sequence';
    const corruptSession = Session.create(randomUUID());
    const corruptEvent = corruptSession.append('turn/start', { turn: 1 });
    const corruptWriter = await acquire(durableReader.persistence.create(corruptSession.header));
    await bounded(corruptWriter.append([corruptEvent]));
    await close(corruptWriter);
    const external = new DatabaseSync(join(durableDir, 'sessions.sqlite'), { timeout: 0, allowExtension: false });
    try {
      const changed = external.prepare('UPDATE events SET envelope_json = ? WHERE session_id = ? AND seq = 0')
        .run(json({ ...corruptEvent, seq: 7 }), corruptSession.id);
      requireCheck(changed.changes === 1, 'IOS_PERSISTENCE_CORRUPTION_FIXTURE_NOT_APPLIED');
    } finally { external.close(); }
    const corruptPrefix = rawPrefix(durableDir, corruptSession.id);
    await rejects(async () => {
      const broken = await acquire(durableReader.persistence.open(corruptSession.id, 'read'));
      try { await broken.read(); } finally { await close(broken); }
    }, (error) => error instanceof SessionPersistenceCorruptionError, 'IOS_PERSISTENCE_CORRUPT_READ_ACCEPTED');
    await rejects(() => ctx.agents.resume({ resumeSessionId: corruptSession.id, agentOptions }),
      (error) => error instanceof SessionPersistenceCorruptionError, 'IOS_PERSISTENCE_CORRUPT_RESUME_ACCEPTED');
    requireCheck(ctx.agents.get(corruptSession.id) == null && ctx.sessions.get(corruptSession.id) == null,
      'IOS_PERSISTENCE_CORRUPT_SESSION_SUBSTITUTED');
    assertPrefix(durableDir, corruptSession.id, corruptPrefix);
    const absentId = randomUUID();
    await rejects(() => ctx.agents.resume({ resumeSessionId: absentId, agentOptions }),
      (error) => error instanceof SessionPersistenceNotFoundError, 'IOS_PERSISTENCE_MISSING_RESUME_SUBSTITUTED');
    requireCheck(await durableReader.persistence.stat(absentId) === undefined && ctx.agents.get(absentId) == null,
      'IOS_PERSISTENCE_MISSING_RESUME_CREATED');
    await releaseRoot(ctx);

    report.stage = 'negative-missing-persistence';
    const noStorePath = join(work, 'missing-persistence.json');
    await writeFile(noStorePath, json(rows.filter(({ id: rowId }) => !['session-persistence', 'session-checkpoint-policy'].includes(rowId))),
      { flag: 'wx', mode: 0o600 });
    const noStore = await openRoot(noStorePath);
    requireCheck(noStore.get('sessionPersistence') == null, 'IOS_PERSISTENCE_NEGATIVE_STORE_PRESENT');
    await rejects(() => noStore.agents.resume({ resumeSessionId: stableId, agentOptions }),
      (error) => error instanceof Error, 'IOS_PERSISTENCE_NO_STORE_RESUME_ACCEPTED');
    report.badBaselineRejected = noStore.agents.get(stableId) == null && noStore.sessions.get(stableId) == null
      && noStore.get('iosFixtureModel').requests.length === 0;
    requireCheck(report.badBaselineRejected, 'IOS_PERSISTENCE_NO_STORE_SESSION_SUBSTITUTED');
    await releaseRoot(noStore);
    completed = true;
  } catch (error) {
    report.errorCode = error instanceof ProbeFailure ? error.message : 'IOS_DSH_PERSISTENCE_PROBE_FAILED';
  } finally {
    let clean = true;
    for (const handle of agents) {
      try { handle.agent.cancel({ kind: 'disposed' }); await bounded(handle.dispose()); }
      catch { clean = false; }
    }
    for (const handle of handles) {
      try { await bounded(handle.close()); }
      catch { clean = false; }
    }
    for (const provider of providers) {
      try { await bounded(provider.dispose()); }
      catch { clean = false; }
    }
    for (const context of roots) {
      try { await bounded(context.fiber.dispose()); }
      catch { clean = false; }
    }
    if (work) {
      try { await rm(work, { recursive: true, force: true }); }
      catch { clean = false; }
    }
    report.disposeVerified = completed && clean;
    if (!clean) { report.errorCode = 'IOS_DSH_PERSISTENCE_CLEANUP_FAILED'; report.stage = 'cleanup'; }
    else if (completed) report.stage = 'complete';
  }
  return report;
}
