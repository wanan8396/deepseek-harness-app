// Reports visible web dialogs to Lite's native controls. Observe only: no
// form events, DOM writes, credentials, storage or plugin calls.
(function () {
  if (window.__dshAppModal) {
    window.__dshAppModal();
    return;
  }
  var last = null;
  var queued = false;

  function visible(el) {
    if (!el.isConnected || el.closest('[hidden],[aria-hidden="true"],[inert]')) return false;
    for (var p = el; p; p = p.parentElement) {
      var style = getComputedStyle(p);
      if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' ||
          Number(style.opacity) === 0) return false;
    }
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 &&
      r.left < innerWidth && r.top < innerHeight;
  }

  function report() {
    var dialogs = document.querySelectorAll(
      '[role="dialog"],[aria-modal="true"],body>[class*="_overlay"]:has([data-slot="settings.section"])'
    );
    var open = false;
    for (var i = 0; i < dialogs.length; i++) {
      // rc2 exposes the navigation drawer as a dialog too. It is not a
      // full-screen sheet: Lite's whale stays in the drawer's reserved footer.
      if (dialogs[i].matches('[data-shortcut-modal="sidebar"]')) continue;
      if (visible(dialogs[i])) { open = true; break; }
    }
    if (open === last) return;
    try {
      var channel = window.DshAppModal;
      if (!channel || !channel.postMessage) return;
      channel.postMessage(open ? 'open' : 'closed');
      last = open;
    } catch (e) {
      // The host may have detached while this document was navigating away.
    }
  }

  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; report(); });
  }

  window.__dshAppModal = report;
  new MutationObserver(schedule).observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['role', 'aria-modal', 'aria-hidden', 'hidden', 'inert', 'open', 'class', 'style'],
  });
  window.addEventListener('resize', schedule, { passive: true });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', schedule, { passive: true });
  // A class can begin a fade at opacity zero before its first visible frame.
  document.addEventListener('transitionend', schedule, { passive: true });
  document.addEventListener('animationend', schedule, { passive: true });
  report();
})();
