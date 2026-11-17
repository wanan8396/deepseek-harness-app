import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const source = readFileSync(new URL('../app/assets/web/dsh_web_settings_document.js', import.meta.url), 'utf8').replace('__DSH_SETTINGS_DOCUMENT_NONCE__', JSON.stringify('fixture-nonce'));
function harness({ frame = false, channel = true } = {}) {
  let handler; const sent = [];
  const document = { addEventListener: (_t, f) => { handler = f; }, removeEventListener: () => { handler = null; } };
  const window = { document }; window.top = frame ? {} : window;
  if (channel) window.DshAppSettingsDocument = { postMessage: value => sent.push(value) };
  runInNewContext(source, { window, document });
  return { sent, window, click({ trusted = true, disabled = false, scoped = true, label = '打开配置文件', child = false } = {}) {
    let prevented = false; let stopped = false;
    const button = { disabled, textContent: label, matches: selector => {
      assert.equal(selector, '[data-shortcut-modal="settings"][role="dialog"] [data-slot="settings.action"] button'); return scoped;
    }, closest: () => button };
    const target = child ? { closest: () => button } : button;
    handler?.({ isTrusted: trusted, target, preventDefault() { prevented = true; }, stopImmediatePropagation() { stopped = true; } });
    return { prevented, stopped };
  } };
}
test('real scoped button clicks request only a nonce and suppress the desktop action', () => {
  const h = harness(); assert.deepEqual(h.click({ child: true }), { prevented: true, stopped: true });
  assert.deepEqual(h.sent, ['fixture-nonce']);
});
test('all eight official action labels are recognized exactly', () => {
  for (const label of ['打开配置文件', 'Open configuration file', 'Abrir archivo de configuración', 'Ouvrir le fichier de configuration',
    'Konfigurationsdatei öffnen', '設定ファイルを開く', 'Открыть файл конфигурации', 'Abra o arquivo de configuração']) {
    const h = harness(); h.click({ label }); assert.deepEqual(h.sent, ['fixture-nonce']);
  }
});
for (const [name, input] of [['script click', { trusted: false }], ['disabled action', { disabled: true }],
  ['unrelated button', { label: 'Save' }], ['outside settings', { scoped: false }], ['partial label', { label: '打开配置文件 extra' }]]) {
  test(`${name} keeps the original action`, () => {
    const h = harness(); assert.deepEqual(h.click(input), { prevented: false, stopped: false }); assert.deepEqual(h.sent, []);
  });
}
test('frames and a missing bridge are not intercepted', () => {
  for (const input of [{ frame: true }, { channel: false }]) {
    const h = harness(input); assert.deepEqual(h.click(), { prevented: false, stopped: false }); assert.deepEqual(h.sent, []);
  }
});
test('disposal removes the old page handler', () => {
  const h = harness(); h.window.__dshSettingsDocumentDispose(); h.click(); assert.deepEqual(h.sent, []);
});
