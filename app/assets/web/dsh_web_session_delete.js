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
  var CONFIRM =
    '删除这个对话？\n\n' +
    '会话文件会从手机上真的删掉，无法恢复。\n' +
    '想以后还能找回，请改用「归档」。';
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

  function rowId(menu) {
    var row = menu.closest('[data-session-id]');
    if (row) return row.getAttribute('data-session-id');
    var item = menu.closest('[role="menuitem"], [role="option"], li');
    return item ? item.getAttribute('data-session-id') : null;
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
    var sessionId = rowId(menu) || selection();
    if (!sessionId) return;
    var project = projectOf(sessionId);
    // An unknown Session stays in the list: the shell is the authority on what
    // exists, and a stale list must not hide the entry for a new conversation.
    if (project === null && known) return;
    if (!window.confirm(CONFIRM)) return;
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

  function archiveItem(menu) {
    var items = menu.querySelectorAll('[role="menuitem"]');
    for (var i = 0; i < items.length; i++) {
      if (items[i].hasAttribute('data-dsh-app-delete')) continue;
      var text = (items[i].textContent || '').trim();
      // 归档 / Archive — the engine's own entry, which this sits beside.
      if (text === '归档' || text === 'Archive' || text === 'アーカイブ' || text === '보관') return items[i];
    }
    return null;
  }

  function decorate() {
    var menus = document.querySelectorAll('[role="menu"]');
    for (var i = 0; i < menus.length; i++) {
      var menu = menus[i];
      if (menu.querySelector('[data-dsh-app-delete]')) continue;
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
      // The archive icon would be wrong and misleading for a deletion.
      var icons = entry.querySelectorAll('svg');
      for (var k = 0; k < icons.length; k++) icons[k].remove();
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
