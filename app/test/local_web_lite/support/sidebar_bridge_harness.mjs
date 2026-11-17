import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// The shipped sidebar bridge, run against a model of the page. What is checked
// is the state the app's whale hides on: the official drawer, Lite's own
// drawer, a replaced frame, and the forced re-check the page needs after a load.
// Just as important: a drawer mask or a panel container that merely exists in
// the document must not read as open — that hid the whale for good.
const source = fs.readFileSync('assets/web/dsh_web_sidebar.js', 'utf8');

const messages = [];
const window = { DshAppSidebar: { postMessage: (m) => messages.push(m) }, addEventListener() {} };
const callbacks = new Map();
let observes = 0;
const htmlAttrs = new Set(['data-dsh-app-lite', 'data-dsh-app-layout']);
let layout = 'drawer';
const documentElement = {
  hasAttribute: (name) => htmlAttrs.has(name),
  getAttribute: (name) => (name === 'data-dsh-app-layout' ? layout : null),
  addEventListener() {},
};
const frameAttrs = new Set(['data-sidebar-drawer', 'data-sidebar-collapsed']);
// Off-screen or shell-only nodes: present, sized, yet not a drawer state.
const mask = { getBoundingClientRect: () => ({ width: 100, height: 100 }) };
const panel = {};
const frame = {
  hasAttribute: (name) => frameAttrs.has(name),
  querySelector: (selector) => (selector === '[class*="_drawerMask"]' ? mask : null),
};
const root = {};
const document = {
  documentElement,
  querySelector: (selector) => {
    if (selector === '[data-slot="root"]') return root;
    if (selector === '[data-slot="root"] > [class*="_frame"]') return frame;
    if (selector === '[data-sidebar-right-panel="fullscreen"]') return panel;
    return null;
  },
  addEventListener() {},
  visibilityState: 'visible',
};

const context = vm.createContext({
  window,
  document,
  MutationObserver: class {
    constructor(fn) { this.fn = fn; }
    observe(target) { callbacks.set(target, this.fn); observes++; }
    disconnect() {}
  },
  getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
});
const update = () => callbacks.get(frame)?.();
const install = () => vm.runInContext(source, context);

install();
assert.deepEqual(messages, [], 'a closed drawer says nothing at install');

// Neither a sized mask nor a mounted panel container counts while the drawer
// attributes say closed. Reading them as state is what made the marker vanish.
assert.equal(mask.getBoundingClientRect().width, 100);
update();
assert.deepEqual(messages, [], 'a mask or panel in the document is not an open drawer');

// The official drawer, by its attributes.
frameAttrs.delete('data-sidebar-collapsed');
update();
assert.deepEqual(messages, ['open']);
frameAttrs.add('data-sidebar-collapsed');
update();
assert.deepEqual(messages, ['open', 'closed']);

// Lite's own drawer (the app's attribute), and back.
frameAttrs.delete('data-sidebar-drawer');
frameAttrs.add('data-dsh-app-drawer');
update();
assert.equal(messages.at(-1), 'open');
frameAttrs.delete('data-dsh-app-drawer');
update();
assert.equal(messages.at(-1), 'closed');

// Idempotent: a second injection adds nothing.
const before = observes;
install();
assert.equal(observes, before, 're-injection must not stack observers');

// A forced re-report is sent even when the state did not change: this is what
// the app calls after a load, on resume, and after its own toggle.
messages.length = 0;
window.__dshAppSidebar(true);
assert.deepEqual(messages, ['closed'], 'forced report always posts');

// The same call without an argument still only reports a change.
messages.length = 0;
window.__dshAppSidebar();
assert.deepEqual(messages, []);

// A frame replaced by the page: the observer follows the new one, and a drawer
// already open there is reported instead of leaving the marker up.
const replacement = {
  hasAttribute: (name) => name === 'data-dsh-app-drawer',
  querySelector: () => null,
};
document.querySelector = (selector) => {
  if (selector === '[data-slot="root"]') return root;
  if (selector === '[data-slot="root"] > [class*="_frame"]') return replacement;
  return null;
};
frameAttrs.delete('data-sidebar-drawer');
frameAttrs.delete('data-dsh-app-drawer');
messages.length = 0;
window.__dshAppSidebar(true);
assert.deepEqual(messages, ['open'], 'the new frame with the drawer open is reported');

// Without Lite the app's own attribute is not a signal, as in the full edition.
htmlAttrs.delete('data-dsh-app-lite');
messages.length = 0;
window.__dshAppSidebar(true);
assert.deepEqual(messages, ['closed'], 'the full edition keeps ignoring the adapted drawer');

// Its official, non-adapted phone drawer is still reported normally.
layout = null;
document.querySelector = (selector) => (selector === '[data-slot="root"] > [class*="_frame"]' ? frame : null);
frameAttrs.add('data-sidebar-drawer');
frameAttrs.delete('data-sidebar-collapsed');
messages.length = 0;
window.__dshAppSidebar(true);
assert.deepEqual(messages, ['open']);

console.log('Sidebar bridge passed: official/Lite drawers, no false open from mask or panel shells, forced re-sync, frame replacement, full compatibility.');
