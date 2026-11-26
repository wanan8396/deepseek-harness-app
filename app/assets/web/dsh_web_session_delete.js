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
  if (!CHANNEL || window.top !== window) return;

  var FAILED = '请刷新会话列表后重试。';
  var ROW = '[data-row-key^="session:"], [data-session-id]';

  // In rc.5 the context menu is a portal. Use the document's marked opener
  // (also available on long press via _menuOpen) or the menu's own props. The
  // currently selected conversation can be different, so it is never a fallback.
  function owningRow(menu) {
    var nested = menu.closest(ROW);
    if (nested) return nested;
    var candidates = Array.from(document.querySelectorAll(
      '[data-row-key^="session:"][class*="_menuOpen"], [data-context-menu-trigger][aria-expanded="true"]',
    )).map(function (node) { return node.closest(ROW); }).filter(Boolean);
    return candidates.length && candidates.every(function (row) { return idOf(row) === idOf(candidates[0]); })
      ? candidates[0] : null;
  }

  function idOf(row) {
    if (!row) return '';
    var key = row.getAttribute('data-row-key') || '';
    return row.getAttribute('data-session-id') || (key.indexOf('session:') === 0 ? key.slice(8) : '');
  }

  function menuTarget(menu) {
    var key = Object.keys(menu).find(function (name) {
      return name.indexOf('__reactFiber$') === 0 || name.indexOf('__reactInternalInstance$') === 0;
    });
    for (var depth = 0, fiber = menu[key]; fiber && depth < 40; depth++, fiber = fiber.return) {
      var props = fiber.memoizedProps;
      if (!props) continue;
      var target = props.target && (props.target.value || props.target);
      var values = [target, props.value, props];
      for (var i = 0; i < values.length; i++) {
        var value = values[i];
        if (value && typeof value.sessionId === 'string' && value.sessionId) return value;
      }
    }
    return null;
  }

  function sessionFor(menu) {
    var row = owningRow(menu);
    var target = menuTarget(menu);
    var sessionId = target ? target.sessionId : idOf(row);
    if (!sessionId) return null;
    if (idOf(row) !== sessionId) {
      row = document.querySelector('[data-row-key="' + CSS.escape('session:' + sessionId) + '"]');
    }
    var label = row && row.querySelector(':scope > [data-session-title], :scope > [class$="_title"]');
    return {
      id: sessionId,
      title: (label && textOf(label)) || (target && typeof target.displayTitle === 'string' ? target.displayTitle.trim() : ''),
      opener: row && (row.querySelector('[data-context-menu-trigger][aria-expanded="true"]') || row),
    };
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
      var ids = known[names[i]];
      if (Array.isArray(ids) && ids.indexOf(sessionId) >= 0) return names[i];
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

  var activeDialog = null;
  var pendingDelete = null;

  function part(parent, tag, cls, text) {
    var node = document.createElement(tag);
    node.className = cls;
    if (text) node.textContent = text;
    parent.appendChild(node);
    return node;
  }

  function openDialog(session, message) {
    if (activeDialog) return;
    var dialog = document.createElement('dialog');
    if (typeof dialog.showModal !== 'function') return;
    dialog.setAttribute('data-dsh-app-session-dialog', '');
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', 'dsh-session-dialog-title');
    dialog.setAttribute('aria-describedby', session ? 'dsh-session-dialog-target dsh-session-dialog-note' : 'dsh-session-dialog-note');

    var icon = part(dialog, 'span', 'dsh-session-dialog-icon');
    icon.setAttribute('aria-hidden', 'true');
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    trashGlyph(svg);
    icon.appendChild(svg);
    part(dialog, 'h2', 'dsh-session-dialog-title', session ? '删除这个对话？' : '暂时无法删除对话')
      .id = 'dsh-session-dialog-title';
    if (session) {
      var shortId = session.id.replace(/^session-/, '').slice(0, 8) + '…';
      part(dialog, 'p', 'dsh-session-dialog-target', session.title || '会话 ID · ' + shortId)
        .id = 'dsh-session-dialog-target';
    }
    part(dialog, 'p', 'dsh-session-dialog-note', session
      ? '此对话将从本机永久删除，无法恢复。如需保留记录，请选择「归档」。' : message)
      .id = 'dsh-session-dialog-note';
    var status = part(dialog, 'p', 'dsh-session-dialog-result');
    status.setAttribute('role', 'status');
    var actions = part(dialog, 'div', 'dsh-session-dialog-actions');
    var dismiss = part(actions, 'button', 'dsh-session-dialog-cancel', session ? '取消' : '关闭');
    dismiss.type = 'button';
    dismiss.autofocus = true;
    dismiss.setAttribute('data-dsh-session-dismiss', '');
    function close() {
      if (activeDialog !== dialog) return;
      activeDialog = null;
      dialog.close();
      dialog.remove();
      if (session && session.opener) requestAnimationFrame(function () {
        if (!activeDialog && session.opener.isConnected) session.opener.focus({ preventScroll: true });
      });
    }
    dismiss.addEventListener('click', close);
    dialog.addEventListener('cancel', function (event) {
      event.preventDefault();
      close();
    });
    dialog.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      close();
    });
    if (session) {
      var submit = part(actions, 'button', 'dsh-session-dialog-submit', '删除对话');
      submit.type = 'button';
      submit.addEventListener('click', function () {
        if (activeDialog !== dialog || pendingDelete) return;
        pendingDelete = { id: session.id, dialog: dialog, submit: submit, dismiss: dismiss, status: status };
        submit.disabled = true;
        submit.textContent = '正在删除…';
        dismiss.textContent = '关闭';
        status.removeAttribute('data-error');
        status.textContent = '删除请求已提交，关闭此弹窗不会取消删除。';
        // The shell resolves the project again if the list is stale or missing.
        if (!ask(projectOf(session.id) || '', session.id)) deleteFailed(FAILED);
      });
    }
    document.body.appendChild(dialog);
    activeDialog = dialog;
    try {
      dialog.showModal();
      dismiss.focus({ preventScroll: true });
    } catch (e) {
      activeDialog = null;
      dialog.remove();
    }
  }

  function deleteFrom(menu) {
    if (activeDialog || pendingDelete) return;
    var session = sessionFor(menu);
    // Close the upstream menu through its normal outside-pointer handler. The
    // target and title are captured first because the handler unmounts the menu.
    document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerType: 'touch' }));
    openDialog(session, '未识别到这个菜单所属的会话，请重新打开该会话的菜单后再试。');
  }

  function deleteFailed(message) {
    var request = pendingDelete;
    pendingDelete = null;
    if (activeDialog !== request.dialog) {
      openDialog(null, message);
      return;
    }
    request.submit.disabled = false;
    request.submit.textContent = '删除对话';
    request.dismiss.textContent = '取消';
    request.status.textContent = message;
    request.status.setAttribute('data-error', '');
    request.dismiss.focus({ preventScroll: true });
  }

  // Reload only on a successful reply for this request, keeping any other
  // conversation selected. An error stays in the same themed dialog.
  window.__dshAppSessionDeleted = function (payload) {
    if (!pendingDelete) return;
    var value;
    try { value = typeof payload === 'string' ? JSON.parse(payload) : payload; } catch (e) {}
    if (value && value.sessionId && value.sessionId !== pendingDelete.id) return;
    known = null;
    if (!value || value.ok !== true || value.sessionId !== pendingDelete.id) {
      deleteFailed(value && typeof value.message === 'string' ? value.message : FAILED);
      return;
    }
    pendingDelete = null;
    try {
      var store = JSON.parse(localStorage.getItem('dsh.sessions.current') || '{}') || {};
      if (store.sessionId === value.sessionId) localStorage.removeItem('dsh.sessions.current');
    } catch (e) {}
    location.reload();
  };

  // The Session menu's own archive row. It must be the whole phrase: a loose
  // /归档/ test also matches the sort menu's 「隐藏已归档」, which is a filter,
  // not a Session action, and that is not where a deletion belongs.
  // Both states of the same row: an active Session offers 归档会话, an archived
  // one offers 取消归档. A deletion belongs after either.
  var ARCHIVE = /^(归档会话|取消归档|Archive (conversation|session)|Unarchive|アーカイブ|보관)$/i;

  function textOf(node) {
    return (node.textContent || '').replace(/\s+/g, ' ').trim();
  }

  function archiveItem(menu) {
    var items = menu.querySelectorAll('[role="menuitem"]');
    for (var i = 0; i < items.length; i++) {
      if (items[i].hasAttribute('data-dsh-app-delete')) continue;
      if (ARCHIVE.test(textOf(items[i]))) return items[i];
    }
    return null;
  }

  // Only a Session menu offers 「复制 Session ID」/「分叉会话」; a filter or sort
  // menu does not. Requiring one of those keeps the row out of the wrong popup.
  var SESSION_MENU = /^(复制 Session ID|Copy Session ID|分叉会话|Fork|重命名|Rename|置顶会话|Pin)/i;

  function isSessionMenu(menu) {
    if (archiveItem(menu)) return true;
    var items = menu.querySelectorAll('[role="menuitem"]');
    for (var i = 0; i < items.length; i++) {
      if (SESSION_MENU.test(textOf(items[i]))) return true;
    }
    return false;
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
      if (!isSessionMenu(menu)) continue;
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
          var owner = event.currentTarget.closest('[role="menu"]');
          if (owner) deleteFrom(owner);
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
