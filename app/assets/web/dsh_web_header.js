// Keep session-header dropdowns out of the horizontally scrolling row's clip.
// Only positions existing menus; their actions and dismissal remain the webpage's.
(function () {
  if (window.__dshAppHeaderMenus) { window.__dshAppHeaderMenus(); return; }
  var queued = false;
  function set(el, name, value) {
    if (el.style.getPropertyValue(name) !== value) el.style.setProperty(name, value);
  }
  function update() {
    var html = document.documentElement;
    var active = html.hasAttribute('data-dsh-app-lite') && html.getAttribute('data-dsh-app-layout') === 'drawer';
    var menus = document.querySelectorAll('[data-slot="conversation.session.header"] [role="menu"]');
    for (var i = 0; i < menus.length; i++) {
      var menu = menus[i];
      if (!active || menu.parentElement.closest('[role="menu"]')) {
        menu.removeAttribute('data-dsh-app-header-menu');
        continue;
      }
      if (getComputedStyle(menu).display === 'none' || menu.getAttribute('aria-hidden') === 'true') continue;
      var anchor = menu.parentElement.getBoundingClientRect();
      if (!anchor.width || !anchor.height) continue;
      if (!menu.hasAttribute('data-dsh-app-header-menu')) menu.setAttribute('data-dsh-app-header-menu', '');
      var style = getComputedStyle(html);
      var safeTop = parseFloat(style.getPropertyValue('--dsh-app-safe-top')) || 0;
      var safeBottom = parseFloat(style.getPropertyValue('--dsh-app-safe-bottom')) || 0;
      var edge = 8, minTop = safeTop + edge, maxBottom = innerHeight - safeBottom - edge;
      var below = Math.max(0, maxBottom - anchor.bottom - 4);
      var above = Math.max(0, anchor.top - 4 - minTop);
      var up = below < Math.min(menu.scrollHeight, 160) && above > below;
      var available = up ? above : below;
      set(menu, '--dsh-app-header-menu-height', Math.max(0, available) + 'px');
      var rect = menu.getBoundingClientRect();
      var left = Math.max(edge, Math.min(anchor.right - rect.width, innerWidth - rect.width - edge));
      var top = up ? Math.max(minTop, anchor.top - rect.height - 4) : Math.max(minTop, anchor.bottom + 4);
      set(menu, '--dsh-app-header-menu-left', left + 'px');
      set(menu, '--dsh-app-header-menu-top', top + 'px');
    }
  }
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; update(); });
  }
  window.__dshAppHeaderMenus = schedule;
  new MutationObserver(schedule).observe(document.documentElement, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: ['class', 'style', 'role', 'hidden', 'aria-hidden', 'data-dsh-app-layout', 'data-dsh-app-lite'],
  });
  document.addEventListener('scroll', schedule, { capture: true, passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  schedule();
})();
