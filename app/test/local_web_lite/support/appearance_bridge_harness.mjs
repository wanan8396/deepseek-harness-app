// The shipped appearance observer must report only a light/dark bit.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const script = fs.readFileSync('assets/web/dsh_web_appearance.js', 'utf8');
const html = {};
let dark = false, observeCount = 0, mutate;
const messages = [];
const document = {
  documentElement: html,
  body: { hasAttribute(name) { assert.equal(name, 'data-ds-dark-theme'); return dark; } },
};
const window = { DshAppAppearance: { postMessage: value => messages.push(value) } };
const context = vm.createContext({
  document, window,
  MutationObserver: class {
    constructor(callback) { mutate = callback; }
    observe(target, options) {
      assert.equal(target, html);
      assert.equal(options.subtree, true);
      assert.equal(options.childList, true);
      assert.deepEqual(Array.from(options.attributeFilter), ['data-ds-dark-theme']);
      observeCount++;
    }
  },
});
vm.runInContext(script, context);
assert.deepEqual(messages, ['light']);
mutate();
assert.deepEqual(messages, ['light']);
dark = true; mutate();
assert.deepEqual(messages, ['light', 'dark']);
vm.runInContext(script, context);
assert.equal(observeCount, 1);
assert.deepEqual(messages, ['light', 'dark']);
document.body = null; mutate();
assert.deepEqual(messages, ['light', 'dark']);
document.body = { hasAttribute: () => false }; mutate();
assert.deepEqual(messages, ['light', 'dark', 'light']);
// Detachment and reattachment must not advance the last successful report.
window.DshAppAppearance = null; dark = true;
document.body = { hasAttribute: () => dark }; mutate();
assert.deepEqual(messages, ['light', 'dark', 'light']);
window.DshAppAppearance = { postMessage: value => messages.push(value) }; mutate();
assert.deepEqual(messages, ['light', 'dark', 'light', 'dark']);
assert.ok(messages.every(value => value === 'light' || value === 'dark'));
console.log('Appearance observer contract passed: themes, duplicates, body replacement and channel reconnection.');
