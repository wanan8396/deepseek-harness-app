// Only the phone's local WebView injects this bridge. No document content is
// requested by JavaScript or returned to it. The native App reads its own profile.
(function (nonce) {
  if (window !== window.top || !window.DshAppSettingsDocument) return;
  if (window.__dshSettingsDocumentDispose) window.__dshSettingsDocumentDispose();
  var names = [
    '打开配置文件', 'Open configuration file',
    'Abrir archivo de configuración', 'Ouvrir le fichier de configuration',
    'Konfigurationsdatei öffnen', '設定ファイルを開く',
    'Открыть файл конфигурации', 'Abra o arquivo de configuração'
  ];
  var selector = '[data-shortcut-modal="settings"][role="dialog"] [data-slot="settings.action"] button';
  function click(event) {
    if (!event.isTrusted || event.defaultPrevented) return;
    var button = event.target && event.target.closest && event.target.closest('button');
    if (!button || !button.matches(selector) || button.disabled) return;
    var name = (button.textContent || '').replace(/\s+/g, ' ').trim();
    if (names.indexOf(name) < 0) return;
    try { window.DshAppSettingsDocument.postMessage(nonce); }
    catch (_) { return; } // Keep official behavior if the App bridge is absent.
    event.preventDefault();
    event.stopImmediatePropagation();
  }
  document.addEventListener('click', click, true);
  window.__dshSettingsDocumentDispose = function () {
    document.removeEventListener('click', click, true);
    delete window.__dshSettingsDocumentDispose;
  };
})(__DSH_SETTINGS_DOCUMENT_NONCE__);
