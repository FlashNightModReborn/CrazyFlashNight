// Read-only equipment inspection for the front door. Item names come from the slot, artwork
// and authored descriptions from the game catalogs. No actor or Flash connection is required.
(function () {
  'use strict';
  const weaponSlots = [
    ['primary','长枪','枪'], ['melee','刀','刀'], ['secondary1','手枪一','枪'], ['secondary2','手枪二','枪'],
    ['grenade','手雷','雷']
  ];
  const armorSlots = [
    ['body','上装','甲'], ['head','头部','盔'], ['hand','手部','手'],
    ['neck','颈部','饰'], ['leg','下装','裤'], ['foot','脚部','靴']
  ];
  const statLabels = {power:'威力', defence:'防御', damage:'伤害加成', hp:'HP', mp:'MP'};
  let catalog = null, pending = null;
  let scope, pinned;
  const bindings = new WeakSet();

  function pieces(appearance, compact) {
    const outfit = window.BootstrapAppearance.outfit(appearance || {}) || {};
    const worn = ([field]) => typeof outfit[field] === 'string' && outfit[field].trim();
    const weapons = weaponSlots.filter(worn), armor = armorSlots.filter(worn);
    let shown = weapons.concat(armor);
    if (compact) shown = weapons.length && armor.length ? [weapons[0], armor[0]] : shown.slice(0, 2);
    return shown.map(([field, label, glyph]) => ({field, label, glyph, name:outfit[field]}));
  }

  function record(name) {
    return catalog && Object.hasOwn(catalog, name) ? catalog[name] : null;
  }

  function paint(tile) {
    const name = tile.dataset.item;
    const info = record(name);
    tile.setAttribute('aria-label', tile.dataset.slotLabel + ' · ' + (info?.label || name));
    const url = window.Icons?.resolveStatic(info?.icon || name);
    if (!url || tile.dataset.iconUrl === url) return;
    tile.dataset.iconUrl = url;
    const img = document.createElement('img');
    img.alt = '';
    img.loading = 'lazy';
    img.decoding = 'async';
    img.onload = () => { if (img.parentElement === tile) tile.classList.add('has-art'); };
    img.onerror = () => { if (img.parentElement === tile) { tile.classList.remove('has-art'); img.remove(); } };
    tile.classList.remove('has-art');
    tile.replaceChildren(img);
    img.src = url;
  }

  function prepare(stage) {
    if (catalog || pending || !stage.querySelector('.save-equip')) return;
    const index = fetch('generated/archive-equipment.json').then(response => {
      if (!response.ok) throw new Error('archive equipment reference unavailable');
      return response.json();
    }).then(data => {
      if (data.version === 1 && data.items && typeof data.items === 'object') catalog = data.items;
    }).catch(() => {}); // Old or incomplete installations can still inspect the exact saved name.
    pending = Promise.all([index, new Promise(resolve => window.Icons ? window.Icons.load(resolve) : resolve())])
      .then(() => {
        stage.querySelectorAll('.save-equip').forEach(paint);
        if (pinned?.isConnected && window.PanelTooltip?.isVisible(pinned)) {
          window.PanelTooltip.updateContent(tooltip(pinned), pinned);
        }
      }).finally(() => { pending = null; });
  }

  function tooltip(tile) {
    const info = record(tile.dataset.item);
    const title = info?.label || tile.dataset.item;
    const intro = [info?.use || tile.dataset.slotLabel];
    if (Number.isFinite(info?.level)) intro.push('等级限制 ' + info.level);
    if (info?.set) intro.push(info.set);
    const sections = [{role:'intro', runs:[{text:intro.join(' · ')}]}];
    if (info) {
      const stats = Object.entries(statLabels).filter(([key]) => info[key])
        .map(([key,label]) => label + ' ' + info[key]);
      if (stats.length) sections.push({role:'intro', runs:[{text:'基础属性　' + stats.join(' · ')}]});
      if (info.description) {
        const runs = window.PanelTooltipDocument?.flattenMarkup(info.description) || [{text:info.description}];
        sections.push({role:'description', runs});
      }
    }
    const icon = info?.icon || tile.dataset.item;
    const doc = {version:1, title, profile:'dense', layoutType:'wide', icon:{kind:'item',name:icon}, sections};
    // The document renderer escapes titles and runs, including names from imported saves.
    return window.PanelTooltip.buildItemRichHtml({document:doc, iconUrl:window.Icons?.resolveStatic(icon),
      introWebHTML:escapeText(title + ' · ' + intro.join(' · '))});
  }

  function escapeText(text) {
    const node = document.createElement('span');
    node.textContent = text;
    return node.innerHTML;
  }

  function connect(stage) {
    scope = window.PanelTooltip.createScope('bootstrap-archive-equipment', {profile:window.PanelTooltip.profiles.dense});
    function bind(event) {
      const tile = event.target.closest?.('.save-equip');
      if (!tile || bindings.has(tile)) return;
      bindings.add(tile);
      scope.bindAsync(tile, {
        key:tile.dataset.item, item:tile, placement:tile.closest('#save-detail') ? 'left' : 'right',
        renderBasic:tooltip, renderRich:tooltip,
        fetch:(_tile, done) => Promise.resolve(pending).then(() => done({success:true}))
      });
    }
    stage.addEventListener('pointerover', bind, true);
    stage.addEventListener('focusin', bind, true);
    stage.addEventListener('click', event => {
      const tile = event.target.closest('button.save-equip');
      if (!tile) return;
      pinned = tile;
      window.PanelTooltip.showPinned(tooltip(tile), tile, {
        owner:tile, placement:'left', title:record(tile.dataset.item)?.label || tile.dataset.item
      });
    });
  }

  function release(root) {
    if (pinned && root.contains(pinned)) { window.PanelTooltip.hide(pinned); pinned = null; }
    if (scope) scope.releaseTree(root);
  }

  function tile(piece, detail) {
    const el = document.createElement(detail ? 'button' : 'span');
    if (detail) el.type = 'button';
    else el.setAttribute('role','img');
    el.className = 'save-equip';
    el.dataset.item = piece.name;
    el.dataset.slotLabel = piece.label;
    el.dataset.glyph = piece.glyph;
    paint(el);
    return el;
  }

  window.BootstrapSaveEquipment = {pieces, tile, connect, prepare, release};
})();
