// Fixed-canvas browser for the Host slot catalog. The last Host list owns the identities.
(function () {
  'use strict';

  function isDeleted(slot) {
    return !!(slot.tombstoned || slot.inconsistent);
  }

  function create(actions) {
    var stage = document.getElementById('save-shell');
    var list = document.getElementById('cards');
    var liveTab = document.getElementById('save-live');
    var deletedTab = document.getElementById('save-deleted');
    var detail = document.getElementById('save-detail');
    var ledger = list.parentElement;
    var empty = document.getElementById('save-empty');
    var headings = document.getElementById('save-columns');
    var createTools = document.getElementById('save-create-tools');
    var headerTools = createTools.parentElement;
    var buttons = document.getElementById('save-actions');
    var scale = null;
    var slots = [];
    var rows = [];
    var deleted = false;
    var selectedKey = '';
    var pendingDelete = '';
    var pendingRename = '';

    function selected() {
      return rows.find(function (row) { return row.slot === selectedKey; });
    }

    function statusText(slot) {
      if (slot.rebuildPending) return '重建副本待核验';
      if (slot.inconsistent) return '已删除 · 有残留副本';
      if (slot.tombstoned) return '已删除';
      if (slot.corrupt) return '需要修复';
      return '可选择';
    }

    function modified(slot) {
      if (!slot.lastModified) return '—';
      var date = new Date(slot.lastModified);
      if (!isFinite(date.getTime())) return '—';
      return date.toLocaleDateString('sv-SE') + ' ' + date.toLocaleTimeString('zh-CN', {hour:'2-digit', minute:'2-digit', hour12:false});
    }

    function setText(id, value) { document.getElementById(id).textContent = value; }

    function drawDetail() {
      var slot = selected();
      detail.hidden = !slot;
      empty.hidden = !!slot;
      headings.hidden = !slot;
      stage.classList.toggle('archive-empty', !slot);
      setText('save-empty-label', deleted ? '没有已删除的存档' : '暂无存档');
      var toolsParent = !slot && !deleted ? empty : headerTools;
      if (createTools.parentElement !== toolsParent) {
        var focused = createTools.contains(document.activeElement) && document.activeElement;
        if (toolsParent === empty) empty.appendChild(createTools);
        else headerTools.prepend(createTools);
        if (focused) focused.focus({preventScroll:true});
      }
      if (!slot) return;
      var protectedSlot = isDeleted(slot);
      var busy = slot.slot === pendingDelete;
      setText('save-title', actions.primaryName(slot));
      detail.setAttribute('aria-label', actions.primaryName(slot) + '的存档操作');
      setText('save-key', slot.slot);
      document.getElementById('save-title').title = actions.primaryName(slot);
      var available = {
        start: !protectedSlot && !slot.corrupt,
        edit: !protectedSlot || slot.inconsistent,
        export: !protectedSlot || slot.inconsistent,
        rename: true,
        delete: !protectedSlot || (slot.inconsistent && !slot.rebuildPending && actions.canCleanResidue()),
        rebuild: protectedSlot
      };
      Array.from(buttons.children).forEach(function (button) {
        var action = button.dataset.action;
        button.hidden = !available[action];
        button.disabled = busy || (action === 'delete' && !!pendingDelete) || (action === 'rename' && !!pendingRename);
        if (action === 'edit') button.textContent = protectedSlot ? '查看副本' : '编辑';
        if (action === 'delete') button.textContent = protectedSlot ? '清理残留' : '删除';
        if (action === 'rename') button.textContent = slot.slot === pendingRename ? '重命名中…' : '重命名';
      });
    }

    function positionActions(active) {
      // Keep the same action buttons next to the record when all rows fit. For a
      // scrolling catalog they dock outside the scroller and remain reachable.
      var focused = detail.contains(document.activeElement) && document.activeElement;
      if (active && list.clientHeight && list.scrollHeight <= list.clientHeight + 1) {
        if (active.nextElementSibling !== detail) active.after(detail);
      } else if (detail.parentElement !== ledger) {
        ledger.appendChild(detail);
      }
      if (focused && document.activeElement !== focused) focused.focus({preventScroll:true});
    }

    function updateLayout() {
      if (scale) positionActions(list.querySelector('.save-row[aria-pressed="true"]'));
    }

    function choose(index, focus) {
      selectedKey = rows[index] ? rows[index].slot : '';
      var options = list.querySelectorAll('.save-row');
      options.forEach(function (button, i) {
        button.setAttribute('aria-pressed', String(i === index));
        button.tabIndex = i === index ? 0 : -1;
      });
      drawDetail();
      var active = options[index];
      positionActions(active);
      if (focus && active) {
        active.focus({preventScroll:true});
        active.scrollIntoView({block:'nearest'});
      }
    }

    function rowButton(slot) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'save-row';
      button.setAttribute('aria-controls', 'save-detail');
      button.dataset.slot = slot.slot;
      var state = isDeleted(slot) ? 'deleted' : slot.corrupt ? 'corrupt' : 'live';
      button.dataset.state = state;
      var character = actions.primaryName(slot);
      var display = actions.displayName(slot);
      var name = document.createElement('strong');
      name.textContent = character;
      name.title = character;
      var alias = document.createElement('span');
      alias.className = 'save-alias';
      alias.textContent = display === character ? '—' : display;
      alias.title = display === character ? '与角色名相同' : display;
      if (display === character) alias.setAttribute('aria-label', '存档名与角色名相同');
      var progress = document.createElement('span');
      progress.className = 'save-progress';
      // The legacy service can prefix a level with the same character name already in column one.
      var value = slot.mainProgress || '';
      var prefix = character + ' ';
      if (value.indexOf(prefix) === 0 && /^Lv\.\s*\d+$/i.test(value.slice(prefix.length))) value = value.slice(prefix.length);
      progress.textContent = state === 'live' ? value || '—' : statusText(slot);
      progress.title = state === 'live' ? slot.mainProgress || '' : statusText(slot);
      var stamp = document.createElement('time');
      stamp.textContent = modified(slot);
      if (slot.lastModified) stamp.dateTime = slot.lastModified;
      var size = document.createElement('span');
      size.className = 'save-bytes';
      size.textContent = actions.formatBytes(slot.size) || '—';
      button.append(name, alias, progress, stamp, size);
      return button;
    }

    function render() {
      var focusList = list.contains(document.activeElement) && document.activeElement.classList.contains('save-row');
      var focusedAction = buttons.contains(document.activeElement) && document.activeElement;
      var priorScroll = list.scrollTop;
      var removed = slots.filter(isDeleted);
      rows = deleted ? removed : slots.filter(function (s) { return !isDeleted(s); });
      setText('save-live-count', slots.length - removed.length);
      setText('save-deleted-count', removed.length);
      liveTab.setAttribute('aria-pressed', String(!deleted));
      deletedTab.setAttribute('aria-pressed', String(deleted));
      list.setAttribute('aria-label', deleted ? '已删除存档' : '我的存档');
      var index = rows.findIndex(function (s) { return s.slot === selectedKey; });
      if (index < 0) index = rows.length ? 0 : -1;
      var fragment = document.createDocumentFragment();
      rows.forEach(function (slot) { fragment.appendChild(rowButton(slot)); });
      if (detail.parentElement !== ledger) ledger.appendChild(detail);
      list.replaceChildren(fragment);
      list.scrollTop = priorScroll;
      choose(index, focusList);
      if (((focusList || focusedAction) && index < 0) || (focusedAction && (focusedAction.hidden || focusedAction.disabled))) {
        (deleted ? deletedTab : liveTab).focus();
      } else if (focusedAction) {
        focusedAction.focus({preventScroll:true});
      }
    }

    function changeGroup(next) {
      if (deleted === next) return;
      deleted = next;
      selectedKey = '';
      list.scrollTop = 0;
      render();
    }
    liveTab.onclick = function () { changeGroup(false); };
    deletedTab.onclick = function () { changeGroup(true); };

    list.onclick = function (event) {
      var button = event.target.closest('.save-row');
      if (button) choose(rows.findIndex(function (slot) { return slot.slot === button.dataset.slot; }), false);
    };
    list.onkeydown = function (event) {
      if (!event.target.closest('.save-row')) return;
      var i = rows.findIndex(function (row) { return row.slot === selectedKey; });
      if (i < 0) return;
      if (event.key === 'ArrowDown') i = Math.min(rows.length - 1, i + 1);
      else if (event.key === 'ArrowUp') i = Math.max(0, i - 1);
      else if (event.key === 'Home') i = 0;
      else if (event.key === 'End') i = rows.length - 1;
      else if (event.key === 'Enter' && !isDeleted(rows[i]) && !rows[i].corrupt) {
        event.preventDefault();
        buttons.querySelector('.btn-start').click();
        return;
      } else return;
      event.preventDefault();
      choose(i, true);
    };

    buttons.onclick = function (event) {
      var button = event.target.closest('button[data-action]');
      var slot = selected();
      if (slot && button && !button.hidden && !button.disabled) actions.run(button.dataset.action, slot);
    };

    return {
      update: function (ordered) { slots = ordered; render(); },
      updateLayout: updateLayout,
      open: function (fromWelcome, preferredKey) {
        if (!scale) scale = PanelScale.attach(stage, 1024, 576, {onUpdate:updateLayout});
        scale.update();
        if (fromWelcome) { deleted = false; selectedKey = preferredKey || ''; }
        render();
        var target = list.querySelector('.save-row[aria-pressed="true"]') || document.getElementById('btn-new');
        target.focus({preventScroll:true});
        if (list.contains(target)) target.scrollIntoView({block:'nearest'});
      },
      close: function () {
        if (scale) scale.detach();
        scale = null;
      },
      setDeletePending: function (key) { pendingDelete = key || ''; drawDetail(); },
      setRenamePending: function (key) { pendingRename = key || ''; drawDetail(); }
    };
  }

  window.BootstrapSaveManager = { create: create, isDeleted: isDeleted };
})();
