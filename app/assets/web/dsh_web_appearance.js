// Observe DSH's actual theme only. No theme writes, storage or form access.
(function () {
  if (window.__dshAppAppearance) {
    window.__dshAppAppearance();
    return;
  }
  var last = null;
  function report() {
    var body = document.body;
    if (!body) return;
    var value = body.hasAttribute('data-ds-dark-theme') ? 'dark' : 'light';
    if (value === last) return;
    var channel = window.DshAppAppearance;
    if (!channel || !channel.postMessage) return;
    try { channel.postMessage(value); last = value; } catch (e) {}
  }
  window.__dshAppAppearance = report;
  new MutationObserver(report).observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['data-ds-dark-theme'],
  });
  report();
})();
