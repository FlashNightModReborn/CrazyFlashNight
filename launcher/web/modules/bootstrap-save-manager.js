// Fixed-canvas browser for the Host slot catalog. The last Host list owns the identities.
(function () {
  'use strict';

  function isDeleted(slot) {
    return !!(slot.tombstoned || slot.inconsistent);
  }

  function needsAttention(slot) {
    return isDeleted(slot) && !!(slot.inconsistent || slot.cleanupPending || slot.rebuildPending || slot.rebuildInProgress);
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
    if (badge.id === 'welcome-slot-sig') badge.dataset.lineLabel = sig ? sig.lineName + ' · Σ ' + sig.magicSum : '';
    if (!sig) return;
    var lo = Math.min.apply(null, sig.values), hi = Math.max.apply(null, sig.values);
    var bars = document.createDocumentFragment();
    sig.values.forEach(function(_, i) {
      var index = ((sig.offset || 0) + (sig.reversed ? -i : i) + sig.values.length) % sig.values.length;
      var value = sig.values[index];
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
    var gear = window.BootstrapSaveEquipment;
    var gearDetail = document.getElementById('save-equipment');
    var gearDetailKey;
    gear.connect(stage);
    var sigObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var row = entry.target;
        sigObserver.unobserve(row);
        if (list.contains(row)) paintSignature(row.querySelector('.slot-sig'), row.dataset.slot);
      });
    }, {root:list, rootMargin:'42px 0px'});

    function updateSignatures() {
      sigObserver.disconnect();
      var visible = !deleted && !!window.PM19Decor?.ready && rows.some(s => !s.corrupt);
      stage.classList.toggle('save-has-signatures', visible);
      if (visible) list.querySelectorAll('.save-row[data-state="live"]').forEach(row => {
        if (row.querySelector('.slot-sig:empty')) sigObserver.observe(row);
      });
    }
    window.addEventListener('pm19-decor-ready', updateSignatures);
    var createTools = document.getElementById('save-create-tools');
    var headerTools = createTools.parentElement;
    var buttons = document.getElementById('save-actions');
    var slots = [];
    var rows = [];
    var deleted = false;
    var selectedKey = '';
    var search = document.getElementById('save-search');
    var sort = document.getElementById('save-sort');
    var largeBusts = document.getElementById('save-large-busts');
    largeBusts.onclick = function () {
      var large = stage.classList.toggle('save-large-busts');
      largeBusts.setAttribute('aria-pressed', String(large));
      var active = list.querySelector('[aria-pressed="true"]');
      if (active) active.scrollIntoView({block:'nearest'});
    };
    var more = document.getElementById('save-more');
    var portrait = document.getElementById('save-detail-portrait');
    var technical = document.getElementById('save-technical');
    document.addEventListener('click', function (event) {
      if (more.open && (!more.contains(event.target) || event.target.closest('button'))) {
        more.open = false;
        if (more.contains(document.activeElement)) more.querySelector('summary').focus();
      }
    });
    search.oninput = render;
    sort.onchange = render;
    var pendingDelete = '';
    var pendingRename = '';

    function selected() {
      return rows.find(function (row) { return row.slot === selectedKey; });
    }

    function catalogName(slot) {
      var name = actions.primaryName(slot);
      if (isDeleted(slot) && name === slot.slot && /^cf7_[0-9a-f]{16,}$/i.test(name))
        return slot.rebuildInProgress || slot.rebuildPending ? '待确认的新角色' : '待清理的旧存档';
      return name;
    }

    function statusText(slot) {
      if (slot.rebuildPending) return '新角色待确认';
      if (slot.rebuildInProgress) return '建角未完成';
      if (slot.cleanupPending || slot.inconsistent) return '副本待清理';
      if (slot.tombstoned) return '已删除';
      if (slot.corrupt) return '需要修复';
      return '可选择';
    }

    function setText(id, value) { document.getElementById(id).textContent = value; }

    function drawGear(slot) {
      var usable = slot && !isDeleted(slot) && !slot.corrupt;
      var pieces = usable ? gear.pieces(slot.appearance) : [];
      var key = JSON.stringify([slot?.slot, pieces]);
      if (key !== gearDetailKey) {
        gearDetailKey = key;
        gear.release(gearDetail);
        gearDetail.replaceChildren(...pieces.map(piece => gear.tile(piece, true)));
      }
      gearDetail.hidden = !pieces.length;
      var hair = usable && slot.appearance?.hair;
      var meta = document.getElementById('save-character-meta');
      meta.textContent = !pieces.length && typeof hair === 'string' && !/^\d+$/.test(hair)
        ? hair.replace(/^发型-[男女]式-/, '') : '';
      meta.hidden = !meta.textContent;
    }

    function drawDetail() {
      var slot = selected();
      drawGear(slot);
      detail.hidden = !slot;
      empty.hidden = !!slot;
      headings.hidden = !slot;
      stage.classList.toggle('archive-empty', !slot);
      setText('save-empty-label', search.value.trim() ? '没有匹配的存档' : deleted ? '没有待处理的存档' : '暂无存档');
      var toolsParent = !slot && !deleted ? empty : headerTools;
      if (createTools.parentElement !== toolsParent) {
        var focused = createTools.contains(document.activeElement) && document.activeElement;
        if (toolsParent === empty) empty.appendChild(createTools);
        else headerTools.insertBefore(createTools, more);
        if (focused) focused.focus({preventScroll:true});
      }
      if (!slot) {
        window.BootstrapAppearance.releasePortrait(portrait);
        technical.open = false;
        return;
      }
      var protectedSlot = isDeleted(slot);
      var busy = slot.slot === pendingDelete;
      setText('save-title', catalogName(slot));
      detail.dataset.state = protectedSlot ? 'deleted' : slot.corrupt ? 'corrupt' : 'live';
      var character = catalogName(slot);
      var alias = actions.displayName(slot);
      var usable = !protectedSlot && !slot.corrupt;
      var stamp = slot.lastPlayed || slot.lastModified;
      window.BootstrapAppearance.bindPortrait(portrait, slot, character);
      setText('save-alias', alias !== character && alias !== slot.slot ? alias : '');
      var progress = [progressLabel(slot, character), slot.difficulty,
        Number.isInteger(slot.storyProgress) ? '主线 ' + slot.storyProgress : ''].filter(Boolean);
      setText('save-progress-detail', usable ? progress.join(' · ') : statusText(slot));
      var history = localTime(stamp);
      setText('save-history', history ? (slot.lastPlayed ? '最近游玩  ' : '最近保存  ') + history : '');
      detail.setAttribute('aria-label', character + '的存档操作');
      setText('save-key', slot.slot);
      setText('save-size', actions.formatBytes(slot.size) || '—');
      document.getElementById('save-title').title = character;
      var available = {
        start: !protectedSlot && !slot.corrupt,
        repair: !protectedSlot && slot.corrupt,
        undo: !protectedSlot && !!slot.editUndoToken,
        edit: !protectedSlot || slot.inconsistent,
        export: !protectedSlot || slot.inconsistent,
        rename: !protectedSlot,
        delete: !protectedSlot || ((slot.inconsistent || slot.cleanupPending) && !slot.rebuildPending && !slot.rebuildInProgress && actions.canCleanResidue()),
        rebuild: protectedSlot && !!(slot.rebuildInProgress || slot.rebuildPending)
      };
      Array.from(buttons.children).forEach(function (button) {
        var action = button.dataset.action;
        button.hidden = !available[action];
        button.disabled = busy || (action === 'delete' && !!pendingDelete) || (action === 'rename' && !!pendingRename);
        if (action === 'edit') button.textContent = protectedSlot ? '查看副本' : '编辑';
        if (action === 'delete') button.textContent = protectedSlot ? '清理残留' : actions.canDeleteFiles() ? '删除' : '移出列表';
        if (action === 'rename') button.textContent = slot.slot === pendingRename ? '重命名中…' : '重命名';
      });
    }

    function choose(index, focus) {
      var next = rows[index] ? rows[index].slot : '';
      if (next !== selectedKey) technical.open = false;
      selectedKey = next;
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
      var character = catalogName(slot);
      var display = actions.displayName(slot);
      var name = document.createElement('strong');
      name.textContent = character;
      name.title = character;
      var badge = document.createElement('span');
      badge.className = 'save-avatar';
      badge.setAttribute('aria-hidden', 'true');
      window.BootstrapAppearance.bindPortrait(badge, slot, character);
      var alias = document.createElement('span');
      alias.className = 'save-alias';
      alias.textContent = display === character || display === slot.slot ? '' : display;
      alias.title = alias.textContent;
      var equipment = document.createElement('span');
      equipment.className = 'save-gear-column save-row-gear';
      if (state === 'live') equipment.append(...gear.pieces(slot.appearance, true).map(piece => gear.tile(piece, false)));
      var signature = document.createElement('span');
      signature.className = 'save-sig-column';
      signature.setAttribute('aria-hidden', 'true');
      if (state === 'live') {
        var bars = document.createElement('span');
        bars.className = 'slot-sig';
        signature.appendChild(bars);
      }
      var identity = document.createElement('span');
      identity.className = 'save-identity';
      identity.append(name, alias);
      var progress = document.createElement('span');
      progress.className = 'save-progress';
      var value = progressLabel(slot, character);
      progress.textContent = state === 'live' ? value : statusText(slot);
      if (state === 'live' && Number.isInteger(slot.storyProgress)) progress.textContent += (value ? ' · ' : '') + '主线 ' + slot.storyProgress;
      progress.title = state === 'live' ? [slot.mainProgress, slot.difficulty, slot.appearance && slot.appearance.hair].filter(Boolean).join(' · ') : statusText(slot);
      var stamp = document.createElement('time');
      stamp.textContent = localTime(slot.lastPlayed || slot.lastModified) ? relativeTime(slot.lastPlayed || slot.lastModified) : '—';
      stamp.title = localTime(slot.lastPlayed || slot.lastModified);
      if (slot.lastPlayed || slot.lastModified) stamp.dateTime = slot.lastPlayed || slot.lastModified;
      button.append(badge, identity, equipment, progress, signature, stamp);
      return button;
    }

    function render() {
      var focusList = list.contains(document.activeElement) && document.activeElement.classList.contains('save-row');
      var focusedAction = buttons.contains(document.activeElement) && document.activeElement;
      var focusedPendingTab = document.activeElement === deletedTab;
      var priorScroll = list.scrollTop;
      var attention = slots.filter(needsAttention);
      var live = slots.filter(function (s) { return !isDeleted(s); });
      if (!attention.length) deleted = false;
      deletedTab.hidden = !attention.length;
      rows = deleted ? attention : live;
      setText('save-live-count', live.length);
      setText('save-deleted-count', attention.length);
      var query = search.value.trim().toLocaleLowerCase();
      rows = rows.filter(function (s) {
        return !query || [actions.primaryName(s), actions.displayName(s), s.slot].join(' ').toLocaleLowerCase().indexOf(query) >= 0;
      });
      if (sort.value === 'recent') rows.sort(function (a, b) {
        return (Date.parse(b.lastPlayed || b.lastModified) || 0) - (Date.parse(a.lastPlayed || a.lastModified) || 0);
      });
      if (sort.value === 'name') rows.sort(function (a, b) { return actions.primaryName(a).localeCompare(actions.primaryName(b), 'zh-CN'); });
      liveTab.setAttribute('aria-pressed', String(!deleted));
      deletedTab.setAttribute('aria-pressed', String(deleted));
      list.setAttribute('aria-label', deleted ? '待处理存档' : '我的存档');
      var index = rows.findIndex(function (s) { return s.slot === selectedKey; });
      if (index < 0) index = rows.length ? 0 : -1;
      var fragment = document.createDocumentFragment();
      rows.forEach(function (slot) { fragment.appendChild(rowButton(slot)); });
      list.querySelectorAll('.save-avatar').forEach(window.BootstrapAppearance.releasePortrait);
      gear.release(list);
      list.replaceChildren(fragment);
      stage.classList.toggle('save-has-equipment', !!list.querySelector('.save-equip'));
      updateSignatures();
      list.scrollTop = priorScroll;
      choose(index, focusList);
      if (!document.getElementById('view-slots').hidden) gear.prepare(stage);
      if (((focusList || focusedAction) && index < 0) || (focusedAction && (focusedAction.hidden || focusedAction.disabled))) {
        (deleted ? deletedTab : liveTab).focus();
      } else if (focusedPendingTab && deletedTab.hidden) {
        liveTab.focus({preventScroll:true});
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
      if (slot && button && !button.hidden && !button.disabled) actions.run(button.dataset.action, slot, catalogName(slot));
    };

    return {
      update: function (ordered) { slots = ordered; render(); },
      open: function (fromWelcome, preferredKey) {
        more.open = false;
        if (fromWelcome) { deleted = false; selectedKey = preferredKey || ''; technical.open = false; }
        render();
        var target = list.querySelector('.save-row[aria-pressed="true"]') || document.getElementById('btn-new');
        target.focus({preventScroll:true});
        if (list.contains(target)) target.scrollIntoView({block:'nearest'});
      },
      setDeletePending: function (key) { pendingDelete = key || ''; drawDetail(); },
      setRenamePending: function (key) { pendingRename = key || ''; drawDetail(); }
    };
  }

  window.BootstrapSaveManager = { create: create, isDeleted: isDeleted, needsAttention:needsAttention, localTime:localTime, relativeTime:relativeTime, progressLabel:progressLabel, paintSignature:paintSignature };
})();
