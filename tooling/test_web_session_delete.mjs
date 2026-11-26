// DOM regression for the App-owned dialog and its deletion bridge. Native
// <dialog> layout, touch and focus behavior are checked on the device.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';

const { JSDOM, VirtualConsole } = createRequire(import.meta.url)('jsdom');
const asset = (name) => readFileSync(new URL(`../app/assets/web/${name}`, import.meta.url), 'utf8');
const script = asset('dsh_web_session_delete.js');
const back = asset('dsh_web_back.js');
const selected = 'session-01234567-1234-4321-abcd-0123456789ab';
const target = 'session-89abcdef-1234-4321-abcd-0123456789ab';
const title = '明确显示的目标标题 <b>不是 HTML</b>';

function fixture(t, { resolve = 'row', withBridge = true, menuLabel = '归档会话', throws = false, adapterMode = null, currentId = selected } = {}) {
  const errors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', (err) => errors.push(err));
  const dom = new JSDOM(`<!doctype html><html lang="zh-CN"><body>
    <aside>
      <div data-row-key="session:${selected}" role="treeitem" aria-selected="true">正在打开的其他对话</div>
      <div data-row-key="session:${target}" role="treeitem" tabindex="0">
        <span class="row_title"></span><button data-context-menu-trigger>More</button>
      </div>
    </aside>
    <div id="menu" role="menu"><button role="menuitem"><svg></svg><span>${menuLabel}</span></button></div>
    <div id="sort" role="menu"><button role="menuitem">隐藏已归档</button></div>
  </body></html>`, { url: 'http://127.0.0.1:8080', runScripts: 'outside-only', virtualConsole });
  t.after(() => dom.window.close());
  const w = dom.window, d = w.document, menu = d.getElementById('menu');
  const opener = d.querySelector('[data-context-menu-trigger]');
  const sent = [], frames = [];
  const selectedKey = 'dsh.sessions.current';
  w.localStorage.setItem(selectedKey, JSON.stringify({ sessionId: selected }));
  d.querySelector('.row_title').textContent = title;
  if (resolve === 'row') opener.setAttribute('aria-expanded', 'true');
  if (resolve === 'long-press') opener.parentElement.classList.add('row_menuOpen');
  if (resolve === 'fiber') menu.__reactFiber$fixture = {
    return: { memoizedProps: { target: { kind: 'session', value: { sessionId: target, displayTitle: title } } } },
  };
  if (resolve === 'fiber-only') {
    opener.parentElement.remove();
    menu.__reactFiber$fixture = { memoizedProps: { target: { sessionId: target, displayTitle: title } } };
  }
  const removed = [], listeners = new Set();
  let clears = 0, writes = 0;
  let snapshot = {
    ids: [selected, target],
    byId: Object.fromEntries([selected, target].map(id => [id, { id, retainedBy: id === currentId ? { mainView: 1 } : {} }])),
    projectionsBySession: { [selected]: { keep: true }, [target]: { drop: true } }, phase: 'ready',
  };
  const store = {
    getSnapshot: () => snapshot,
    set(value) { assert.ok(++writes < 25, 'projection should settle, not loop'); snapshot = value; [...listeners].forEach(fn => fn()); },
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
  };
  const workspace = { mainReference: currentId ? { sessionId: currentId } : undefined,
    clearMain() { clears++; this.mainReference = undefined; } };
  const sessions = { list: store,
    retainInfo: id => ({ getSnapshot: () => ({ retainedBy: workspace.mainReference?.sessionId === id ? { mainView: 1 } : {} }) }),
    handleSessionRemoved(id) {
      removed.push(id);
      const byId = { ...snapshot.byId }; delete byId[id];
      store.set({ ...snapshot, ids: snapshot.ids.filter(key => key !== id), byId });
    },
  };
  if (adapterMode) {
    const scope = { memoizedProps: { value: { hooks: { sessions: store }, keyedHooks: {}, props: {},
      ...(adapterMode === 'scoped' ? { ctx: { get: key => ({ sessions, uiWorkspace: workspace })[key] } } : {}),
    } } };
    let fiber = menu.__reactFiber$fixture;
    if (!fiber) menu.__reactFiber$fixture = scope;
    else { while (fiber.return) fiber = fiber.return; fiber.return = scope; }
  }
  if (withBridge) w.DshAppSessionDelete = { postMessage(message) {
    if (throws) throw Error('unavailable');
    sent.push(JSON.parse(message));
  } };
  w.DshAppSessions = { postMessage() {
    w.__dshAppSessionsList({ projects: { project: [selected, target] } });
  } };
  w.confirm = w.alert = () => assert.fail('No browser prompt should be used');
  w.requestAnimationFrame = (fn) => frames.push(fn);
  w.HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', ''); };
  w.HTMLDialogElement.prototype.close = function () { this.removeAttribute('open'); };
  w.HTMLElement.prototype.getClientRects = function () { return this.isConnected ? [{}] : []; };
  w.CSS ??= {};
  w.CSS.escape ??= (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, '\\$&');
  w.PointerEvent ??= w.MouseEvent;
  let outside = 0;
  // Mirror the upstream menu's outside-pointer behavior, preserving its own
  // focus restoration and simulating removal before the confirmation opens.
  d.addEventListener('pointerdown', (event) => {
    if (event.target === d.body) {
      outside++;
      opener.removeAttribute('aria-expanded');
      menu.remove();
    }
  });
  function flush() { while (frames.length) frames.shift()(); }
  w.eval(back);
  w.eval(script);
  w.eval(script);
  flush();
  return { w, d, opener, selectedKey, sent, errors, flush, store, workspace, removed, listeners,
    get clears() { return clears; },
    get outside() { return outside; },
    get dialog() { return d.querySelector('dialog[open]'); },
    get submit() { return d.querySelector('.dsh-session-dialog-submit'); },
    get dismiss() { return d.querySelector('[data-dsh-session-dismiss]'); },
    open() {
      const rows = menu.querySelectorAll('[data-dsh-app-delete]');
      assert.equal(rows.length, 1);
      assert.equal(d.getElementById('sort').querySelector('[data-dsh-app-delete]'), null);
      rows[0].click();
      assert.equal(errors.length, 0, errors.map(String).join('\n'));
      assert.ok(this.dialog);
    },
  };
}

test('the displayed target is the clicked row, not the selected conversation', (t) => {
  const h = fixture(t);
  h.open();
  assert.equal(h.outside, 1);
  const targetLabel = h.dialog.querySelector('.dsh-session-dialog-target');
  assert.equal(targetLabel.textContent, title);
  assert.equal(targetLabel.childElementCount, 0);
  assert.match(h.dialog.textContent, /永久删除.*无法恢复.*归档/);
  assert.equal(h.dialog.getAttribute('aria-modal'), 'true');
  assert.equal(h.d.activeElement, h.dismiss);
  h.dismiss.click();
  h.flush();
  assert.equal(h.dialog, null);
  assert.equal(h.d.activeElement, h.opener);
  assert.deepEqual(h.sent, []);
});

for (const resolve of ['fiber', 'fiber-only', 'long-press']) {
  test(`an archived conversation resolves through ${resolve}`, (t) => {
    const h = fixture(t, { resolve, menuLabel: '取消归档' });
    h.open();
    assert.equal(h.dialog.querySelector('.dsh-session-dialog-target').textContent, title);
    h.submit.click();
    assert.deepEqual(h.sent, [{ project: 'project', sessionId: target }]);
  });
}

test('an unowned menu displays an error rather than guessing at the selected row', (t) => {
  const h = fixture(t, { resolve: 'none' });
  h.open();
  assert.match(h.dialog.textContent, /未识别到/);
  assert.equal(h.submit, null);
  h.dismiss.click();
  assert.deepEqual(h.sent, []);
});

for (const method of ['back bridge', 'Escape', 'cancel event']) {
  test(`${method} closes the dialog without sending deletion`, (t) => {
    const h = fixture(t);
    h.open();
    if (method === 'back bridge') {
      assert.equal(h.w.__dshAppBack(true), 'layer');
      assert.ok(h.dialog);
      assert.equal(h.w.__dshAppBack(), 'layer');
    } else if (method === 'Escape') {
      h.dismiss.dispatchEvent(new h.w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    } else {
      h.dialog.dispatchEvent(new h.w.Event('cancel', { cancelable: true }));
    }
    assert.equal(h.dialog, null);
    assert.deepEqual(h.sent, []);
  });
}

test('confirm sends once, preserves another selected session, and shows errors inline', (t) => {
  const h = fixture(t);
  h.open();
  assert.deepEqual(h.sent, []);
  h.submit.click();
  h.submit.click();
  assert.deepEqual(h.sent, [{ project: 'project', sessionId: target }]);
  assert.equal(h.submit.disabled, true);
  assert.equal(h.dismiss.textContent, '关闭');
  h.w.__dshAppSessionDeleted({ ok: false, sessionId: selected, message: 'unrelated' });
  assert.equal(h.submit.disabled, true);
  h.w.__dshAppSessionDeleted({ ok: false, sessionId: target, message: '刷新后重试' });
  assert.equal(h.submit.disabled, false);
  assert.equal(h.dismiss.textContent, '取消');
  assert.equal(h.dialog.querySelector('[role=status]').textContent, '刷新后重试');
  assert.equal(JSON.parse(h.w.localStorage.getItem(h.selectedKey)).sessionId, selected);
  assert.deepEqual(h.errors, []);
});

test('a broken bridge displays an inline error instead of a system alert', (t) => {
  const h = fixture(t, { throws: true });
  h.open();
  h.submit.click();
  assert.equal(h.submit.disabled, false);
  assert.match(h.dialog.querySelector('[role=status]').textContent, /刷新会话列表/);
  assert.deepEqual(h.errors, []);
});

test('a page without the Android deletion channel does not gain the destructive menu', (t) => {
  const h = fixture(t, { withBridge: false });
  assert.equal(h.d.querySelector('[data-dsh-app-delete]'), null);
});

for (const currentId of [target, selected]) {
  test(`success updates the observable list without reloading (current=${currentId === target ? 'target' : 'other'})`, (t) => {
    const h = fixture(t, { adapterMode: 'scoped', currentId });
    h.open(); h.submit.click();
    h.w.__dshAppSessionDeleted({ ok: true, sessionId: target });
    assert.deepEqual(h.removed, [target]);
    assert.equal(h.clears, currentId === target ? 1 : 0);
    assert.equal(h.workspace.mainReference?.sessionId, currentId === target ? undefined : selected);
    assert.equal(h.store.getSnapshot().byId[target], undefined);
    assert.deepEqual(Array.from(h.store.getSnapshot().ids), [selected]);
    assert.equal(h.dialog, null);
    assert.deepEqual(h.errors, []); // jsdom reports any location.reload() here.
  });
}

test('navigation while deleting is not replaced by a stale selection', (t) => {
  const h = fixture(t, { adapterMode: 'scoped', currentId: target });
  h.open(); h.submit.click();
  h.workspace.mainReference = { sessionId: selected };
  h.w.__dshAppSessionDeleted({ ok: true, sessionId: target });
  assert.equal(h.clears, 0);
  assert.equal(h.workspace.mainReference.sessionId, selected);
  assert.deepEqual(h.errors, []);
});

test('root-only projection excludes only acknowledged IDs and does not notify forever', (t) => {
  const h = fixture(t, { adapterMode: 'root', currentId: null });
  h.open();
  const before = h.store.getSnapshot();
  h.w.__dshAppSessionDeleted({ ok: true, sessionId: target }); // unsolicited: ignored
  assert.equal(h.store.getSnapshot(), before);
  h.submit.click();
  h.w.__dshAppSessionDeleted({ ok: true, sessionId: target });
  assert.equal(h.dialog, null);
  assert.equal(h.store.getSnapshot().byId[target], undefined);
  assert.equal(h.store.getSnapshot().byId[selected], before.byId[selected]);
  assert.equal(h.store.getSnapshot().projectionsBySession[selected], before.projectionsBySession[selected]);
  h.store.set(before); // A subsequent upstream metadata publication.
  assert.deepEqual(Array.from(h.store.getSnapshot().ids), [selected]);
  assert.equal(h.store.getSnapshot().byId[target], undefined);
  assert.equal(h.clears, 0);
  assert.equal(h.listeners.size, 1);
  h.w.dispatchEvent(new h.w.PageTransitionEvent('pagehide', { persisted: true }));
  assert.equal(h.listeners.size, 0);
  h.store.set(before);
  h.w.dispatchEvent(new h.w.PageTransitionEvent('pageshow', { persisted: true }));
  assert.equal(h.listeners.size, 1);
  assert.equal(h.store.getSnapshot().byId[target], undefined);
  assert.deepEqual(h.errors, []);
});

test('an unfamiliar renderer acknowledges success without offering delete again or reloading', (t) => {
  const h = fixture(t);
  h.open(); h.submit.click();
  h.w.__dshAppSessionDeleted({ ok: true, sessionId: target });
  assert.match(h.dialog.textContent, /对话已删除/);
  assert.equal(h.submit, null);
  assert.equal(h.dismiss.textContent, '关闭');
  assert.deepEqual(h.errors, []);
});
