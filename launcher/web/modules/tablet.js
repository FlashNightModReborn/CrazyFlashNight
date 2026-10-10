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

  var shell = null, stage = null, bg = null, bgAlt = null, overlay = null, hoverImg = null;
  var iconLayer = null, statusEl = null;
  var navIcons = {};                // DOM 化图标层（原 XFL 按钮与图标分离，迁移后同样分离才能复现位移/淡入）
  var ambientImgs = {};             // 常驻动画层（帧序列：退出乱码闪变 / 无人机）
  var ambientTimer = null;
  var manifest = null, initData = {}, mux = null;
  var disposers = [];
  var currentView = 'hub';
  var switching = false;            // 转场在途（原 XFL 按钮占用）
  var closingOnce = false;
  var NAV_KEYS = ['infrastructure', 'contacts', 'encyclopedia'];
  // 子视图里仅当前页图标保留（左上 = 重按返回），其余图标淡出；材料页图鉴图标作面包屑
  var VIEW_ACTIVE_ICON = {
    infrastructure: 'infrastructure', contacts: 'contacts',
    encyclopedia: 'encyclopedia', materials: 'encyclopedia'
  };
  var AMBIENT_KEYS = ['exitGlow', 'drone'];
  var TRANS_MS = 380;               // 原 XFL 进入/返回约 15 帧@30fps ≈ 0.5s，取 0.38s 近似
  var data = { contacts: [], materials: [], infrastructure: [] };
  var infraLevels = {};           // name→level；{} = 未同步快照
  var infraSynced = false;        // 是否已收到 AS2 基建快照
  var infraAssets = null;         // AS2 权威物资快照 {money, materials{name→n}, skills{name→lv}}
  var ragAvailable = false;       // AS2 快照的 npc_state_db_exists（原 XFL 终端通信显隐条件）
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
  // hoverKey：hub 三入口悬停时显示烘焙的悬停说明浮层（原 XFL 悬停说明 sprite，
  // 烘成 hover-*.svg 单件按烘焙包围盒盖在图标旁），其余热点无悬停说明
  function hotspot(view, box, label, fn, disabled, hoverKey) {
    var b = el('button', 'tablet-hotspot' + (disabled ? ' disabled' : ''));
    b.type = 'button';
    b.style.cssText = hsStyle(view, box);
    b.setAttribute('aria-label', label);
    if (hoverKey) {
      listen(b, 'mouseenter', function () { showHover(hoverKey); });
      listen(b, 'mouseleave', hideHover);
    }
    if (disabled) { b.setAttribute('aria-disabled', 'true'); }
    else listen(b, 'click', fn);
    return b;
  }
  function showHover(key) {
    var hb = manifest && manifest.hovers && manifest.hovers[key];
    if (!hb || !hoverImg) return;
    hoverImg.src = ASSETS + 'hover-' + key + '.svg';
    hoverImg.style.cssText = hsStyle('hub', hb);
    hoverImg.hidden = false;
    // 引导线遮罩扫入的近似：clip-path 左→右展开
    hoverImg.classList.remove('on');
    requestAnimationFrame(function () { hoverImg.classList.add('on'); });
  }
  function hideHover() {
    if (!hoverImg) return;
    hoverImg.classList.remove('on');
    hoverImg.hidden = true;
  }

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
    hideHover();
    render();
  }

  // ── 转场动画：复现原 XFL"图标飞到左上 + 内容淡入"——
  //    图标是独立 DOM 层（烘焙已把图标从背景剥离），切视图时先动图标位置，
  //    同时背景交叉淡化，转场结束才提交新视图的热点/内容 ──
  function viewBgSrc(name) { return ASSETS + (name === 'hub' ? 'hub.svg' : 'view-' + name + '.svg'); }
  function iconBoxCss(box) { return hsStyle('hub', box); } // 各视图共用同一 viewBox

  function applyIconPlaces(view) {
    var pl = (manifest.iconPlaces || {})[view] || {};
    NAV_KEYS.forEach(function (k) {
      var img = navIcons[k];
      if (!img || !pl[k]) return;
      img.style.cssText = iconBoxCss(pl[k]);
      if (img.hidden) return;   // 唤起交错未完成前只定位，点亮交给 onOpen 的 stagger
      // 子页中非当前图标淡出（原版这些图标在子视图 _visible=0 / 不可见）
      img.classList.toggle('shown', !VIEW_ACTIVE_ICON[view] || VIEW_ACTIVE_ICON[view] === k);
    });
  }

  // ── 常驻动画：帧序列按视图摆放（叉的「退出」乱码闪变、联络页无人机飞行），
  //    单一计时器驱动全部在屏图层，原速 = SWF 帧率 ──
  function applyAmbient(view) {
    var amb = (manifest && manifest.ambient) || {};
    AMBIENT_KEYS.forEach(function (key) {
      var meta = amb[key];
      var pl = meta && meta.places && meta.places[view];
      var img = ambientImgs[key];
      if (!pl) { if (img) img.hidden = true; return; }
      if (!img) {
        img = el('img', 'tablet-ambient');
        img.alt = ''; img.draggable = false;
        stage.insertBefore(img, overlay);
        ambientImgs[key] = img;
        for (var i = 1; i <= meta.frames; i++) {  // 预载，免首轮逐张取图
          var pre = new Image();
          pre.src = ASSETS + 'ambient/' + key + '/f' + (i < 10 ? '0' : '') + i + '.png';
        }
      }
      img.style.cssText = hsStyle(view, pl);
      img.src = ASSETS + 'ambient/' + key + '/f01.png';
      img.hidden = false;
    });
  }
  function startAmbient() {
    if (ambientTimer) return;
    ambientTimer = setInterval(function () {
      var now = Date.now();
      for (var key in ambientImgs) {
        var img = ambientImgs[key];
        var meta = manifest && manifest.ambient && manifest.ambient[key];
        if (!img || img.hidden || !meta || !meta.frames) continue;
        var fi = Math.floor(now * meta.fps / 1000) % meta.frames;
        if (img._fi !== fi) {
          img._fi = fi;
          img.src = ASSETS + 'ambient/' + key + '/f' + (fi + 1 < 10 ? '0' : '') + (fi + 1) + '.png';
        }
      }
    }, 40);
  }
  function crossfadeBg(name) {
    var src = viewBgSrc(name);
    if (!bgAlt) { bg.src = src; return; }
    bgAlt.classList.remove('on');
    bgAlt.src = src;
    bgAlt.hidden = false;
    requestAnimationFrame(function () { bgAlt.classList.add('on'); });
    setTimeout(function () {
      bg.src = src;
      bgAlt.classList.remove('on');
      bgAlt.hidden = true;
    }, TRANS_MS + 60);
  }
  function goTo(name) {
    if (switching || name === currentView) return;
    switching = true;
    stage.classList.add('switching', 'entered');
    applyIconPlaces(name);   // 图标位移先行，正是原版的飞行效果
    crossfadeBg(name);
    setTimeout(function () {
      setView(name);
      switching = false;
      stage.classList.remove('switching');
    }, TRANS_MS);
    // entered 保留到 DOM 淡入播完再摘，避免选行重渲染也重播入场
    setTimeout(function () { stage.classList.remove('entered'); }, TRANS_MS + 350);
  }
  // 关闭动画：原 XFL 按来源页播收起动画；近似为整体缩小淡出
  function exitWithAnim() {
    if (shell && !closingOnce) {
      closingOnce = true;
      shell.classList.add('closing');
      setTimeout(requestClose, 280);
    } else {
      requestClose();
    }
  }

  // ── 各视图 ──
  function render() {
    clearStage(); status('');
    applyIconPlaces(currentView);
    applyAmbient(currentView);
    ({ hub: renderHub, infrastructure: renderInfra, contacts: renderContacts,
       encyclopedia: renderEnc, materials: renderMaterials })[currentView]();
  }

  function renderHub() {
    var h = manifest.hotspots || {};
    overlay.appendChild(hotspot('hub', h.nav_infrastructure, '基建', function () { goTo('infrastructure'); }, false, 'nav_infrastructure'));
    overlay.appendChild(hotspot('hub', h.nav_contacts, '联络', function () { goTo('contacts'); }, false, 'nav_contacts'));
    overlay.appendChild(hotspot('hub', h.nav_encyclopedia, '图鉴', function () { goTo('encyclopedia'); }, false, 'nav_encyclopedia'));
    overlay.appendChild(hotspot('hub', h.exit, '退出', exitWithAnim));
  }

  // 子视图导航与原版一致（XFL 透明按钮层）：
  // 当前页图标移到左上充当"重按返回上一层"（材料页图鉴图标作面包屑返回图鉴页），
  // 叉除材料页外保留为退出；其余烘进背景的图标只作展示，不响应点击
  function wireSubNav() {
    var back = (manifest.viewBack || {})[currentView];
    if (back) {
      overlay.appendChild(hotspot(currentView, back, '重按按钮以返回选择界面', function () {
        goTo(currentView === 'materials' ? 'encyclopedia' : 'hub');
      }));
    }
    var exit = (manifest.exits || {})[currentView];
    if (exit) overlay.appendChild(hotspot(currentView, exit, '退出', exitWithAnim));
  }

  // 图鉴六分类按键暂不接入（用户要求先移除）：图鉴页只保留左上返回与退出
  function renderEnc() { wireSubNav(); }

  function renderMaterials() {
    wireSubNav();
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

  // 联络页（原 XFL 联络列表）：行点击只换 NPC头像；进入商店/终端通信是
  // 两个固定透明按钮盖在烘焙文字上（无 web 外框、无侧栏按钮）
  function renderContacts() {
    wireSubNav();
    var cb = (manifest.contactBounds || {});
    var rows = cb.rows || [];
    // 行直接挂 overlay：% 定位以舞台为锚（空容器会塌成 0×0 导致行不可见）
    data.contacts.forEach(function (c, i) {
      var row = el('button', 'tablet-dom tablet-contact-row' + (i === selectedContact ? ' selected' : ''));
      row.type = 'button'; row.textContent = c.name;
      if (rows[i]) row.style.cssText = hsStyle('contacts', rows[i]);
      listen(row, 'click', function () { selectedContact = i; render(); });
      overlay.appendChild(row);
    });
    if (selectedContact < 0 && data.contacts.length) selectedContact = 0;
    var c = data.contacts[selectedContact];
    if (!c) return;
    var face = el('div', 'tablet-dom tablet-contact-face');
    if (cb.portrait) face.style.cssText = hsStyle('contacts', cb.portrait);
    if (c.portrait) {
      // 原 XFL：loadMovie 原图 + 头像框 overflow 裁剪（不压缩原图）。
      // PNG 是 400×400 原尺寸，天然比例 1:1，等比 cover 铺满 200×200 框。
      var img = el('img'); img.alt = c.name; img.draggable = false;
      img.src = ASSETS + c.portrait;
      face.appendChild(img);
    }
    overlay.appendChild(face);
    // domain 'tablet' → AS2 tabletOpenNpcShop → openNpcShop(source='tablet_contacts')
    // 按钮字形在原版是 EditText（ffdec 帧导出不产 text def，烘焙只剩边框），
    // 用 DOM 文字盖在烘焙边框上补回标签
    if (cb.shop) {
      overlay.appendChild(hotspot('contacts', cb.shop, '进入商店', function () {
        status('正在呼叫商店…');
        domainRequest('open_npc_shop', { shopId: c.shopId }, {}, function (resp) {
          status(resp && resp.success === false
            ? '商店链路：' + respErrorText(resp) : '商店面板已受理');
        });
      }));
      var shopText = el('div', 'tablet-dom tablet-contact-btnlabel', '进入商店');
      shopText.style.cssText = hsStyle('contacts', cb.shop);
      overlay.appendChild(shopText);
    }
    // domain 'tablet' → AS2 openRagTerminal → agent.启动外部RAG工具
    // 原 XFL 按 npc_state_db_exists 显隐：快照未给出可用信号时不渲染按钮
    if (cb.ragchat && ragAvailable) {
      overlay.appendChild(hotspot('contacts', cb.ragchat, '终端通信', function () {
        status('正在接通终端…');
        domainRequest('open_ragchat', {}, {}, function (resp) {
          status(resp && resp.success === false
            ? '终端链路：' + respErrorText(resp) : '通信终端已受理');
        });
      }));
      var ragText = el('div', 'tablet-dom tablet-contact-btnlabel', '终端通信');
      ragText.style.cssText = hsStyle('contacts', cb.ragchat);
      overlay.appendChild(ragText);
    }
  }

  // 升级需求文本（原 XFL 打印基建升级需求：当前等级数据=Level[当前等级]，即升到下一级的成本）
  // 附带 所需/拥有 显示（参考合成界面惯例），拥有数来自权威 assets 快照
  function upgradeReqText(it, lv) {
    var t = '当前等级：' + (lv == null ? 0 : lv);
    if (lv == null || lv >= it.maxLevel) return t + '，已达到最大等级。';
    var d = it.levels[lv] || {};
    t += '，升到下一级需要：';
    if (d.price > 0) {
      t += '\n金币 * ' + d.price;
      if (infraAssets) t += '（拥有 ' + (infraAssets.money || 0) + '）';
    }
    if (d.materials && d.materials.length) {
      t += '\n' + d.materials.map(function (m) {
        var own = infraAssets && infraAssets.materials ? (infraAssets.materials[m.name] || 0) : null;
        return m.name + '#' + m.count + (own == null ? '' : '（拥有 ' + own + '）');
      }).join(', ');
    }
    (d.skills || []).forEach(function (s) {
      var cur = infraAssets && infraAssets.skills ? infraAssets.skills[s.name] : null;
      t += '\n技能[' + s.name + ']达到 ' + s.level + ' 级'
        + (cur == null ? '' : '（当前 ' + cur + ' 级）');
    });
    return t;
  }
  // 写权走 AS2 tabletInfraUpgrade 回环；unknown 结果不乐观显示
  function doUpgrade(it) {
    if (!it || upgradeBusy) return;
    upgradeBusy = true;
    domainRequest('upgrade', { name: it.name },
      { kind: 'upgrade', write: true, singleFlight: true },
      function (resp) {
        upgradeBusy = false;
        if (resp && resp.infrastructure && typeof resp.infrastructure === 'object') {
          infraLevels = resp.infrastructure; infraSynced = true;
        }
        if (resp && resp.assets && typeof resp.assets === 'object') infraAssets = resp.assets;
        if (resp && resp.ragAvailable === true) ragAvailable = true;
        if (resp && resp.ragAvailable === false) ragAvailable = false;
        if (resp && resp.success) {
          status((resp.name || it.name) + ' 已升级' + (resp.level != null ? '至 LV ' + resp.level : ''));
        } else {
          status(resp && resp.unknown
            ? '升级结果未知——以基地实际状态为准'
            : '升级失败：' + respErrorText(resp));
        }
        if (currentView === 'infrastructure') render();
      });
    render();
    status('升级请求已发送…');
  }

  // 基建页（原 XFL 基建内容整体）：左 = 滑动按钮栏行覆盖槽位，
  // 右 = 名字/简介/升级需求对准烘焙文本框，升级 = 透明按钮盖在烘焙按钮上
  function renderInfra() {
    wireSubNav();
    var ib = manifest.infraBounds || {};
    var rowBoxes = manifest.infraRows || [];
    var entries = infraSynced
      ? data.infrastructure.filter(function (it) { return infraLevels[it.name] != null; })
      : data.infrastructure;
    var list = el('div', 'tablet-dom tablet-infra-list');
    if (ib.list) list.style.cssText = hsStyle('infrastructure', ib.list);
    // 行高/行距沿用烘焙槽位几何（% 相对列表容器高），超出 8 项在槽位容器内滚动
    if (rowBoxes.length > 1 && ib.list) {
      list.style.setProperty('--row-h', (rowBoxes[0].h / ib.list.h * 100).toFixed(3) + '%');
      list.style.setProperty('--row-gap',
        ((rowBoxes[1].y - rowBoxes[0].y - rowBoxes[0].h) / ib.list.h * 100).toFixed(3) + '%');
    }
    entries.forEach(function (it, i) {
      var row = el('button', 'tablet-infra-row' + (i === selectedInfra ? ' selected' : ''));
      row.type = 'button'; row.textContent = it.name;
      listen(row, 'click', function () { selectedInfra = i; render(); });
      list.appendChild(row);
    });
    overlay.appendChild(list);

    // 烘焙滚动条（rail/thumb）只作视觉底；在其上叠透明拖拽热点驱动 list.scrollTop——
    // 原版 scrollbutton 拖动语义；无内容可滚时拖拽自然无位移
    if (ib.thumb && ib.rail) {
      var maxScrollTop = function () { return Math.max(0, list.scrollHeight - list.clientHeight); };
      // 可见滑块：烘焙 thumb 只是初始帧，滚动时需要跟随 thumb 位置的可视层
      var thumbEl = el('div', 'tablet-dom tablet-infra-thumb');
      var vbInfra = vb('infrastructure');
      var railY = (ib.rail.y - vbInfra.y) / vbInfra.h * 100;
      var thumbH = ib.thumb.h / vbInfra.h * 100;
      thumbEl.style.left = ((ib.thumb.x - vbInfra.x) / vbInfra.w * 100).toFixed(3) + '%';
      thumbEl.style.width = (ib.thumb.w / vbInfra.w * 100).toFixed(3) + '%';
      thumbEl.style.height = thumbH.toFixed(3) + '%';
      var railRange = ib.rail.h - ib.thumb.h;
      var syncThumb = function () {
        var frac = maxScrollTop() > 0 ? list.scrollTop / maxScrollTop() : 0;
        thumbEl.style.top = ((ib.rail.y + railRange * frac - vbInfra.y) / vbInfra.h * 100).toFixed(3) + '%';
      };
      syncThumb();
      listen(list, 'scroll', syncThumb);
      overlay.appendChild(thumbEl);
      var drag = hotspot('infrastructure', ib.rail, '滚动条', function () {});
      drag.style.cursor = 'ns-resize';
      var dragStartY = 0, dragStartScroll = 0, dragging = false;
      var onMove = function (ev) {
        if (!dragging) return;
        var scrollable = maxScrollTop();
        var trackPx = Math.max(1, drag.clientHeight - thumbEl.clientHeight);
        list.scrollTop = dragStartScroll + (ev.clientY - dragStartY) / trackPx * scrollable;
      };
      var onUp = function () { dragging = false; };
      listen(drag, 'mousedown', function (ev) {
        dragging = true; dragStartY = ev.clientY; dragStartScroll = list.scrollTop;
        ev.preventDefault();
      });
      listen(document, 'mousemove', onMove);
      listen(document, 'mouseup', onUp);
      overlay.appendChild(drag);
    }

    if (selectedInfra < 0) selectedInfra = 0;
    var it = entries[selectedInfra];
    var lv = it ? infraLevels[it.name] : null;
    var nameEl = el('div', 'tablet-dom tablet-infra-name', it ? it.name : '');
    if (ib.name) nameEl.style.cssText = hsStyle('infrastructure', ib.name);
    overlay.appendChild(nameEl);
    var descEl = el('div', 'tablet-dom tablet-infra-desc');
    if (ib.desc) descEl.style.cssText = hsStyle('infrastructure', ib.desc);
    overlay.appendChild(descEl);
    var reqEl = el('div', 'tablet-dom tablet-infra-req');
    if (ib.req) reqEl.style.cssText = hsStyle('infrastructure', ib.req);
    overlay.appendChild(reqEl);
    if (it) {
      var cur = it.levels[lv] || it.levels[0];
      descEl.textContent = (cur && cur.description) || '';
      reqEl.textContent = upgradeReqText(it, lv);
    } else {
      descEl.textContent = infraSynced ? '尚未发现任何基建项目' : '点击左侧列表查看基建内容';
    }
    // 升级：透明热点盖烘焙的基建升级按钮；无快照/未解锁/满级/在途禁点
    if (ib.upgrade) {
      var canUp = !!(it && infraSynced && lv != null && lv < it.maxLevel && !upgradeBusy);
      overlay.appendChild(hotspot('infrastructure', ib.upgrade, '升级',
        function () { doUpgrade(it); }, !canUp));
    }
  }

  // domain snapshot：向 AS2 拉取权威基建等级快照
  function requestSnapshot() {
    domainRequest('snapshot', {}, { kind: 'snapshot', latestWins: true }, function (resp) {
      if (resp && resp.infrastructure && typeof resp.infrastructure === 'object') {
        infraLevels = resp.infrastructure;
        infraSynced = true;
      }
      if (resp && resp.assets && typeof resp.assets === 'object') infraAssets = resp.assets;
      if (resp && resp.ragAvailable === true) ragAvailable = true;
      if (resp && resp.ragAvailable === false) ragAvailable = false;
      if (resp && resp.success === false) {
        status('基建快照：' + respErrorText(resp));
      }
      // 基建页刷新需求行；联络页按 ragAvailable 补/撤终端通信按钮
      if (currentView === 'infrastructure' || currentView === 'contacts') render();
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
    bgAlt = el('img', 'tablet-bg tablet-bg-alt'); bgAlt.alt = ''; bgAlt.draggable = false; bgAlt.hidden = true;
    iconLayer = el('div', 'tablet-icons');
    NAV_KEYS.forEach(function (k) {
      var img = el('img', 'tablet-icon');
      img.alt = ''; img.draggable = false; img.hidden = true;
      img.src = ASSETS + 'nav-' + k + '.svg';
      navIcons[k] = img;
      iconLayer.appendChild(img);
    });
    overlay = el('div', 'tablet-overlay');
    hoverImg = el('img', 'tablet-hoverdesc'); hoverImg.alt = ''; hoverImg.draggable = false; hoverImg.hidden = true;
    statusEl = el('div', 'tablet-status');
    stage.appendChild(bg); stage.appendChild(bgAlt); stage.appendChild(iconLayer);
    stage.appendChild(overlay); stage.appendChild(hoverImg); stage.appendChild(statusEl);
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
      // 唤起动画近似：原 XFL"轻按屏幕→中心展开→三图标依次淡入"
      shell.classList.add('entering');
      NAV_KEYS.forEach(function (k, i) {
        var img = navIcons[k];
        if (!img) return;
        img.hidden = false;
        img.style.transitionDelay = (160 + i * 70) + 'ms';
        requestAnimationFrame(function () { img.classList.add('shown'); });
      });
      requestAnimationFrame(function () { shell.classList.remove('entering'); });
      setTimeout(function () {
        NAV_KEYS.forEach(function (k) { if (navIcons[k]) navIcons[k].style.transitionDelay = '0ms'; });
      }, 900);
      startAmbient();
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
    switching = false; closingOnce = false;
    if (ambientTimer) { clearInterval(ambientTimer); ambientTimer = null; }
    for (var key in ambientImgs) { try { ambientImgs[key].remove(); } catch (e) {} }
    ambientImgs = {};
    if (shell) shell.classList.remove('entering', 'closing');
    if (stage) stage.classList.remove('switching');
    NAV_KEYS.forEach(function (k) {
      var img = navIcons[k];
      if (img) { img.classList.remove('shown'); img.hidden = true; }
    });
    if (bgAlt) { bgAlt.classList.remove('on'); bgAlt.hidden = true; }
    if (hoverImg) hoverImg.classList.remove('on');
  }

  Panels.register('tablet', {
    create: createDOM,
    onOpen: onOpen,
    onRequestClose: requestClose,
    onClose: cleanup,
    onForceClose: cleanup
  });
})();
