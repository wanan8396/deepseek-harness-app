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

function fixture(t, { resolve = 'row', withBridge = true, menuLabel = '归档会话', throws = false } = {}) {
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
  return { w, d, opener, selectedKey, sent, errors, flush,
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
