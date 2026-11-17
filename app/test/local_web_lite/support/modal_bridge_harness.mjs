// Visibility and event contract for the shipped observer, without a browser.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const script = fs.readFileSync('assets/web/dsh_web_modal.js', 'utf8');
const nodes = [];
const messages = [];
const frames = [];
const documentEvents = new Map();
const windowEvents = new Map();
let observeCount = 0;
let mutate;
const html = {};
function node({ role, modal = false, sidebar = false, settings = false, hidden = false, parent = null,
    left = 20, top = 60, width = 300, height = 400, opacity = '1' } = {}) {
  const result = {
    role, modal, settings, hidden, parentElement: parent, isConnected: true,
    rect: { left, top, width, height, right: left + width, bottom: top + height },
    style: { display: 'block', visibility: 'visible', opacity },
    getBoundingClientRect() { return this.rect; },
    matches(selector) {
      assert.equal(selector, '[data-shortcut-modal="sidebar"]');
      return sidebar;
    },
    closest() {
      for (let n = this; n; n = n.parentElement) if (n.hidden) return n;
      return null;
    },
  };
  nodes.push(result);
  return result;
}
const document = {
  documentElement: html,
  querySelectorAll(selector) {
    assert.match(selector, /\[role="dialog"\]/);
    assert.match(selector, /\[aria-modal="true"\]/);
    return nodes.filter((n) => n.role === 'dialog' || n.modal ||
      (n.settings && selector.includes('settings.section')));
  },
  addEventListener(name, callback) { documentEvents.set(name, callback); },
};
const window = {
  DshAppModal: { postMessage(value) { messages.push(value); } },
  addEventListener(name, callback) { windowEvents.set(name, callback); },
};
const context = vm.createContext({
  document, window, innerWidth: 390, innerHeight: 844,
  getComputedStyle: (el) => el.style,
  requestAnimationFrame: (fn) => frames.push(fn),
  MutationObserver: class {
    constructor(fn) { mutate = fn; }
    observe(target, options) {
      assert.equal(target, html);
      assert.equal(options.subtree, true);
      assert.equal(options.childList, true);
      observeCount++;
    }
  },
});
function flush() { while (frames.length) frames.shift()(); }
function check(expected) { flush(); assert.deepEqual(messages, expected); }
vm.runInContext(script, context);
check(['closed']);
vm.runInContext(script, context);
assert.equal(observeCount, 1);
check(['closed']);
// A visible sidebar/menu and an offscreen aria-modal drawer are not dialogs.
node({ role: 'navigation' });
node({ role: 'menu' });
const drawer = node({ role: 'dialog', modal: true, left: -400, width: 300 });
mutate(); check(['closed']);
const hiddenParent = node({ hidden: true });
const hidden = node({ role: 'dialog', parent: hiddenParent });
mutate(); check(['closed']);
// rc2's visible sidebar is explicitly a navigation dialog, not a blocking sheet.
const navigationDrawer = node({ role: 'dialog', modal: true, sidebar: true });
mutate(); check(['closed']);
navigationDrawer.isConnected = false;
// The actual settings dialog becomes visible, then is removed.
const settings = node({ role: 'dialog', modal: true });
mutate(); mutate();
assert.equal(frames.length, 1);
check(['closed', 'open']);
settings.isConnected = false;
mutate(); check(['closed', 'open', 'closed']);
// A valid aria-modal need not repeat role=dialog. A fade begins at opacity 0.
const fade = node({ modal: true, opacity: '0' });
mutate(); check(['closed', 'open', 'closed']);
fade.style.opacity = '1';
documentEvents.get('transitionend')(); check(['closed', 'open', 'closed', 'open']);
fade.isConnected = false;
mutate(); check(['closed', 'open', 'closed', 'open', 'closed']);
// Legacy settings overlays are recognized by their stable settings.section hook.
const legacy = node({ settings: true });
mutate(); check(['closed', 'open', 'closed', 'open', 'closed', 'open']);
legacy.isConnected = false;
mutate(); check(['closed', 'open', 'closed', 'open', 'closed', 'open', 'closed']);
// Resizing can move a dialog into/out of view without changing DOM attributes.
drawer.rect = { left: 10, top: 900, width: 300, height: 400, right: 310, bottom: 1300 };
windowEvents.get('resize')();
check(['closed', 'open', 'closed', 'open', 'closed', 'open', 'closed']);
context.innerHeight = 1400;
windowEvents.get('resize')();
check(['closed', 'open', 'closed', 'open', 'closed', 'open', 'closed', 'open']);
assert.equal(observeCount, 1);
for (const name of ['click', 'submit', 'input', 'change', 'keydown', 'pointerdown']) {
  assert.equal(documentEvents.has(name), false);
  assert.equal(windowEvents.has(name), false);
}
assert.equal(hidden.hidden, false);
process.stdout.write(JSON.stringify({ messages, observeCount, events: [...documentEvents.keys()] }));
