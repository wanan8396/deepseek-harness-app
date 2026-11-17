// The official sidebar's drawer, seen from the app. Injected by dsh-app's
// WebView page after every load (idempotent): it only reports, and only when
// the drawer covers the app's marker — the official drawer at phone widths or
// the app's own drawer (Lite).
//
// The app's marker sits in DSH Web's leading seat, over the page's own header
// row; the drawer, opened, slides over that row. So the marker steps aside
// while it is up instead of covering the drawer's brand and rows.
//
// State, not events: the page may replace its frame, open the drawer before
// this bridge was injected, or finish an animation without a watched attribute
// changing. So the covering state is recomputed from the drawer attributes, the
// observers stay the fast path, a slow poll catches a mutation nobody watched,
// and the app can ask for a re-report after a load or when it comes back to the
// front.
//
// Only the attributes DSH sets for the drawer count. A drawer mask or a panel
// container can exist in the document while nothing is open (off-screen, or an
// unmounted panel's shell), so their presence is not a state: a false positive
// here hides the marker for good.
(function () {
  if (window.__dshAppSidebar) return;

  var CHANNEL = 'DshAppSidebar';

  function frame() {
    return document.querySelector('[data-slot="root"] > [class*="_frame"]');
  }

  function lite() {
    return document.documentElement.hasAttribute('data-dsh-app-lite');
  }

  // Open: the official layout puts `data-sidebar-drawer` on the frame at phone
  // widths and folds the sidebar away with `data-sidebar-collapsed`. Wider
  // windows show the sidebar as a column (no drawer): nothing to cover, so
  // that reads as closed.
  //
  // The app's own phone layout sets `html[data-dsh-app-layout="drawer"]`; its
  // drawer is the app's (dsh_web_phone.js, dsh_web_phone.css) and marked with
  // `data-dsh-app-drawer`. Only Lite has it, so the full edition is unchanged.
  function open() {
    var f = frame();
    if (!f) return false;
    var appLayout = document.documentElement.getAttribute('data-dsh-app-layout') === 'drawer';
    if (appLayout) {
      if (f.hasAttribute('data-sidebar-drawer')) {
        return (lite() && f.hasAttribute('data-dsh-app-drawer')) ||
          !f.hasAttribute('data-sidebar-collapsed');
      }
      return lite() && f.hasAttribute('data-dsh-app-drawer');
    }
    return !!f.hasAttribute('data-sidebar-drawer') && !f.hasAttribute('data-sidebar-collapsed');
  }

  // Closed to start with: the app's marker is up before the page says
  // otherwise, and a load that finishes on an error page never says.
  var last = false;
  function report(force) {
    var now = open();
    if (now === last && !force) return;
    last = now;
    try {
      var channel = window[CHANNEL];
      if (channel && channel.postMessage) channel.postMessage(now ? 'open' : 'closed');
    } catch (e) {
      // No channel (an old shell): nothing to tell.
    }
  }

  // The frame can be replaced when the page rebuilds its layout; keep the
  // attribute watch on whichever frame is there, and report the new state.
  var watched = null;
  var frameObserver = null;
  function bind() {
    var f = frame();
    if (f === watched) return;
    watched = f;
    if (frameObserver) frameObserver.disconnect();
    frameObserver = null;
    if (f) {
      frameObserver = new MutationObserver(function () { report(); });
      frameObserver.observe(f, {
        attributes: true,
        attributeFilter: ['data-sidebar-drawer', 'data-sidebar-collapsed', 'data-dsh-app-drawer'],
      });
    }
    report();
  }

  // The app's own hook: a forced re-report, used after a load and when the app
  // returns to the front, so a state the page reached while nobody listened is
  // corrected instead of leaving the marker up over an open drawer.
  window.__dshAppSidebar = function (force) { report(force === true); };

  new MutationObserver(function () {
    bind();
    report();
  }).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-dsh-app-layout', 'data-dsh-app-lite'],
    // Direct children only: a replacement of the root, not every message the
    // conversation streams in (the frame watch below covers that tree).
    childList: true,
  });
  var root = document.querySelector('[data-slot="root"]');
  if (root) new MutationObserver(bind).observe(root, { childList: true });

  // A mutation nobody watches (a drawer opened while the frame observer was
  // being rebound, a change during a transition) still ends in the right state:
  // compare now and then while the document is visible. Timers throttle in the
  // background, which is why the app also asks on resume.
  if (typeof setTimeout === 'function' && typeof document.visibilityState === 'string') {
    var tick = function () {
      if (document.visibilityState === 'visible') {
        bind();
        report();
      }
      setTimeout(tick, 700);
    };
    setTimeout(tick, 700);
  }

  if (window.addEventListener) {
    window.addEventListener('pageshow', function () { report(true); }, { passive: true });
    window.addEventListener('resize', function () { report(); }, { passive: true });
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') { bind(); report(true); }
    });
  }

  bind();
})();
