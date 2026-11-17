// DOM/input regression, not a browser scrolling or Android WebView test.
// Requires jsdom 27.4.0; reuse a tool installation with NODE_PATH=<prefix>/node_modules.
// NODE_PATH=... node --test tooling/test_web_swipe.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';
const { JSDOM } = createRequire(import.meta.url)('jsdom');
const sourceDir = process.env.DSH_SWIPE_SOURCE_DIR;
const phone = readFileSync(sourceDir ? `${sourceDir}/dsh_web_phone.js` : new URL('../app/assets/web/dsh_web_phone.js', import.meta.url), 'utf8');
const back = readFileSync(sourceDir ? `${sourceDir}/dsh_web_back.js` : new URL('../app/assets/web/dsh_web_back.js', import.meta.url), 'utf8');

function fixture(t, { official = true, layout = 'drawer' } = {}) {
  const dom = new JSDOM(`<!doctype html><html data-dsh-app-layout="${layout}"><body>
    <div data-slot="root"><div class="test_frame" data-sidebar-collapsed data-rightbar-collapsed ${official ? 'data-sidebar-drawer' : ''}>
      <div class="test_sidebarCol" ${official ? 'inert' : ''}><aside data-slot="sidebar"><div class="test_sidebarRoot" ${official ? 'role="dialog" data-shortcut-modal="sidebar"' : ''}><div class="test_logoRow"><button class="test_iconButton">Toggle</button></div>
        <div role="treeitem" class="test_sessionRow" data-row-key="session:s1">Chat</div></div></aside></div>
      <main data-slot="main"><div data-slot="main.conversation"><p id="content">Conversation</p></div></main>
      <aside data-slot="rightbar"><button data-sidebar-right-toggle>Close files</button></aside>
    </div></div></body></html>`, { url: 'https://fixture.invalid', runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const w = dom.window, d = w.document;
  w.matchMedia = () => ({ addEventListener() {} });
  w.requestAnimationFrame = () => 0;
  w.CSS = { escape: v => String(v) };
  w.PointerEvent = w.MouseEvent;
  // jsdom has no layout. Visibility/overflow geometry is explicit fixture data.
  w.HTMLElement.prototype.getClientRects = function () { return this.isConnected && !this.hidden ? [{}] : []; };
  let clock = 1000;
  w.Date.now = () => clock;
  const frame = d.querySelector('.test_frame'), main = d.querySelector('main');
  const row = d.querySelector('[role=treeitem]');
  d.querySelector('.test_iconButton').addEventListener('click', () => {
    const closed = frame.toggleAttribute('data-sidebar-collapsed');
    if (official) {
      const dialog = d.querySelector('[data-shortcut-modal="sidebar"]');
      if (closed) dialog.removeAttribute('aria-modal');
      else dialog.setAttribute('aria-modal', 'true');
      d.querySelector('.test_sidebarCol').toggleAttribute('inert', closed);
    }
  });
  row.addEventListener('click', () => { main.innerHTML = '<div data-slot="main.conversation"><p id="content">Conversation</p></div>'; });
  d.querySelector('[data-sidebar-right-toggle]').addEventListener('click', () => frame.removeAttribute('data-rightbar-fullscreen'));
  w.localStorage.setItem('dsh.sessions.current', JSON.stringify({ sessionId: 's1' }));
  w.eval(back); w.eval(phone);
  const app = w.__dshApp, backFn = w.__dshAppBack;
  w.eval(back); w.eval(phone);
  assert.equal(app, w.__dshApp);
  assert.equal(backFn, w.__dshAppBack);
  function touch(target, type, x, y = 200, { count = 1, cancelable = true, id = 7 } = {}) {
    const point = { identifier: id, clientX: x, clientY: y };
    const event = new w.Event(type, { bubbles: true, cancelable });
    const points = count === 1 ? [point] : count === 0 ? [] : [point, { identifier: 9, clientX: x + 10, clientY: y }];
    Object.defineProperties(event, {
      touches: { value: type === 'touchend' || type === 'touchcancel' ? [] : points },
      changedTouches: { value: points },
    });
    target.dispatchEvent(event);
    return event;
  }
  function swipe({ target = main, x = 100, dx = 100, dy = 0, duration = 180, cancel = false, moveCancelable = true } = {}) {
    const start = touch(target, 'touchstart', x);
    clock += duration / 2;
    const move = touch(target, 'touchmove', x + dx * 0.7, 200 + dy * 0.7, { cancelable: moveCancelable });
    clock += duration / 2;
    const end = touch(target, cancel ? 'touchcancel' : 'touchend', x + dx, 200 + dy);
    return { start, move, end };
  }
  function layer(role = 'dialog') {
    const el = d.createElement('div');
    el.setAttribute('role', role);
    if (role === 'dialog') el.setAttribute('aria-modal', 'true');
    el.textContent = 'Overlay'; d.body.append(el);
    el.addEventListener('keydown', e => { if (e.key === 'Escape') el.remove(); });
    d.addEventListener('keydown', e => { if (e.key === 'Escape' && el.isConnected) el.remove(); }, { once: true });
    return el;
  }
  return { w, d, frame, main, row, app, touch, swipe, layer, tick: n => { clock += n; } };
}

for (const official of [true, false]) test(`${official ? 'official' : 'app'} drawer: right opens, left closes, reinjection stays idempotent`, t => {
  const h = fixture(t, { official });
  assert.equal(h.app.sidebarOpen(), false);
  assert.equal(h.w.__dshAppBack(true), 'none', 'a folded sidebar dialog is not a popup');
  const first = h.swipe();
  assert.equal(first.start.defaultPrevented, false);
  assert.equal(first.move.defaultPrevented, true);
  assert.equal(h.app.sidebarOpen(), true);
  assert.equal(h.w.__dshAppBack(true), 'drawer', 'an open sidebar dialog is not a modal layer');
  h.swipe({ target: h.row, x: 250, dx: -100 });
  assert.equal(h.app.sidebarOpen(), false);
});

for (const [name, args] of [
  ['short drag', { dx: 40 }], ['vertical scroll', { dx: 15, dy: 120 }],
  ['diagonal scroll', { dx: 90, dy: 100 }], ['wrong direction', { dx: -100 }],
  ['long press', { duration: 1400 }], ['cancelled touch', { cancel: true }],
  ['browser-owned scroll', { moveCancelable: false }],
]) test(`${name} does not navigate`, t => {
  const h = fixture(t); h.swipe(args); assert.equal(h.app.sidebarOpen(), false);
});

for (const layout of ['drawer', 'desktop']) test(`Back closes the official sidebar through its own toggle (${layout})`, t => {
  const h = fixture(t, { layout }); h.app.toggleSidebar();
  assert.equal(h.w.__dshAppBack(true), 'drawer');
  assert.equal(h.w.__dshAppBack(), 'drawer');
  assert.equal(h.app.sidebarOpen(), false);
  assert.equal(h.w.__dshAppBack(true), 'none');
});

test('a real popup inside the sidebar still takes priority over the drawer', t => {
  const h = fixture(t); h.app.toggleSidebar();
  const popup = h.d.createElement('div'); popup.setAttribute('role', 'dialog');
  h.d.querySelector('[data-shortcut-modal="sidebar"]').append(popup);
  assert.equal(h.w.__dshAppBack(true), 'popup');
  h.swipe({ target: h.row, dx: -100 }); assert.equal(h.app.sidebarOpen(), true);
  popup.remove();
  h.swipe({ target: h.row, dx: -100 }); assert.equal(h.app.sidebarOpen(), false);
});

test('right swipe on an open drawer leaves it open', t => {
  const h = fixture(t); h.app.toggleSidebar(); h.swipe({ target: h.row }); assert(h.app.sidebarOpen());
});

test('desktop layout keeps its original touch behavior', t => {
  const h = fixture(t, { layout: 'desktop' }); h.swipe(); assert.equal(h.app.sidebarOpen(), false);
});

test('plugin page returns to the selected conversation before opening the sidebar', t => {
  const h = fixture(t); h.main.innerHTML = '<section>Plugins</section>';
  assert.equal(h.w.__dshAppBack(true), 'chat');
  h.swipe(); assert(h.main.querySelector('[data-slot="main.conversation"]')); assert.equal(h.app.sidebarOpen(), false);
  h.swipe(); assert.equal(h.app.sidebarOpen(), true);
});

test('nested plugin page takes one crumb only', t => {
  const h = fixture(t); h.main.innerHTML = '<section><button class="test_crumb">Plugins</button><p>Detail</p></section>';
  h.main.querySelector('button').onclick = () => { h.main.innerHTML = '<section>Plugins</section>'; };
  h.swipe(); assert.equal(h.main.textContent, 'Plugins'); assert.equal(h.app.sidebarOpen(), false);
});

test('fullscreen files panel closes before the chat drawer opens', t => {
  const h = fixture(t); h.frame.setAttribute('data-rightbar-fullscreen', 'true');
  h.swipe({ target: h.d.querySelector('[data-slot=rightbar]') });
  assert.equal(h.frame.hasAttribute('data-rightbar-fullscreen'), false); assert.equal(h.app.sidebarOpen(), false);
});

test('settings above the drawer closes first; left swipe leaves the overlay alone', t => {
  const h = fixture(t); h.app.toggleSidebar(); const el = h.layer();
  h.swipe({ target: el, dx: -100 }); assert(el.isConnected); assert(h.app.sidebarOpen());
  h.swipe({ target: el }); assert.equal(el.isConnected, false); assert(h.app.sidebarOpen());
});

test('Back preview does not blur, spend attempts or dismiss a dialog', t => {
  const h = fixture(t); const el = h.layer(); const editor = h.d.createElement('input'); el.append(editor); editor.focus();
  for (let i = 0; i < 5; i++) assert.equal(h.w.__dshAppBack(true), 'layer');
  assert.equal(h.d.activeElement, editor); assert(el.isConnected);
  assert.equal(h.w.__dshAppBack(), 'layer'); assert.equal(el.isConnected, false);
});

for (const html of ['<input>', '<textarea></textarea>', '<select></select>', '<div contenteditable="true"><span>edit</span></div>',
  '<div role="slider"></div>', '<nav role="tablist"></nav>', '<canvas></canvas>', '<div class="xterm"></div>', '<div data-dsh-no-swipe></div>']) {
  test(`interactive surface keeps its gesture: ${html}`, t => {
    const h = fixture(t); h.main.innerHTML = html; const target = h.main.firstElementChild;
    const result = h.swipe({ target }); assert.equal(h.app.sidebarOpen(), false); assert.equal(result.move.defaultPrevented, false);
  });
}

test('horizontal code/table scrolling keeps its gesture even at the scroll boundary', t => {
  const h = fixture(t); h.main.innerHTML = '<pre style="overflow-x:auto"><code>long code</code></pre>';
  const pre = h.main.firstElementChild;
  Object.defineProperties(pre, { clientWidth: { value: 200 }, scrollWidth: { value: 600 } });
  const result = h.swipe({ target: pre.firstElementChild });
  assert.equal(result.move.defaultPrevented, false); assert.equal(h.app.sidebarOpen(), false);
});

test('text selection and multitouch never navigate', t => {
  const h = fixture(t); const selection = h.w.getSelection(); selection.selectAllChildren(h.main);
  h.swipe(); assert.equal(h.app.sidebarOpen(), false); selection.removeAllRanges();
  h.touch(h.main, 'touchstart', 100); h.touch(h.main, 'touchmove', 170);
  h.touch(h.main, 'touchstart', 170, 200, { count: 2 }); h.touch(h.main, 'touchend', 230);
  assert.equal(h.app.sidebarOpen(), false);
});

test('vertical-first or reversed gestures do not navigate', t => {
  const h = fixture(t);
  h.touch(h.main, 'touchstart', 100); h.touch(h.main, 'touchmove', 102, 240); h.touch(h.main, 'touchmove', 230, 240); h.touch(h.main, 'touchend', 230, 240);
  assert.equal(h.app.sidebarOpen(), false);
  h.touch(h.main, 'touchstart', 100); h.touch(h.main, 'touchmove', 180); h.touch(h.main, 'touchend', 50);
  assert.equal(h.app.sidebarOpen(), false);
});

test('navigation state changes, rotation and frame replacement cancel pending actions', t => {
  for (const change of [h => h.layer(), h => h.app.toggleSidebar(), h => h.w.dispatchEvent(new h.w.Event('resize')), h => h.frame.replaceWith(h.frame.cloneNode(true))]) {
    const h = fixture(t); h.touch(h.main, 'touchstart', 100); h.touch(h.main, 'touchmove', 170);
    change(h); const before = h.app.sidebarOpen(); h.touch(h.main, 'touchend', 230);
    assert.equal(h.app.sidebarOpen(), before);
  }
});

test('a claimed short swipe suppresses only its generated click, then a fresh tap works', t => {
  const h = fixture(t); const button = h.d.createElement('button'); h.main.append(button); let clicks = 0;
  button.addEventListener('click', () => clicks++);
  h.swipe({ target: button, dx: 40 }); button.dispatchEvent(new h.w.MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }));
  assert.equal(clicks, 0);
  h.touch(button, 'touchstart', 100); h.touch(button, 'touchend', 100);
  button.dispatchEvent(new h.w.MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 })); assert.equal(clicks, 1);
});
