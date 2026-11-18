(() => {
  // Official main.ts replaces __DSH_TRANSPORT__ only for dshDesktopBoot, so the
  // page-world hook must exist before any official script evaluates.
  const handler = window.webkit?.messageHandlers?.dshBridge;
  const name = 'IOS_WEB_TRANSPORT_UNAVAILABLE';
  const blocked = () => Promise.reject(new TypeError(name));
  if (!handler || typeof handler.postMessage !== 'function') {
    window.__DSH_TRANSPORT__ = Object.freeze({ ownsHost: true, fetch: blocked, openStream: blocked });
    return;
  }
  const send = (frame) => handler.postMessage(frame);
  const fetchImpl = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url, 'dsh-app://bundle/');
    if (url.protocol !== 'dsh-app:' || url.host !== 'bundle' || url.port || url.username || url.password) {
      return blocked();
    }
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
    const reply = await send({
      type: 'request', method: request.method, path: `${url.pathname}${url.search}`, headers, body,
    });
    if (!reply || typeof reply.status !== 'number') throw new TypeError('IOS_WEB_TRANSPORT_FAILED');
    const raw = typeof reply.body === 'string' ? atob(reply.body) : '';
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return new Response(bytes, { status: reply.status, headers: reply.headers ?? {} });
  };
  window.__DSH_TRANSPORT__ = Object.freeze({
    ownsHost: true,
    fetch: fetchImpl,
    openStream: () => blocked(),
  });
})();
