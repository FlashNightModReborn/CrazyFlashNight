/** 平板电脑 Web 面板（替代 Flash 平板电脑界面）
 *  视图：hub（主屏三入口+退出）→ infrastructure / contacts / encyclopedia
 *        encyclopedia → materials（材料大全只读）等六子项
 *  素材：launcher/web/assets/tablet/（tools/bake-tablet-assets.js 烘焙）
 *  数据：contacts.json / materials.json / infrastructure.json 静态烘焙；
 *        基建等级经 domain 'tablet' 的 snapshot/upgrade 走 AS2 权威
 *        （initData.infrastructure{name:level} 只是打开时的乐观注入，仍以回包为准）。
 *  跨层链路：Bridge.send {type:'panel', panel:'tablet', domain:'tablet', cmd, callId,
 *        panelInstanceId, payload:{v:1,...}} → Host TabletTask → AS2 gameCommands →
 *        socket task 'tablet_response' → panel_resp 回包（PanelRequestMux 关联）。
 */
(function () {
  'use strict';

  if (typeof Panels === 'undefined') return;

  var ASSETS = (typeof window !== 'undefined' && window.CF7_TABLET_ASSET_ROOT) || 'assets/tablet/';
  var VIEW_ORDER = ['hub', 'infrastructure', 'contacts', 'encyclopedia', 'materials'];

  var shell = null, stage = null, bg = null, overlay = null, tipEl = null;
  var backBtn = null, closeBtn = null, statusEl = null;
  var manifest = null, initData = {}, mux = null;
  var disposers = [];
  var currentView = 'hub';
  var data = { contacts: [], materials: [], infrastructure: [] };
  var infraLevels = {};           // name→level；{} = 未同步快照
  var infraSynced = false;        // 是否已收到 AS2 基建快照
  var upgradeBusy = false;        // 升级命令在途（防重发）
  var selectedContact = -1, selectedInfra = -1, selectedMaterial = -1;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function listen(node, ev, fn) {
    node.addEventListener(ev, fn);
    disposers.push(function () { node.removeEventListener(ev, fn); });
  }
  function status(text) { if (statusEl) statusEl.textContent = text || ''; }

  function vb(view) {
    var raw = manifest && manifest.viewBoxes && manifest.viewBoxes[view];
    if (!raw) return { x: 0, y: 0, w: 100, h: 100 };
    var p = String(raw).split(/[\s,]+/).map(Number);
    return { x: p[0], y: p[1], w: p[2] || 100, h: p[3] || 100 };
  }
  function hsStyle(view, box) {
    var v = vb(view);
    return 'left:' + ((box.x - v.x) / v.w * 100).toFixed(3) + '%;top:'
      + ((box.y - v.y) / v.h * 100).toFixed(3) + '%;width:'
      + (box.w / v.w * 100).toFixed(3) + '%;height:'
      + (box.h / v.h * 100).toFixed(3) + '%;';
  }
  function hotspot(view, box, label, fn, disabled) {
    var b = el('button', 'tablet-hotspot' + (disabled ? ' disabled' : ''));
    b.type = 'button';
    b.style.cssText = hsStyle(view, box);
    b.setAttribute('aria-label', label);
    b.title = label;
    listen(b, 'mouseenter', function () { tip(label); });
    listen(b, 'mouseleave', function () { tip(''); });
    if (disabled) { b.setAttribute('aria-disabled', 'true'); }
    else listen(b, 'click', fn);
    return b;
  }
  function tip(text) { if (tipEl) { tipEl.textContent = text || ''; tipEl.hidden = !text; } }

  // ── 受管域信封（domain:'tablet'）──
  function createMux() {
    if (typeof PanelRuntime === 'undefined' || !PanelRuntime.PanelRequestMux) return null;
    var m = new PanelRuntime.PanelRequestMux({
      send: function (msg) { return Bridge.send(msg); },
      router: PanelRuntime.sharedResponseRouter,
      callPrefix: 'tablet',
      timeoutMs: 8000,
      createMessage: function (context) {
        return {
          type: 'panel', panel: 'tablet', domain: 'tablet',
          panelInstanceId: String(initData.panelInstanceId || ''),
          cmd: context.entry.cmd,
          callId: context.entry.callId,
          payload: context.payload
        };
      },
      validateResponse: function (data, entry) {
        return !!data && data.type === 'panel_resp' && data.domain === 'tablet'
          && data.callId === entry.callId
          && (!data.cmd || data.cmd === entry.cmd);
      }
    });
    m.openSession({ panel: 'tablet' });
    return m;
  }
  function domainRequest(cmd, payload, options, callback) {
    if (!mux) return null;
    var body = { v: 1 };
    if (payload) for (var k in payload) if (payload.hasOwnProperty(k)) body[k] = payload[k];
    return mux.request(cmd, body, options, callback);
  }
  function respErrorText(resp) {
    var err = resp && resp.error;
    return ({
      unknown_infra: '未知基建项目', not_unlocked: '尚未解锁', max_level: '已达最大等级',
      skill_required: '技能等级不足', money_shortage: '金币不足', material_shortage: '材料不足',
      transaction_error: '事务异常（已回滚）', shop_unavailable: '商店不可用',
      busy: '请求在途', disconnected: '游戏未连接', timeout: '响应超时',
      delivery_unknown: '送达未知', unsupported_cmd: '不支持', panel_instance_expired: '面板实例已过期',
      tablet_unavailable: '平板服务不可用'
    })[err] || err || '失败';
  }

  function clearStage() {
    overlay.textContent = '';
    overlay.querySelectorAll('.tablet-hotspot,.tablet-dom').forEach(function (n) { n.remove(); });
  }

  function setView(name) {
    currentView = name;
    shell.setAttribute('data-view', name);
    bg.src = ASSETS + (name === 'hub' ? 'hub.svg' : 'view-' + name + '.svg');
    backBtn.hidden = name === 'hub';
    render();
  }

  // ── 各视图 ──
  function render() {
    clearStage(); status('');
    ({ hub: renderHub, infrastructure: renderInfra, contacts: renderContacts,
       encyclopedia: renderEnc, materials: renderMaterials })[currentView]();
  }

  function renderHub() {
    var h = manifest.hotspots || {};
    overlay.appendChild(hotspot('hub', h.nav_infrastructure, '基建', function () { setView('infrastructure'); }));
    overlay.appendChild(hotspot('hub', h.nav_contacts, '联络', function () { setView('contacts'); }));
    overlay.appendChild(hotspot('hub', h.nav_encyclopedia, '图鉴', function () { setView('encyclopedia'); }));
    overlay.appendChild(hotspot('hub', h.exit, '退出', requestClose));
  }

  function renderEnc() { renderEncHotspots(null); }

  // 图鉴六分类热点：在 encyclopedia 与 materials 视图共用（背景帧同版心）
  function renderEncHotspots(activeKey) {
    var h = manifest.encHotspots || {};
    var items = [
      ['sidequests', '支线查询'], ['materials', '材料大全'], ['characters', '角色信息'],
      ['texts', '文本收集'], ['units', '单位说明'], ['factions', '阵营信息']
    ];
    items.forEach(function (it) {
      var key = it[0], label = it[1];
      if (!h[key]) return;
      var ready = key === 'materials';
      var node = hotspot('encyclopedia', h[key], label + (ready ? '' : '（暂未接入）'),
        key === activeKey ? function () {}
          : ready ? function () { setView('materials'); }
          : function () { status(label + ' 档案尚未数字化'); });
      if (key === activeKey) node.classList.add('active');
      overlay.appendChild(node);
    });
  }

  function renderMaterials() {
    renderEncHotspots('materials');
    var list = el('div', 'tablet-dom tablet-mat-list');
    list.style.cssText = 'left:6%;top:18%;width:34%;bottom:14%;';
    var detail = el('div', 'tablet-dom tablet-mat-detail');
    detail.style.cssText = 'left:44%;top:18%;width:44%;bottom:14%;';
    data.materials.forEach(function (m, i) {
      var row = el('button', 'tablet-row' + (i === selectedMaterial ? ' selected' : ''));
      row.type = 'button';
      var ic = el('img', 'tablet-mat-icon'); ic.alt = '';
      if (typeof Icons !== 'undefined' && Icons.resolveStatic) {
        var u = Icons.resolveStatic(m.name); if (u) ic.src = u;
      }
      row.appendChild(ic);
      row.appendChild(el('span', '', m.name));
      if (m.infra) row.appendChild(el('em', 'tablet-mat-tag', '基建'));
      listen(row, 'click', function () { selectedMaterial = i; render(); });
      list.appendChild(row);
    });
    overlay.appendChild(list); overlay.appendChild(detail);
    var m = data.materials[selectedMaterial];
    if (m) {
      detail.appendChild(el('h3', '', m.name));
      detail.appendChild(el('p', 'tablet-dim', '类别 ' + m.typeId + (m.infra ? ' · 基建用途' : '')));
      var info = el('pre', 'tablet-mat-info', m.info || '暂无掉落情报');
      detail.appendChild(info);
    } else {
      detail.appendChild(el('p', 'tablet-dim', '← 选择左侧材料查看掉落情报'));
    }
    if (selectedMaterial < 0 && data.materials.length) { selectedMaterial = 0; render(); return; }
  }

  function renderContacts() {
    var cb = (manifest.contactBounds || {});
    var rows = cb.rows || [];
    // 行名覆盖在烘焙行槽位上（原版 列表0-7 位置精确还原）
    var list = el('div', 'tablet-dom tablet-contact-list');
    data.contacts.forEach(function (c, i) {
      var row = el('button', 'tablet-row tablet-contact-row' + (i === selectedContact ? ' selected' : ''));
      row.type = 'button'; row.textContent = c.name;
      if (rows[i]) row.style.cssText = hsStyle('contacts', rows[i]);
      listen(row, 'click', function () { selectedContact = i; render(); });
      list.appendChild(row);
    });
    overlay.appendChild(list);
    var side = el('div', 'tablet-dom tablet-contact-side');
    var px = cb.portrait;
    if (px) {
      side.style.cssText = hsStyle('contacts', px);
    } else {
      side.style.cssText = 'left:42%;top:16%;width:46%;bottom:16%;';
    }
    overlay.appendChild(side);

    var c = data.contacts[selectedContact];
    if (!c) { side.appendChild(el('p', 'tablet-dim', '← 选择联络对象')); return; }
    var face = el('div', 'tablet-contact-face');
    var img = el('img'); img.alt = c.name;
    face.appendChild(img);
    if (typeof ShopPortraits !== 'undefined' && ShopPortraits.mount) {
      ShopPortraits.mount(face, img, c.name);
    }
    side.appendChild(face);
    side.appendChild(el('h3', '', c.name));
    var actions = el('div', 'tablet-contact-actions');
    var shop = el('button', 'tablet-btn', '进入商店');
    shop.type = 'button';
    listen(shop, 'click', function () {
      status('正在呼叫商店…');
      // domain 'tablet' → AS2 tabletOpenNpcShop → openNpcShop(source='tablet_contacts')
      domainRequest('open_npc_shop', { shopId: c.shopId }, {}, function (resp) {
        status(resp && resp.ok === false || resp && resp.success === false
          ? '商店链路：' + respErrorText(resp) : '商店面板已受理');
      });
    });
    var rag = el('button', 'tablet-btn', '终端通信');
    rag.type = 'button';
    listen(rag, 'click', function () {
      status('正在接通终端…');
      domainRequest('open_ragchat', {}, {}, function (resp) {
        status(resp && resp.success === false
          ? '终端链路：' + respErrorText(resp) : '通信终端已受理');
      });
    });
    actions.appendChild(shop); actions.appendChild(rag);
    side.appendChild(actions);
    if (selectedContact < 0) { selectedContact = 0; render(); }
  }

  function renderInfra() {
    var list = el('div', 'tablet-dom tablet-infra-list');
    list.style.cssText = 'left:6%;top:18%;width:26%;bottom:14%;';
    var detail = el('div', 'tablet-dom tablet-infra-detail');
    detail.style.cssText = 'left:36%;top:18%;width:52%;bottom:14%;';
    var entries = infraSynced
      ? data.infrastructure.filter(function (it) { return infraLevels[it.name] != null; })
      : data.infrastructure;
    if (!entries.length && infraSynced) {
      detail.appendChild(el('p', 'tablet-dim', '尚未发现任何基建项目'));
      overlay.appendChild(list); overlay.appendChild(detail);
      return;
    }
    entries.forEach(function (it, i) {
      var lv = infraLevels[it.name];
      var row = el('button', 'tablet-row' + (i === selectedInfra ? ' selected' : ''));
      row.type = 'button';
      row.appendChild(el('span', '', it.name));
      row.appendChild(el('em', 'tablet-dim', lv == null ? '未解锁' : 'LV ' + lv + '/' + it.maxLevel));
      listen(row, 'click', function () { selectedInfra = i; render(); });
      list.appendChild(row);
    });
    overlay.appendChild(list); overlay.appendChild(detail);
    var it = entries[selectedInfra];
    if (!it) { detail.appendChild(el('p', 'tablet-dim', '← 选择设施查看')); return; }
    var lv = infraLevels[it.name];
    var cur = it.levels[lv] || it.levels[0];
    var next = lv == null ? null : it.levels[lv + 1];
    detail.appendChild(el('h3', '', it.name + '　' + (lv == null ? '未解锁' : 'LV ' + lv + '/' + it.maxLevel)));
    detail.appendChild(el('p', 'tablet-infra-desc', cur && cur.description || ''));
    if (lv != null && next) {
      var req = el('div', 'tablet-infra-req');
      req.appendChild(el('h4', '', '下一级需求'));
      if (next.price > 0) req.appendChild(el('p', '', '金币 × ' + next.price));
      next.materials.forEach(function (m) { req.appendChild(el('p', '', m.name + ' × ' + m.count)); });
      next.skills.forEach(function (s) { req.appendChild(el('p', '', '技能「' + s.name + '」≥ ' + s.level)); });
      detail.appendChild(req);
    }
    var btn = el('button', 'tablet-btn tablet-upgrade', '升级');
    btn.type = 'button';
    // 写权走 AS2 tabletInfraUpgrade 回环；无快照/未解锁/满级/在途均禁点
    btn.disabled = !infraSynced || lv == null || next == null || upgradeBusy;
    btn.title = btn.disabled
      ? (!infraSynced ? '等待基建快照…' : lv == null ? '尚未解锁' : next == null ? '已达最大等级' : '升级中…')
      : '提交升级请求（经 AS2 权威执行）';
    listen(btn, 'click', function () {
      if (upgradeBusy) return;
      upgradeBusy = true;
      status('升级请求已发送…');
      domainRequest('upgrade', { name: it.name },
        { kind: 'upgrade', write: true, singleFlight: true },
        function (resp) {
          upgradeBusy = false;
          if (resp && resp.infrastructure && typeof resp.infrastructure === 'object') {
            infraLevels = resp.infrastructure; infraSynced = true;
          }
          if (resp && resp.success) {
            status((resp.name || it.name) + ' 已升级' + (resp.level != null ? '至 LV ' + resp.level : ''));
          } else {
            // unknown 结果（超时/送达未知）禁止乐观显示，提示重读快照
            status(resp && resp.unknown
              ? '升级结果未知——以基地实际状态为准'
              : '升级失败：' + respErrorText(resp));
          }
          if (currentView === 'infrastructure') render();
        });
      render();
    });
    detail.appendChild(btn);
    detail.appendChild(el('p', 'tablet-dim',
      !infraSynced ? '等待 AS2 基建快照…' : ''));
    if (selectedInfra < 0) { selectedInfra = 0; render(); }
  }

  // domain snapshot：向 AS2 拉取权威基建等级快照
  function requestSnapshot() {
    domainRequest('snapshot', {}, { kind: 'snapshot', latestWins: true }, function (resp) {
      if (resp && resp.infrastructure && typeof resp.infrastructure === 'object') {
        infraLevels = resp.infrastructure;
        infraSynced = true;
      } else if (resp && resp.success === false) {
        status('基建快照：' + respErrorText(resp));
      }
      if (currentView === 'infrastructure') render();
    });
  }

  // ── 生命周期 ──
  function requestClose() {
    try { Panels.close(); } catch (e) {}
    try { Bridge.send({ type: 'panel', cmd: 'close', panel: 'tablet' }); } catch (e) {}
  }

  function createDOM() {
    shell = el('div', 'panel-scale-shell tablet-shell');
    stage = el('div', 'tablet-stage');
    bg = el('img', 'tablet-bg'); bg.alt = ''; bg.draggable = false;
    overlay = el('div', 'tablet-overlay');
    tipEl = el('div', 'tablet-tip'); tipEl.hidden = true;
    statusEl = el('div', 'tablet-status');
    backBtn = el('button', 'tablet-back', '◀ 返回'); backBtn.type = 'button'; backBtn.hidden = true;
    listen(backBtn, 'click', function () {
      setView(currentView === 'materials' ? 'encyclopedia' : 'hub');
    });
    closeBtn = el('button', 'tablet-close', '×'); closeBtn.type = 'button';
    closeBtn.setAttribute('aria-label', '关闭');
    listen(closeBtn, 'click', requestClose);
    stage.appendChild(bg); stage.appendChild(overlay);
    stage.appendChild(tipEl); stage.appendChild(backBtn); stage.appendChild(closeBtn); stage.appendChild(statusEl);
    shell.appendChild(stage);
    return shell;
  }

  function loadData() {
    return Promise.all([
      fetch(ASSETS + 'manifest.json').then(function (r) { return r.json(); }),
      fetch(ASSETS + 'contacts.json').then(function (r) { return r.json(); }),
      fetch(ASSETS + 'materials.json').then(function (r) { return r.json(); }),
      fetch(ASSETS + 'infrastructure.json').then(function (r) { return r.json(); })
    ]).then(function (r) {
      manifest = r[0]; data.contacts = r[1]; data.materials = r[2]; data.infrastructure = r[3];
    });
  }

  function onOpen(element, data) {
    initData = data || {};
    infraLevels = (initData.infrastructure && typeof initData.infrastructure === 'object')
      ? initData.infrastructure : {};
    infraSynced = !!initData.infrastructure;
    upgradeBusy = false;
    mux = createMux();
    status('载入平板数据…');
    loadData().then(function () {
      if (!shell.isConnected) return;
      status('');
      setView('hub');
      // 始终向 AS2 拉一次权威快照：initData 注入仅作打开前乐观投影
      requestSnapshot();
    }).catch(function () { status('平板数据载入失败'); });
    if (typeof PanelScale !== 'undefined') PanelScale.attach(shell, 1024, 576);
  }

  function cleanup() {
    if (mux) { try { mux.destroy(); } catch (e) {} mux = null; }
    disposers.splice(0).forEach(function (f) { try { f(); } catch (e) {} });
    manifest = null; selectedContact = selectedInfra = selectedMaterial = -1; currentView = 'hub';
    infraLevels = {}; infraSynced = false; upgradeBusy = false;
  }

  Panels.register('tablet', {
    create: createDOM,
    onOpen: onOpen,
    onRequestClose: requestClose,
    onClose: cleanup,
    onForceClose: cleanup
  });
})();
