import { randomBytes, randomUUID } from 'node:crypto';
import { isAbsolute, join } from 'node:path';
import { lstat, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const ROOTS = [
  ['session-projection', 'dsh-session-projection'], ['session', 'dsh-session'],
  ['system-prompt', 'dsh-system-prompt'], ['tools', 'dsh-tools'],
  ['tool-executor-native', 'dsh-tool-executor-native'], ['llm', 'dsh-llm'],
  ['agent', 'dsh-agent'], ['agent-loop', 'dsh-agent-loop'],
];
const CHECKS = ['coreBooted', 'servicesVerified', 'firstTurnStreamed', 'secondTurnHistoryVerified',
  'cancellationSettled', 'errorSettled', 'disposeVerified', 'badBaselineRejected'];
const textOf = (message) => message?.content?.filter((block) => block.type === 'text').map((block) => block.text).join('');

async function bounded(promise, milliseconds = 8000) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('IOS_CORE_TIMEOUT')), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}

async function bootBounded(boot, ...args) {
  let abandoned = false;
  const pending = boot(...args);
  // Promise.race does not cancel boot. Dispose a root that arrives after this
  // caller has timed out; the application must never retain an orphan Loader.
  void pending.then(async (context) => {
    if (abandoned) {
      try { await context.fiber.dispose(); }
      catch { console.error('IOS_CORE_LATE_DISPOSE_FAILED'); }
    }
  }, () => {});
  try { return await bounded(pending); }
  catch (error) { abandoned = true; throw error; }
}

/** Executes supplier AgentLoop logic with only the external model replaced by a
 * deterministic offline adapter. It deliberately mounts no persistence backend. */
export async function runCoreProbe(privateDir, bundleDir) {
  const report = { ...Object.fromEntries(CHECKS.map((key) => [key, false])),
    ephemeral: true, engineReady: false, modelKind: 'offline-fixture', stage: 'input', errorCode: null };
  let work;
  let ctx;
  let handle;
  let bad;
  try {
    for (const directory of [privateDir, bundleDir]) {
      if (!isAbsolute(directory)) throw new Error('IOS_CORE_INPUT_INVALID');
      const stat = await lstat(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('IOS_CORE_INPUT_INVALID');
    }
    const manifest = JSON.parse(await readFile(join(bundleDir, 'distribution-manifest.json'), 'utf8'));
    if (manifest.distribution !== 'ios-adapted-core-probe' || manifest.engineVersion !== '0.2.2-rc.3') {
      throw new Error('IOS_CORE_DISTRIBUTION_INVALID');
    }
    report.stage = 'import';
    const entryUrl = (packageName) => pathToFileURL(join(bundleDir, 'node_modules/@deepseek-ai', packageName, 'lib/index.js')).href;
    const { boot, StartupError } = await import(entryUrl('dsh-app-boot'));
    const { createUserMessage, expandAssistantStream } = await import(entryUrl('dsh-llm'));
    const { brandString } = await import(entryUrl('dsh-brand'));
    const { PROVIDER, MODEL } = await import(pathToFileURL(join(bundleDir, 'core-fixture-model.mjs')).href);
    const challenge = randomBytes(32).toString('hex');
    work = await mkdtemp(join(privateDir, '.dsh-core-'));
    const rows = ROOTS.map(([id, pkg]) => ({ id, name: entryUrl(pkg),
      ...(id === 'system-prompt' ? { config: { includeHarnessIdentity: false, includeRuntimeContext: false,
        personaPrefix: 'Offline iOS AgentLoop verification fixture.' } } : {}),
      ...(id === 'agent-loop' ? { config: { agents: [] } } : {}),
    }));
    rows.splice(rows.length - 1, 0, { id: 'ios-fixture-model',
      name: pathToFileURL(join(bundleDir, 'core-fixture-model.mjs')).href, config: { challenge } });
    const configPath = join(work, 'cordis.json');
    await writeFile(configPath, JSON.stringify(rows), { flag: 'wx', mode: 0o600 });
    report.stage = 'boot';
    ctx = await bootBounded(boot, 'dsh-ios-core', configPath, [], undefined);
    const tree = ctx.get('loader')?.resolve('include')?.subtree;
    report.coreBooted = ctx.fiber.state === 2 && rows.every(({ id }) => tree?.resolve(id)?.fiber?.state === 2);
    if (!report.coreBooted) throw new Error('IOS_CORE_PLUGIN_INACTIVE');
    const serviceNames = ['agents', 'sessions', 'llm', 'tools', 'systemPrompt', 'sessionProjections', 'iosFixtureModel'];
    report.servicesVerified = serviceNames.every((name) => ctx.get(name) != null)
      && ctx.get('sessionPersistence') == null;
    if (!report.servicesVerified) throw new Error('IOS_CORE_SERVICE_MISSING');
    const id = brandString(randomUUID());
    const events = [];
    const frames = [];
    ctx.on('session/event', (session, event) => { if (session.id === id) events.push(event); });
    ctx.on('agent/assistant-stream', ({ agent, frame }) => { if (agent.id === id) frames.push(frame); });
    const errors = [];
    ctx.on('agent/error', ({ agent, error }) => { if (agent.id === id) errors.push(error); });
    handle = await bounded(ctx.agents.create({ sessionId: id,
      agentOptions: { provider: PROVIDER, model: MODEL, maxTokens: 128 } }));
    const agent = handle.agent;
    const fixture = ctx.get('iosFixtureModel');
    const input = (kind) => createUserMessage({ content: [{ type: 'text', text: `probe-${kind}:${challenge}` }], source: { kind: 'user' } });
    const send = async (kind) => {
      agent.followup(input(kind));
      await bounded(agent.whenIdle());
      if (agent.status !== 'idle') throw new Error('IOS_CORE_AGENT_NOT_IDLE');
    };
    const lastAssistant = () => events.findLast((event) => event.type === 'assistant/message');
    const lastTurn = () => events.findLast((event) => event.type === 'turn/end');

    report.stage = 'first-turn';
    await send('first');
    const first = lastAssistant();
    const deltas = first ? expandAssistantStream(first.data.stream).filter(({ chunk }) => chunk.type === 'text-delta') : [];
    report.firstTurnStreamed = textOf(first?.data.message) === `${challenge}:first`
      && deltas.length === 2 && deltas.map(({ chunk }) => chunk.text).join('') === `${challenge}:first`
      && frames.filter((frame) => frame.type === 'chunk' && frame.chunk.type === 'text-delta').length === 2
      && frames.some((frame) => frame.type === 'end' && frame.outcome.kind === 'committed')
      && lastTurn()?.data.reason.kind === 'completed';
    if (!report.firstTurnStreamed) throw new Error('IOS_CORE_FIRST_STREAM_INVALID');

    report.stage = 'second-turn';
    await send('second');
    const secondRequest = fixture.requests.find((request) => request.input === `probe-second:${challenge}`);
    const history = secondRequest?.messages.filter((message) => message.role === 'user' || message.role === 'assistant') ?? [];
    const firstInputIndex = history.findIndex((message) => message.role === 'user' && message.text === `probe-first:${challenge}`);
    const firstAnswerIndex = history.findIndex((message) => message.role === 'assistant' && message.text === `${challenge}:first`);
    const secondInputIndex = history.findIndex((message) => message.role === 'user' && message.text === `probe-second:${challenge}`);
    report.secondTurnHistoryVerified = firstInputIndex >= 0 && firstAnswerIndex > firstInputIndex
      && secondInputIndex > firstAnswerIndex && textOf(lastAssistant()?.data.message) === `${challenge}:second`
      && events.filter((event) => event.type === 'turn/end' && event.data.reason.kind === 'completed').length === 2;
    if (!report.secondTurnHistoryVerified) throw new Error('IOS_CORE_HISTORY_INVALID');

    report.stage = 'cancel';
    agent.followup(input('cancel'));
    await bounded(fixture.cancelStarted.promise);
    agent.cancel({ kind: 'user' });
    await bounded(agent.whenIdle());
    report.cancellationSettled = fixture.cancelObserved === true && agent.status === 'idle'
      && lastTurn()?.data.reason.kind === 'aborted' && lastTurn()?.data.reason.reason.kind === 'user'
      && lastAssistant()?.data.interrupted === true;
    if (!report.cancellationSettled) throw new Error('IOS_CORE_CANCEL_INVALID');

    report.stage = 'error';
    await send('error');
    const failure = lastTurn()?.data.reason;
    const observedFailure = fixture.errorObserved === true && failure?.kind === 'error'
      && failure.error.code === 'AUTH' && errors.length > 0;
    await send('recover');
    report.errorSettled = observedFailure && agent.status === 'idle'
      && textOf(lastAssistant()?.data.message) === `${challenge}:recovered`
      && lastTurn()?.data.reason.kind === 'completed';
    if (!report.errorSettled) throw new Error('IOS_CORE_ERROR_NOT_RECOVERED');

    report.stage = 'dispose';
    await bounded(handle.dispose());
    handle = undefined;
    report.disposeVerified = ctx.agents.get(id) == null && ctx.sessions.get(id) == null;
    await bounded(ctx.fiber.dispose());
    ctx = undefined;
    if (!report.disposeVerified) throw new Error('IOS_CORE_DISPOSE_INVALID');

    report.stage = 'negative';
    const badPath = join(work, 'missing-system-prompt.json');
    await writeFile(badPath, JSON.stringify(rows.filter(({ id }) => id !== 'system-prompt')), { flag: 'wx', mode: 0o600 });
    try { bad = await bootBounded(boot, 'dsh-ios-core-bad-baseline', badPath, [], undefined); }
    catch (error) {
      report.badBaselineRejected = error instanceof StartupError && error.entries.some(({ id, required, outcome }) =>
        id === 'agent-loop' && required === true && outcome.kind === 'pending' && outcome.missing.includes('systemPrompt'));
    }
    if (!report.badBaselineRejected) throw new Error('IOS_CORE_BAD_BASELINE_ACCEPTED');
    report.stage = 'complete';
  } catch {
    report.errorCode = 'IOS_DSH_CORE_PROBE_FAILED';
  } finally {
    if (handle) {
      try { handle.agent.cancel({ kind: 'disposed' }); await bounded(handle.dispose()); }
      catch { report.disposeVerified = false; report.errorCode = 'IOS_DSH_CORE_CLEANUP_FAILED'; }
    }
    for (const context of [bad, ctx]) {
      try { if (context) await bounded(context.fiber.dispose()); }
      catch { report.disposeVerified = false; report.errorCode = 'IOS_DSH_CORE_CLEANUP_FAILED'; }
    }
    if (work) {
      try { await rm(work, { recursive: true, force: true }); }
      catch { report.disposeVerified = false; report.errorCode = 'IOS_DSH_CORE_CLEANUP_FAILED'; }
    }
  }
  return report;
}
