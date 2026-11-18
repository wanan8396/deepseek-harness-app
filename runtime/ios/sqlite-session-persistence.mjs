// App-owned backend for the official SessionPersistence seam. No npm package is patched.
import {
  chmodSync, closeSync, constants, fstatSync, lstatSync, mkdirSync, openSync, realpathSync,
} from 'node:fs'
import { createHash, randomUUID } from 'node:crypto'
import { isAbsolute, join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import {
  SessionPersistence, SessionPersistenceRevision,
  SessionAlreadyExistsError, SessionAlreadyOwnedError, SessionFormatUnsupportedError,
  SessionHandleClosedError, SessionOwnershipLostError, SessionPersistenceCorruptionError,
  SessionPersistenceNotFoundError, SessionReadOnlyError,
  assertContiguous, assertStoredId, assertVersion, materializeAppendBatch,
  materializeCreateHeader, validateStoredEvents,
} from '@deepseek-ai/dsh-session-persistence'

export const name = 'ios-sqlite-session-persistence'
export const inject = ['sessions']

function freezeJson(value) {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) freezeJson(child)
    Object.freeze(value)
  }
  return value
}

function offset(value, label) {
  if (!Number.isSafeInteger(value) || value < 0 || Object.is(value, -0)) {
    throw new TypeError(`${label} must be a non-negative safe integer`)
  }
  return value
}

function sessionId(id) {
  if (typeof id !== 'string' || !id.isWellFormed()) {
    throw new TypeError('session id must be a well-formed Unicode string')
  }
  return id
}

// The public materializer validates lossless JSON; the remaining header fields
// mirror Session's metadata boundary (its header validator is not exported).
function headerMetadata(value, id) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('session header must be a JSON record')
  }
  assertVersion(value)
  assertStoredId(id, value)
  sessionId(value.id)
  offset(value.createdAt, 'createdAt')
  if (Object.hasOwn(value, 'seedLength')) throw new TypeError('retired session header seedLength')
  if (typeof value.isSeeded !== 'boolean') throw new TypeError('isSeeded must be boolean')
  if (value.cwd !== undefined && (typeof value.cwd !== 'string' || !isAbsolute(value.cwd))) {
    throw new TypeError('session cwd must be an absolute path')
  }
  for (const field of ['parentSession', 'agentPreset']) {
    if (value[field] !== undefined && typeof value[field] !== 'string') {
      throw new TypeError(`${field} must be a string`)
    }
  }
  if (value.origin !== undefined && value.origin !== 'subagent') throw new TypeError('invalid session origin')
  if (value.delegationDepth !== undefined) offset(value.delegationDepth, 'delegationDepth')
  return freezeJson(value)
}

function inheritedCut(header, supplied) {
  if (header.isSeeded && supplied === undefined) throw new TypeError('seeded session requires inheritedEventCount')
  const count = offset(supplied ?? 0, 'inheritedEventCount')
  if (!header.isSeeded && count !== 0) throw new TypeError('unseeded session has inherited events')
  return count
}

function eventBatch(header, batch) {
  if (!Array.isArray(batch)) throw new TypeError('session event batch must be an array')
  const fields = new Set(['type', 'seq', 'time', 'data', 'surfaceOp', 'sourceEventSeqs', 'ignorable'])
  for (const event of batch) {
    if (event === null || typeof event !== 'object' || Array.isArray(event)
      || Object.keys(event).some(key => !fields.has(key))
      || typeof event.type !== 'string' || !Number.isSafeInteger(event.time)
      || event.data === undefined || (event.ignorable !== undefined && event.ignorable !== true)) {
      throw new TypeError('invalid session event envelope')
    }
    offset(event.seq, 'event seq')
  }
  return validateStoredEvents(header, batch)
}

function corruption(id, error) {
  if (error instanceof SessionFormatUnsupportedError || error instanceof SessionPersistenceCorruptionError) return error
  return new SessionPersistenceCorruptionError(`stored session "${id}" failed validation`, { cause: error })
}

function transaction(db, begin, operation) {
  db.exec(begin)
  try {
    const result = operation()
    db.exec('COMMIT')
    return result
  } catch (error) {
    if (db.isTransaction) {
      try { db.exec('ROLLBACK') } catch (rollbackError) {
        throw new AggregateError([error, rollbackError], 'SQLite transaction and rollback failed')
      }
    }
    throw error
  }
}

function privateDirectory(path) {
  mkdirSync(path, { recursive: true, mode: 0o700 })
  const info = lstatSync(path)
  if (info.isSymbolicLink() || !info.isDirectory()) throw new TypeError('storage directory must be a real directory')
  chmodSync(path, 0o700)
  return realpathSync(path)
}

function assertPrivateFile(info) {
  if (info.isSymbolicLink() || !info.isFile() || info.nlink !== 1) {
    throw new TypeError('SQLite input must be a regular file with exactly one link')
  }
}

function realFile(path) {
  // Never raw-open/close an existing SQLite inode: POSIX close on *any* fd
  // for that inode can release this process's SQLite fcntl locks. Only a new
  // O_EXCL inode is opened here; existing files are inspected with lstat.
  try { assertPrivateFile(lstatSync(path)) } catch (error) {
    if (error?.code !== 'ENOENT') throw error
    let fd
    try {
      fd = openSync(path, constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600)
    } catch (createError) {
      if (createError?.code !== 'EEXIST') throw createError
    }
    if (fd !== undefined) {
      try { assertPrivateFile(fstatSync(fd)) } finally { closeSync(fd) }
    }
    // Another creator may have won O_EXCL; validate without opening its inode.
    assertPrivateFile(lstatSync(path))
  }
  chmodSync(path, 0o600)
  for (const suffix of ['-journal', '-wal', '-shm']) {
    try {
      assertPrivateFile(lstatSync(path + suffix))
      chmodSync(path + suffix, 0o600)
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error
    }
  }
}

function sqliteBusy(error) {
  // Only the lease's BEGIN IMMEDIATE uses this mapping. Main-store faults retain
  // their original SQLite error/code, including BUSY, IOERR and FULL.
  return (Number.isInteger(error?.errcode) && (error.errcode & 255) === 5)
    || error?.code === 'SQLITE_BUSY'
}

function closeLease(lease) {
  const failures = []
  if (lease.db.isOpen && lease.db.isTransaction) {
    try { lease.db.exec('ROLLBACK') } catch (error) { failures.push(error) }
  }
  if (lease.db.isOpen) {
    try { lease.db.close() } catch (error) { failures.push(error) }
  }
  if (failures.length) throw new AggregateError(failures, 'SQLite lease release failed')
}

class SqliteBackend {
  constructor(config) {
    if (typeof config?.directory !== 'string' || !isAbsolute(config.directory)) {
      throw new TypeError('directory must be an absolute App-private directory')
    }
    this.directory = privateDirectory(config.directory)
    this.leasesDirectory = privateDirectory(join(this.directory, 'leases'))
    this.path = join(this.directory, 'sessions.sqlite')
    this.handles = new Set()
    this.writers = new Map()
    this.retiredFailures = []
    this.revisionSalt = randomUUID()
    this.disposing = false
    realFile(this.path)
    this.db = new DatabaseSync(this.path, { timeout: 0, allowExtension: false })
    try {
      this.db.exec('PRAGMA busy_timeout=0; PRAGMA foreign_keys=ON; PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA;')
      const version = this.db.prepare('PRAGMA user_version').get().user_version
      if (version !== 0 && version !== 1) throw new Error('unsupported iOS session database schema')
      transaction(this.db, 'BEGIN IMMEDIATE', () => {
        this.db.exec(`
          CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY NOT NULL,
            header_json TEXT NOT NULL,
            inherited_count INTEGER NOT NULL CHECK(inherited_count >= 0),
            next_seq INTEGER NOT NULL CHECK(next_seq >= 0),
            content_revision TEXT NOT NULL,
            writer_token TEXT
          );
          CREATE TABLE IF NOT EXISTS events (
            session_id TEXT NOT NULL REFERENCES sessions(id),
            seq INTEGER NOT NULL CHECK(seq >= 0),
            envelope_json TEXT NOT NULL,
            PRIMARY KEY(session_id, seq)
          );
          PRAGMA user_version=1;
        `)
      })
    } catch (error) {
      try { this.db.close() } catch (closeError) {
        throw new AggregateError([error, closeError], 'SQLite initialization failed')
      }
      throw error
    }
  }

  assertAvailable() {
    if (this.disposing || !this.db.isOpen) throw new Error('iOS session persistence is disposed')
  }

  row(id) {
    return this.db.prepare('SELECT * FROM sessions WHERE id=?').get(id)
  }

  metadata(row) {
    try {
      const header = headerMetadata(JSON.parse(row.header_json), row.id)
      const inheritedEventCount = inheritedCut(header, row.inherited_count)
      offset(row.next_seq, 'stored next_seq')
      if (typeof row.content_revision !== 'string') throw new TypeError('invalid content revision')
      return { header, inheritedEventCount, count: row.next_seq }
    } catch (error) { throw corruption(row.id, error) }
  }

  snapshot(row) {
    const { header, count } = this.metadata(row)
    return {
      header, formatStatus: 'current', eventCount: count,
      revision: SessionPersistenceRevision(`${this.revisionSalt}:${row.content_revision}`),
    }
  }

  readLog(id) {
    // Each call gets a new short read transaction, never a handle-lifetime snapshot.
    return transaction(this.db, 'BEGIN', () => {
      const row = this.row(id)
      if (!row) throw new SessionPersistenceNotFoundError(id)
      const metadata = this.metadata(row)
      const records = this.db.prepare('SELECT seq,envelope_json FROM events WHERE session_id=? ORDER BY seq').all(id)
      try {
        const events = records.map((record, index) => {
          const event = JSON.parse(record.envelope_json)
          if (record.seq !== index || event?.seq !== record.seq) throw new Error('stored event sequence mismatch')
          return event
        })
        if (events.length !== metadata.count) throw new Error('stored event count mismatch')
        if (metadata.inheritedEventCount > events.length) throw new Error('inherited cut exceeds stored log')
        assertContiguous(id, events, 0)
        eventBatch(metadata.header, events)
        return { ...metadata, events }
      } catch (error) { throw corruption(id, error) }
    })
  }

  acquireLease(id) {
    const hash = createHash('sha256').update(id).digest('hex')
    const path = join(this.leasesDirectory, `${hash}.sqlite`)
    realFile(path)
    const db = new DatabaseSync(path, { timeout: 0, allowExtension: false })
    const lease = { db, token: randomUUID(), lost: false }
    try {
      db.exec('PRAGMA busy_timeout=0; PRAGMA synchronous=FULL;')
      // This independent connection holds the RESERVED lock until handle.close.
      // Lease files are stable: never unlink/replace them, including after a crash.
      try { db.exec('BEGIN IMMEDIATE') } catch (error) {
        if (sqliteBusy(error)) throw new SessionAlreadyOwnedError(id)
        throw error
      }
      return lease
    } catch (error) {
      try { closeLease(lease) } catch (closeError) {
        throw new AggregateError([error, closeError], 'SQLite lease acquisition failed')
      }
      throw error
    }
  }

  assertOwner(handle, row) {
    const lease = handle.lease
    if (lease.lost || !lease.db.isOpen || !lease.db.isTransaction || row?.writer_token !== lease.token) {
      lease.lost = true
      throw new SessionOwnershipLostError(handle.id)
    }
  }

  persist(handle, batch) {
    transaction(this.db, 'BEGIN IMMEDIATE', () => {
      const row = this.row(handle.id)
      this.assertOwner(handle, row)
      assertContiguous(handle.id, batch, row.next_seq)
      offset(row.next_seq + batch.length, 'next_seq')
      const insert = this.db.prepare('INSERT INTO events(session_id,seq,envelope_json) VALUES(?,?,?)')
      for (const event of batch) insert.run(handle.id, event.seq, JSON.stringify(event))
      if (batch.length) {
        this.db.prepare('UPDATE sessions SET next_seq=?,content_revision=? WHERE id=? AND writer_token=?')
          .run(row.next_seq + batch.length, randomUUID(), handle.id, handle.lease.token)
      }
    })
  }

  barrier(handle) {
    transaction(this.db, 'BEGIN IMMEDIATE', () => this.assertOwner(handle, this.row(handle.id)))
  }

  release(handle) {
    const failures = []
    try {
      transaction(this.db, 'BEGIN IMMEDIATE', () => {
        this.db.prepare('UPDATE sessions SET writer_token=NULL WHERE id=? AND writer_token=?')
          .run(handle.id, handle.lease.token)
      })
    } catch (error) { failures.push(error) }
    try { closeLease(handle.lease) } catch (error) { failures.push(error) }
    if (failures.length) throw new AggregateError(failures, `session "${handle.id}": release failed`)
  }

  adopt(header, inheritedEventCount, access, lease, count = 0) {
    const handle = new SqliteSessionHandle(this, header, inheritedEventCount, access, lease, count)
    this.handles.add(handle)
    if (access === 'write') this.writers.set(handle.id, handle)
    return handle
  }

  async flushAll() {
    const failures = [...this.retiredFailures]
    const writers = [...this.writers.values()]
    for (const writer of writers) {
      try { await (writer.closed ? writer.close() : writer.flush()) } catch (error) {
        if (error instanceof SessionHandleClosedError) {
          try { await writer.close() } catch (closeError) { failures.push(closeError) }
        } else failures.push(error)
      }
    }
    if (failures.length) throw new AggregateError(failures, `${name}: flush failed`)
  }

  install(ctx) {
    const backend = this
    return ctx.effect(function* () {
      yield () => backend.dispose()
      yield ctx.on('session/event', (session, event) => {
        backend.writers.get(session.id)?.enqueueLive(event, ctx)
      })
      yield ctx.on('session/flush', session => {
        const writer = backend.writers.get(session.id)
        return writer && (writer.closed ? writer.close() : writer.flush())
      })
      yield ctx.on('session/disposed', session => {
        const writer = backend.writers.get(session.id)
        if (writer) writer.close().catch(error => {
          // Keep the failure for the next explicit barrier and resource teardown.
          ctx.logger?.warn?.(`${name}: final drain failed for session "${session.id}": ${String(error)}`)
        })
      })
    }, `${name} routing and database`)
  }

  dispose() {
    if (this.disposal) return this.disposal
    this.disposing = true
    this.disposal = (async () => {
      const failures = [...this.retiredFailures]
      for (const handle of [...this.handles]) {
        try { await handle.close() } catch (error) { failures.push(error) }
      }
      try { if (this.db.isOpen) this.db.close() } catch (error) { failures.push(error) }
      if (failures.length) throw new AggregateError(failures, `${name}: dispose failed`)
    })()
    return this.disposal
  }
}

class SqliteSessionHandle {
  constructor(backend, header, inheritedEventCount, access, lease, observed) {
    Object.defineProperties(this, {
      id: { value: header.id, enumerable: true },
      header: { value: header, enumerable: true },
      inheritedEventCount: { value: inheritedEventCount, enumerable: true },
      access: { value: access, enumerable: true },
    })
    this.backend = backend
    this.lease = lease
    this.observed = observed
    this.closed = false
    this.chain = Promise.resolve()
    this.live = []
  }

  assertOpen(operation) {
    if (this.closed) throw new SessionHandleClosedError(this.id, operation)
  }

  assertWrite(operation) {
    this.assertOpen(operation)
    if (this.access !== 'write') throw new SessionReadOnlyError(this.id, operation)
    if (this.lease.lost) throw new SessionOwnershipLostError(this.id)
  }

  enqueue(operation) {
    const next = this.chain.then(operation)
    // Each returned operation retains its own rejection. The scheduling tail is
    // settled so a failed operation never poisons retries or skips teardown.
    this.chain = next.then(() => undefined, () => undefined)
    return next
  }

  drainThrough(mark) {
    if (this.routeFailure) throw this.routeFailure
    if (!mark) return
    const index = this.live.indexOf(mark)
    if (index < 0) return // already committed by an earlier barrier
    const batch = this.live.slice(0, index + 1).flatMap(entry => entry.events)
    this.backend.persist(this, batch)
    this.live.splice(0, index + 1) // only COMMIT consumes the buffered prefix
    this.observed = Math.max(this.observed, batch.at(-1)?.seq + 1 || 0)
  }

  enqueueLive(event, ctx) {
    if (this.closed) return
    try {
      const batch = materializeAppendBatch([event])
      eventBatch(this.header, batch)
      const mark = { events: batch }
      this.live.push(mark)
      this.enqueue(() => this.drainThrough(mark)).catch(error => {
        // No event is removed on failure; explicit flush/close retries the same prefix.
        ctx.logger?.warn?.(`${name}: buffered write failed for session "${this.id}": ${String(error)}`)
      })
    } catch (error) {
      // Synchronous event observers are contained by Session; remember snapshot
      // failures so the awaited checkpoint reports them instead of losing data.
      this.routeFailure ??= error
    }
  }

  async read(start = 0, length = Number.MAX_SAFE_INTEGER, options) {
    this.assertOpen('read')
    offset(start, 'read offset')
    offset(length, 'read length')
    options?.signal?.throwIfAborted()
    return this.enqueue(() => {
      options?.signal?.throwIfAborted()
      const source = this.backend.readLog(this.id)
      if (source.count < this.observed) throw corruption(this.id, new Error('stored log shrank'))
      this.observed = source.count
      return { eventState: 'detached', events: source.events.slice(start, start + length) }
    })
  }

  async append(events, options) {
    this.assertWrite('append')
    options?.signal?.throwIfAborted()
    const batch = materializeAppendBatch(events)
    eventBatch(this.header, batch)
    const first = batch[0]?.seq
    const last = batch.at(-1)?.seq
    const mark = this.live.findLast(entry => entry.events.at(-1).seq < first)
    return this.enqueue(() => {
      options?.signal?.throwIfAborted()
      if (batch.length && this.live.some(entry => entry.events.some(event => event.seq >= first && event.seq <= last))) {
        throw new Error(`session "${this.id}": append overlaps buffered live events`)
      }
      this.drainThrough(mark)
      this.backend.persist(this, batch)
      this.observed = Math.max(this.observed, batch.at(-1)?.seq + 1 || 0)
    })
  }

  async flush(options) {
    this.assertWrite('flush')
    options?.signal?.throwIfAborted()
    const mark = this.live.at(-1)
    return this.enqueue(() => {
      options?.signal?.throwIfAborted()
      this.drainThrough(mark)
      this.backend.barrier(this)
    })
  }

  close() {
    if (this.closing) return this.closing
    this.closed = true // admission closes immediately, even while queued operations finish
    const mark = this.live.at(-1)
    this.closing = this.enqueue(() => {
      const failures = []
      if (this.access === 'write') {
        try { this.drainThrough(mark); this.backend.barrier(this) } catch (error) { failures.push(error) }
        try { this.backend.release(this) } catch (error) { failures.push(error) }
      }
      this.backend.handles.delete(this)
      if (this.backend.writers.get(this.id) === this) this.backend.writers.delete(this.id)
      if (failures.length) {
        const error = new AggregateError(failures, `session "${this.id}": close failed`)
        this.backend.retiredFailures.push(error)
        throw error
      }
    })
    return this.closing
  }

  [Symbol.asyncDispose]() { return this.close() }
}

export class IosSqliteSessionPersistence extends SessionPersistence {
  constructor(ctx, config, backend) {
    // Open the resource before publishing the service, so constructor failure
    // cannot leave a successfully registered but unusable persistence service.
    const storage = backend ?? new SqliteBackend(config)
    super(ctx)
    this.storage = storage
    if (!backend) storage.install(ctx)
  }

  async create(header, options) {
    options?.signal?.throwIfAborted()
    this.storage.assertAvailable()
    const meta = materializeCreateHeader(header)
    headerMetadata(meta, meta.id)
    const count = inheritedCut(meta, options?.inheritedEventCount)
    if (this.storage.row(meta.id)) throw new SessionAlreadyExistsError(meta.id)
    let lease
    try {
      lease = this.storage.acquireLease(meta.id)
      transaction(this.storage.db, 'BEGIN IMMEDIATE', () => {
        if (this.storage.row(meta.id)) throw new SessionAlreadyExistsError(meta.id)
        this.storage.db.prepare(`INSERT INTO sessions
          (id,header_json,inherited_count,next_seq,content_revision,writer_token) VALUES(?,?,?,0,?,?)`)
          .run(meta.id, JSON.stringify(meta), count, randomUUID(), lease.token)
      })
      return this.storage.adopt(meta, count, 'write', lease)
    } catch (error) {
      if (lease) {
        try { closeLease(lease) } catch (closeError) {
          throw new AggregateError([error, closeError], 'session create failed')
        }
      }
      throw error
    }
  }

  async open(id, access, options) {
    options?.signal?.throwIfAborted()
    this.storage.assertAvailable()
    sessionId(id)
    if (access !== 'read' && access !== 'write') throw new TypeError('access must be read or write')
    if (!this.storage.row(id)) throw new SessionPersistenceNotFoundError(id)
    let lease
    try {
      if (access === 'write') lease = this.storage.acquireLease(id)
      const source = this.storage.readLog(id)
      if (lease) transaction(this.storage.db, 'BEGIN IMMEDIATE', () => {
        if (!this.storage.row(id)) throw new SessionPersistenceNotFoundError(id)
        this.storage.db.prepare('UPDATE sessions SET writer_token=? WHERE id=?').run(lease.token, id)
      })
      return this.storage.adopt(source.header, source.inheritedEventCount, access, lease, source.count)
    } catch (error) {
      if (lease) {
        try { closeLease(lease) } catch (closeError) {
          throw new AggregateError([error, closeError], 'session open failed')
        }
      }
      throw error
    }
  }

  async flush() {
    this.storage.assertAvailable()
    return this.storage.flushAll()
  }

  async stat(id, options) {
    options?.signal?.throwIfAborted()
    this.storage.assertAvailable()
    sessionId(id)
    const row = this.storage.row(id)
    return row ? this.storage.snapshot(row) : undefined
  }

  async list(options) {
    options?.signal?.throwIfAborted()
    this.storage.assertAvailable()
    return this.storage.db.prepare('SELECT * FROM sessions').all().map(row => this.storage.snapshot(row))
  }

  // App-owned resource shutdown for direct construction; not an added SDK method.
  dispose() { return this.storage.dispose() }
  [Symbol.asyncDispose]() { return this.dispose() }
}

export async function apply(ctx, config) {
  let service
  // Consumers unload when the inner service disappears, before outer routing
  // and SQLite resources unwind. A bare root dispose is otherwise concurrent.
  ctx.effect(function* () {
    const backend = new SqliteBackend(config)
    yield backend.install(ctx)
    service = ctx.plugin({
      name: `${name}-service`,
      apply(serviceCtx) { new IosSqliteSessionPersistence(serviceCtx, config, backend) },
    })
    yield service.dispose
  }, `${name} resource ownership`)
  await service.await()
}
