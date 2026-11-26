// A real "delete conversation" entry in DSH Web's own Session menus.
//
// Archiving leaves the Session on disk; this removes it. The page cannot touch
// the guest filesystem, so the whole action goes through the shell: the bridges
// report the Session this menu belongs to, Android refuses anything the
// listing would not offer, and the page only re-renders afterwards.
//
// The menu itself stays the webpage's: this adds one `[role="menuitem"]` beside
// archive, marked with `data-dsh-app-delete` so a second pass never doubles it.
// Injected after every load; idempotent.
(function () {
  if (window.__dshAppSessionDelete) { window.__dshAppSessionDelete(); return; }

  var CHANNEL = window.DshAppSessionDelete;
  function confirmText(sessionId) {
    return (
      '删除这个对话？\n\n' +
      '会话 ' + sessionId.slice(0, 8) + '… 会从手机上真的删掉，无法恢复。\n' +
      '想以后还能找回，请改用「归档」。'
    );
  }
  var FAILED = '删除失败，会话没有被改动。';
  var DONE = '已删除对话';

  // The Session this menu belongs to. DSH Web keeps the selection in
  // localStorage (`dsh.sessions.current`); the row's own attributes win when
  // a menu was opened for a Session that is not the open one.
  function selection() {
    try {
      return (JSON.parse(localStorage.getItem('dsh.sessions.current') || '{}') || {}).sessionId || null;
    } catch (e) {
      return null;
    }
  }

  // The menu is a portal and its rows carry no id attribute, so the Session it
  // was opened for is read from the React tree that owns the menu node: the
  // same `target.sessionId` the page passed when it opened the menu.
  function fiberId(node) {
    var key = Object.keys(node).find(function (name) {
      return name.indexOf('__reactFiber$') === 0 || name.indexOf('__reactInternalInstance$') === 0;
    });
    if (!key) return null;
    var fiber = node[key];
    for (var depth = 0; fiber && depth < 40; depth++) {
      var props = fiber.memoizedProps;
      if (props) {
        if (typeof props.sessionId === 'string') return props.sessionId;
        if (props.target && typeof props.target.sessionId === 'string') return props.target.sessionId;
        if (props.value && typeof props.value.sessionId === 'string') return props.value.sessionId;
      }
      fiber = fiber.return;
    }
    return null;
  }

  function rowId(menu) {
    var direct = menu.closest('[data-session-id]');
    if (direct) return direct.getAttribute('data-session-id');
    var fromTree = fiberId(menu);
    if (fromTree) return fromTree;
    // Last resort: the conversation the page has open. The confirmation names
    // it, so the person can stop a deletion aimed at the wrong one.
    return selection();
  }

  // Session id -> project for everything the shell will accept, fetched once
  // per pass so the menu can refuse a Session that is not on disk.
  var known = null;
  var loading = null;
  function load() {
    if (known) return Promise.resolve(known);
    if (loading) return loading;
    loading = new Promise(function (resolve) {
      try {
        if (!window.DshAppSessions) return resolve(null);
        window.DshAppSessions.postMessage('list');
      } catch (e) {
        resolve(null);
      }
    });
    return loading;
  }

  var pendingList = null;
  window.__dshAppSessionsList = function (payload) {
    try {
      var value = typeof payload === 'string' ? JSON.parse(payload) : payload;
      known = (value && value.projects) || {};
      if (pendingList) {
        pendingList(known);
        pendingList = null;
      }
      loading = null;
    } catch (e) {
      loading = null;
    }
  };

  function projectOf(sessionId) {
    if (!known) return null;
    var names = Object.keys(known);
    for (var i = 0; i < names.length; i++) {
      if (known[names[i]].indexOf(sessionId) >= 0) return names[i];
    }
    return null;
  }

  function ask(project, sessionId) {
    if (!CHANNEL) return false;
    try {
      CHANNEL.postMessage(JSON.stringify({ project: project, sessionId: sessionId }));
      return true;
    } catch (e) {
      return false;
    }
  }

  function deleteFrom(menu) {
    var sessionId = rowId(menu);
    if (!sessionId) {
      // Without an id there is nothing safe to delete; say so rather than
      // acting on a guess.
      window.alert('无法确定这个菜单属于哪个会话。请先打开该对话，再从它的菜单里删除。');
      return;
    }
    // The shell is the authority on what exists and finds the project itself,
    // so a stale or missing list never blocks the action here.
    var project = projectOf(sessionId) || '';
    if (!window.confirm(confirmText(sessionId))) return;
    if (!ask(project, sessionId)) window.alert(FAILED);
  }

  // Android answers here: the Session is gone, so the page reloads its list.
  window.__dshAppSessionDeleted = function (payload) {
    try {
      var value = typeof payload === 'string' ? JSON.parse(payload) : payload;
      known = null;
      if (!value || value.ok === false) {
        window.alert(value && value.message ? value.message : FAILED);
        return;
      }
      // DSH Web reads its list from the engine; a reload is the one reliable
      // way to drop the row, and the deleted Session is no longer selected.
      try {
        if (value.sessionId) {
          var store = JSON.parse(localStorage.getItem('dsh.sessions.current') || '{}') || {};
          if (store.sessionId === value.sessionId) localStorage.removeItem('dsh.sessions.current');
        }
      } catch (e) {}
      location.reload();
    } catch (e) {
      location.reload();
    }
  };

  // The engine's own entry, which this sits beside. Its labels are whole
  // phrases ("归档会话", "Archive conversation"), so match the verb, not equality.
  var ARCHIVE = /归档|archive|アーカイブ|보관/i;

  function archiveItem(menu) {
    var items = menu.querySelectorAll('[role="menuitem"]');
    for (var i = 0; i < items.length; i++) {
      if (items[i].hasAttribute('data-dsh-app-delete')) continue;
      var text = (items[i].textContent || '').trim();
      // 取消归档 / Unarchive is a different action; leave it alone.
      if (/取消归档|取消|unarchive|restore/i.test(text)) continue;
      if (ARCHIVE.test(text)) return items[i];
    }
    return null;
  }

  // A trash-can outline drawn into the row's existing <svg>, so the icon keeps
  // the menu's size, stroke and colour inheritance.
  function trashGlyph(svg) {
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    var ns = 'http://www.w3.org/2000/svg';
    function el(name, attrs) {
      var node = document.createElementNS(ns, name);
      for (var key in attrs) node.setAttribute(key, attrs[key]);
      return node;
    }
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '1.6');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    // Lid, body and the two inner lines.
    svg.appendChild(el('path', { d: 'M4 7h16' }));
    svg.appendChild(el('path', { d: 'M10 4h4a1 1 0 0 1 1 1v2H9V5a1 1 0 0 1 1-1z' }));
    svg.appendChild(el('path', { d: 'M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12' }));
    svg.appendChild(el('path', { d: 'M10 11v6M14 11v6' }));
  }

  // The destructive colour: the theme's error token when it defines one, so
  // light and dark both stay legible, with a fixed red as the fallback.
  function colourDanger(entry) {
    var red = null;
    try {
      var probe = document.createElement('span');
      probe.style.color = 'var(--dsh-color-danger, var(--color-danger, var(--error, #d92d20)))';
      probe.style.display = 'none';
      document.body.appendChild(probe);
      var resolved = getComputedStyle(probe).color;
      document.body.removeChild(probe);
      if (resolved && resolved !== 'rgba(0, 0, 0, 0)' && resolved !== 'transparent') red = resolved;
    } catch (e) {}
    var target = entry.querySelectorAll('[role], span, div');
    var nodes = [entry];
    for (var i = 0; i < target.length; i++) nodes.push(target[i]);
    for (var j = 0; j < nodes.length; j++) {
      // Only leaf-ish nodes carry the label; colouring the row too is harmless.
      nodes[j].style.color = red || '#d92d20';
      nodes[j].setAttribute('data-dsh-app-danger', '');
    }
    var svgs = entry.querySelectorAll('svg');
    for (var k = 0; k < svgs.length; k++) svgs[k].style.color = red || '#d92d20';
  }

  function decorate() {
    var menus = document.querySelectorAll('[role="menu"]');
    for (var i = 0; i < menus.length; i++) {
      var menu = menus[i];
      if (menu.querySelector('[data-dsh-app-delete]')) {
        // A re-render can keep the row but drop our inline colour; re-apply.
        var kept = menu.querySelector('[data-dsh-app-delete]');
        if (!kept.hasAttribute('data-dsh-app-danger') || !kept.querySelector('[data-dsh-app-danger]')) colourDanger(kept);
        continue;
      }
      var anchor = archiveItem(menu);
      if (!anchor) continue;
      var entry = anchor.cloneNode(true);
      entry.setAttribute('data-dsh-app-delete', '');
      entry.setAttribute('data-dsh-app-menu-action', 'delete');
      // Keep the menu's own styling: only the label changes.
      var labelled = entry.querySelectorAll('*');
      var replaced = false;
      for (var j = 0; j < labelled.length && !replaced; j++) {
        var node = labelled[j];
        if (node.children.length === 0 && (node.textContent || '').trim()) {
          node.textContent = '删除对话';
          replaced = true;
        }
      }
      if (!replaced) entry.textContent = '删除对话';
      // Keep the archive row's icon slot so spacing and alignment stay the
      // menu's own; only the glyph becomes a trash can.
      var icons = entry.querySelectorAll('svg');
      if (icons.length) {
        for (var k = 1; k < icons.length; k++) icons[k].remove();
        trashGlyph(icons[0]);
      }
      // Deletion is destructive: label and glyph use the error colour, taken
      // from the page's own theme variable when it has one.
      colourDanger(entry);
      entry.addEventListener(
        'click',
        function (event) {
          event.preventDefault();
          event.stopPropagation();
          deleteFrom(menu);
        },
        true,
      );
      if (anchor.parentElement) anchor.parentElement.insertBefore(entry, anchor.nextSibling);
    }
  }

  var queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () {
      queued = false;
      decorate();
      load();
    });
  }

  window.__dshAppSessionDelete = schedule;
  new MutationObserver(schedule).observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['role', 'aria-hidden', 'hidden', 'style'],
  });
  schedule();
})();
