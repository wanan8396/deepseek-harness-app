(() => {
  // Official main.ts replaces __DSH_TRANSPORT__ only for dshDesktopBoot, so the
  // page-world hook must exist before any official script evaluates.
  const handler = window.webkit?.messageHandlers?.dshBridge;
  const name = 'IOS_WEB_TRANSPORT_UNAVAILABLE';
  const blocked = () => Promise.reject(new TypeError(name));
  if (!handler || typeof handler.postMessage !== 'function') {
    window.__DSH_TRANSPORT__ = Object.freeze({ ownsHost: true, fetch: blocked,
      openStream: async function* () { throw new TypeError(name); },
    });
    return;
  }
  const send = (frame) => handler.postMessage(frame);
  const fetchImpl = async (input, init) => {
    const target = input instanceof Request ? input : new URL(input, 'dsh-app://bundle/');
    const url = new URL(target instanceof Request ? target.url : target);
    if (url.protocol !== 'dsh-app:' || url.host !== 'bundle' || url.port || url.username || url.password
        || !url.pathname.startsWith('/api/') || url.hash) return blocked();
    const request = new Request(target, init);
    request.signal.throwIfAborted();
    const headers = [];
    request.headers.forEach((value, name) => { headers.push([name, value]); });
    let body = null;
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      const bytes = new Uint8Array(await request.arrayBuffer());
      if (bytes.byteLength > 256 * 1024) return blocked();
      let binary = '';
      for (const byte of bytes) binary += String.fromCharCode(byte);
      body = btoa(binary);
    }
    request.signal.throwIfAborted();
    const reply = await send({
      type: 'request', method: request.method, path: `${url.pathname}${url.search}`, headers, body,
    });
    request.signal.throwIfAborted();
    if (!reply || typeof reply.status !== 'number' || typeof reply.body !== 'string'
        || reply.body.length > 350_000) throw new TypeError('IOS_WEB_TRANSPORT_FAILED');
    const raw = atob(reply.body);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return new Response(bytes.byteLength ? bytes : null, { status: reply.status, headers: reply.headers ?? {} });
  };
  const openedStreams = new Set();
  const streamRoute = globalThis.__DSH_IOS_APP_CARRIER__ === true ? 'api/ios-app/stream' : 'api/ios-ci/stream';
  const readOnlyEndpoints = new Set(['$events', 'remoteAccess/follow', 'workspace/follow', 'session/control', 'session/follow']);
  let retired = false;
  // RunnerTests supports only the audited downlink streams. Generated Remote
  // supplies an uplink iterable even for downlink-only descriptors; none of
  // these contracts consume it. Their ClientStreamHandle closes the queue.
  async function* openStream(endpoint, payload, signal) {
    if (retired || !readOnlyEndpoints.has(endpoint)) throw new TypeError(name);
    signal?.throwIfAborted();
    const id = 's' + Array.from(crypto.getRandomValues(new Uint8Array(16)),
      byte => byte.toString(16).padStart(2, '0')).join('');
    const command = async (type, extra = {}) => {
      const response = await fetchImpl(streamRoute, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ id, type, ...extra }),
      });
      if (!response.ok) {
        const failure = new Error(`IOS_WEB_STREAM_${type.toUpperCase()}_FAILED: ${response.status}`);
        failure.dshRemoteStreamFailure = { kind: 'carrier' };
        throw failure;
      }
      return response.json();
    };
    const opening = command('open', { endpoint, payload });
    let closed;
    const close = () => closed ??= opening.then(() => command('close'), () => {}).finally(() => openedStreams.delete(close));
    const abort = () => { void close().catch(() => {}); };
    openedStreams.add(close);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    try {
      if ((await opening).opened !== true) throw new TypeError(name);
      for (;;) {
        if (retired) return;
        signal?.throwIfAborted();
        const item = await command('next');
        if (retired) return;
        signal?.throwIfAborted();
        if (item.idle === true) continue;
        if (item.done === true) return;
        if (item.done !== false || !Object.hasOwn(item, 'value')) throw new TypeError(name);
        yield item.value;
      }
    } finally {
      signal?.removeEventListener('abort', abort);
      await close().catch(() => {});
    }
  }
  window.__iosOfficialBridgeClose = async () => {
    retired = true;
    await Promise.allSettled([...openedStreams].map(close => close()));
  };
  window.__DSH_TRANSPORT__ = Object.freeze({ ownsHost: true, fetch: fetchImpl, openStream });
})();
