// Fixed-canvas browser for the Host slot catalog. The last Host list owns the identities.
(function () {
  'use strict';

  function isDeleted(slot) {
    return !!(slot.tombstoned || slot.inconsistent);
  }

  function localTime(stamp) {
    if (!stamp) return '';
    var date = new Date(stamp);
    if (!isFinite(date.getTime())) return '';
    return date.toLocaleDateString('sv-SE') + ' ' + date.toLocaleTimeString('zh-CN', {hour:'2-digit', minute:'2-digit', hour12:false});
  }

  function relativeTime(stamp) {
    var delta = Date.now() - Date.parse(stamp);
    if (!isFinite(delta) || delta < 0) return '最近记录';
    var minutes = Math.floor(delta / 60000);
    if (!minutes) return '刚刚';
    if (minutes < 60) return minutes + ' 分钟前';
    var hours = Math.floor(minutes / 60);
    return hours < 24 ? hours + ' 小时前' : Math.floor(hours / 24) + ' 天前';
  }

  function progressLabel(slot, name) {
    var text = slot.mainProgress || '';
    var prefix = name + ' ';
    return text.indexOf(prefix) === 0 && /^Lv\.\s*\d+$/i.test(text.slice(prefix.length)) ? text.slice(prefix.length) : text;
  }

  function paintSignature(badge, key) {
    var sig = key && window.PM19Decor && window.PM19Decor.signature(key);
    var cacheKey = sig ? key + '/' + sig.seed + '/' + sig.line : '';
    if (badge.dataset.signature === cacheKey) return;
    badge.dataset.signature = cacheKey;
    badge.replaceChildren();
    badge.title = sig ? sig.lineName + ' · Σ ' + sig.magicSum : '';
    if (!sig) return;
    var lo = Math.min.apply(null, sig.values), hi = Math.max.apply(null, sig.values);
    var bars = document.createDocumentFragment();
    sig.values.forEach(function(value) {
      var bar = document.createElement('i');
      var fraction = hi === lo ? 0.5 : (value - lo) / (hi - lo);
      bar.style.height = (12 + 88 * fraction).toFixed(1) + '%';
      bars.appendChild(bar);
    });
    badge.appendChild(bars);
  }

  function create(actions) {
    var stage = document.getElementById('save-shell');
    var list = document.getElementById('cards');
    var liveTab = document.getElementById('save-live');
    var deletedTab = document.getElementById('save-deleted');
    var detail = document.getElementById('save-detail');
    var empty = document.getElementById('save-empty');
    var headings = document.getElementById('save-columns');
    var createTools = document.getElementById('save-create-tools');
    var headerTools = createTools.parentElement;
    var buttons = document.getElementById('save-actions');
    var slots = [];
    var rows = [];
    var deleted = false;
    var selectedKey = '';
    var search = document.getElementById('save-search');
    var sort = document.getElementById('save-sort');
    window.addEventListener('pm19-decor-ready', function () { if (slots.length) render(); });
    search.oninput = render;
    sort.onchange = render;
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

    function setText(id, value) { document.getElementById(id).textContent = value; }

    function drawDetail() {
      var slot = selected();
      detail.hidden = !slot;
      empty.hidden = !!slot;
      headings.hidden = !slot;
      stage.classList.toggle('archive-empty', !slot);
      setText('save-empty-label', search.value.trim() ? '没有匹配的存档' : deleted ? '没有已删除的存档' : '暂无存档');
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
      detail.dataset.state = protectedSlot ? 'deleted' : slot.corrupt ? 'corrupt' : 'live';
      paintSignature(document.getElementById('save-detail-sig'), slot.slot);
      var stamp = slot.lastPlayed || slot.lastModified;
      setText('save-history', [actions.displayName(slot) !== actions.primaryName(slot) ? actions.displayName(slot) : '',
        progressLabel(slot, actions.primaryName(slot)), Number.isInteger(slot.storyProgress) ? '主线 ' + slot.storyProgress : '',
        localTime(stamp), actions.formatBytes(slot.size)].filter(Boolean).join(' · '));
      detail.setAttribute('aria-label', actions.primaryName(slot) + '的存档操作');
      setText('save-key', slot.slot);
      var meta = document.getElementById('save-character-meta');
      var appearance = slot.appearance || {};
      var facts = protectedSlot || slot.corrupt ? [] : [slot.gender, slot.difficulty, appearance.face, appearance.hair].filter(Boolean);
      meta.textContent = facts.join(' · ');
      meta.title = facts.concat([appearance.upper, appearance.lower, appearance.footwear].filter(Boolean)).join(' · ');
      meta.hidden = !facts.length;
      document.getElementById('save-title').title = actions.primaryName(slot);
      var available = {
        start: !protectedSlot && !slot.corrupt,
        repair: !protectedSlot && slot.corrupt,
        undo: !protectedSlot && !!slot.editUndoToken,
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

    function choose(index, focus) {
      selectedKey = rows[index] ? rows[index].slot : '';
      var options = list.querySelectorAll('.save-row');
      options.forEach(function (button, i) {
        button.setAttribute('aria-pressed', String(i === index));
        button.tabIndex = i === index ? 0 : -1;
      });
      drawDetail();
      var active = options[index];
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
      var badge = document.createElement('span');
      badge.className = 'slot-sig';
      badge.setAttribute('aria-hidden', 'true');
      paintSignature(badge, slot.slot);
      var alias = document.createElement('span');
      alias.className = 'save-alias';
      alias.textContent = display === character ? '—' : display;
      alias.title = display === character ? '与角色名相同' : display;
      if (display === character) alias.setAttribute('aria-label', '存档名与角色名相同');
      var progress = document.createElement('span');
      progress.className = 'save-progress';
      var value = progressLabel(slot, character);
      progress.textContent = state === 'live' ? value || '—' : statusText(slot);
      if (state === 'live' && Number.isInteger(slot.storyProgress)) progress.textContent += ' · 主线 ' + slot.storyProgress;
      progress.title = state === 'live' ? [slot.mainProgress, slot.difficulty, slot.appearance && slot.appearance.hair].filter(Boolean).join(' · ') : statusText(slot);
      var stamp = document.createElement('time');
      stamp.textContent = localTime(slot.lastPlayed || slot.lastModified) ? relativeTime(slot.lastPlayed || slot.lastModified) : '—';
      stamp.title = localTime(slot.lastPlayed || slot.lastModified);
      if (slot.lastPlayed || slot.lastModified) stamp.dateTime = slot.lastPlayed || slot.lastModified;
      var size = document.createElement('span');
      size.className = 'save-bytes';
      size.textContent = actions.formatBytes(slot.size) || '—';
      button.append(badge, name, alias, progress, stamp, size);
      return button;
    }

    function render() {
      var focusList = list.contains(document.activeElement) && document.activeElement.classList.contains('save-row');
      var focusedAction = buttons.contains(document.activeElement) && document.activeElement;
      var priorScroll = list.scrollTop;
      var removed = slots.filter(isDeleted);
      rows = deleted ? removed.slice() : slots.filter(function (s) { return !isDeleted(s); });
      var query = search.value.trim().toLocaleLowerCase();
      rows = rows.filter(function (s) {
        return !query || [actions.primaryName(s), actions.displayName(s), s.slot].join(' ').toLocaleLowerCase().indexOf(query) >= 0;
      });
      if (sort.value === 'recent') rows.sort(function (a, b) {
        return (Date.parse(b.lastPlayed || b.lastModified) || 0) - (Date.parse(a.lastPlayed || a.lastModified) || 0);
      });
      if (sort.value === 'name') rows.sort(function (a, b) { return actions.primaryName(a).localeCompare(actions.primaryName(b), 'zh-CN'); });
      setText('save-live-count', slots.length - removed.length);
      setText('save-deleted-count', removed.length);
      liveTab.setAttribute('aria-pressed', String(!deleted));
      deletedTab.setAttribute('aria-pressed', String(deleted));
      list.setAttribute('aria-label', deleted ? '已删除存档' : '我的存档');
      var index = rows.findIndex(function (s) { return s.slot === selectedKey; });
      if (index < 0) index = rows.length ? 0 : -1;
      var fragment = document.createDocumentFragment();
      rows.forEach(function (slot) { fragment.appendChild(rowButton(slot)); });
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
      open: function (fromWelcome, preferredKey) {
        if (fromWelcome) { deleted = false; selectedKey = preferredKey || ''; }
        render();
        var target = list.querySelector('.save-row[aria-pressed="true"]') || document.getElementById('btn-new');
        target.focus({preventScroll:true});
        if (list.contains(target)) target.scrollIntoView({block:'nearest'});
      },
      setDeletePending: function (key) { pendingDelete = key || ''; drawDetail(); },
      setRenamePending: function (key) { pendingRename = key || ''; drawDetail(); }
    };
  }

  window.BootstrapSaveManager = { create: create, isDeleted: isDeleted, localTime:localTime, relativeTime:relativeTime, progressLabel:progressLabel, paintSignature:paintSignature };
})();
