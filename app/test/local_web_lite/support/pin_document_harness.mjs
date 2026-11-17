// Execute the shipped phone-layout script and generated inset script on the
// LAN proxy's plain POST form (no React #root). No browser or network is used.
// This model checks DOM/event preservation, not CSS pixel layout in Android.
import fs from 'node:fs';
import vm from 'node:vm';

const variants = JSON.parse(process.argv[2]);
const phone = fs.readFileSync('assets/web/dsh_web_phone.js', 'utf8');
const out = [];
for (const variant of variants) {
  const nodes = new Map();
  const attrs = new Map();
  const listeners = new Map();
  const prevented = [];
  const stopped = [];
  let readsLocalStorage = 0;
  const form = { tagName: 'FORM', action: '/_remote/login', method: 'post', closest: () => null };
  const pin = {
    tagName: 'INPUT', name: 'pin', value: 'TESTPIN123', type: 'text',
    closest: () => null, getBoundingClientRect: () => ({ top: 300, bottom: 344 }),
    scrollIntoView() {},
  };
  const html = {
    style: {},
    getAttribute: (key) => attrs.get(key) ?? null,
    hasAttribute: (key) => attrs.has(key),
    setAttribute: (key, value) => attrs.set(key, value),
    removeAttribute: (key) => attrs.delete(key),
    toggleAttribute(key, force) {
      if (force) attrs.set(key, '');
      else attrs.delete(key);
    },
  };
  const document = {
    documentElement: html,
    body: { style: {}, children: [form] },
    activeElement: pin,
    head: { appendChild(node) { nodes.set(node.id, node); } },
    getElementById: (id) => nodes.get(id) ?? null,
    createElement: (tagName) => ({ tagName, textContent: '' }),
    querySelector(selector) {
      if (selector === 'form') return form;
      if (selector === 'input' || selector === 'input[name="pin"]') return pin;
      return null;
    },
    querySelectorAll() { return []; },
    addEventListener(name, callback) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(callback);
    },
  };
  const windowListeners = new Map();
  const window = {
    matchMedia: () => ({ addEventListener() {} }),
    addEventListener(name, callback) {
      if (!windowListeners.has(name)) windowListeners.set(name, []);
      windowListeners.get(name).push(callback);
    },
    dispatchEvent(event) {
      for (const callback of windowListeners.get(event.type) ?? []) callback(event);
      return true;
    },
  };
  const context = vm.createContext({
    document, window, innerHeight: 844, innerWidth: 390,
    getComputedStyle: () => ({ backgroundColor: 'rgb(255, 255, 255)', getPropertyValue: () => '' }),
    MutationObserver: class { observe() {} },
    requestAnimationFrame: (callback) => callback(),
    // The drawer's bounded settle timer can wait: no shell frame exists here.
    setTimeout: () => 1,
    clearTimeout() {},
    localStorage: {
      getItem() { readsLocalStorage++; throw new Error('phone_layout_read_local_session'); },
      setItem() { throw new Error('phone_layout_wrote_local_session'); },
    },
  });
  vm.runInContext(variant.script, context);
  vm.runInContext(phone, context);
  // Reinjection is expected after viewport changes and must remain idempotent.
  vm.runInContext(variant.script, context);
  vm.runInContext(phone, context);
  for (const type of ['focusin', 'pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchend', 'click', 'submit']) {
    const event = {
      type, target: type === 'submit' ? form : pin, clientX: 180,
      preventDefault() { prevented.push(type); },
      stopPropagation() { stopped.push(type); },
    };
    for (const callback of listeners.get(type) ?? []) callback(event);
  }
  out.push({
    action: form.action, method: form.method, pin: pin.value,
    prevented, stopped, readsLocalStorage,
    bodyInsets: nodes.get('dsh-app-insets')?.textContent ?? '',
    keyboardSheet: nodes.get('dsh-app-keyboard')?.textContent ?? '',
    seatSheet: nodes.get('dsh-app-seat')?.textContent ?? '',
  });
}
process.stdout.write(JSON.stringify(out));
