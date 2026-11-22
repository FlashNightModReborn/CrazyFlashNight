/**
 * 阵营配置 — 欢迎页阵营标识数据源
 *
 * 新增阵营只需要往 FACTIONS 里 push 一个对象。字段：
 *   name / enName       — 显示名（中文 / 英文）
 *   baseStatus          — 基础状态: 'sync' | 'standby' | 'offline'
 *                         本次加载被选为 active 的阵营一律显示 'sync'（覆盖 baseStatus）
 *   color / colorDim    — 主色 / 衰减色（用于 rune 描边、右栏点状状态灯）
 *   slogan              — 阵营标语（显示在 active-brand 标签下）
 *   rune                — 中部分割线 SVG 字符串（viewBox 建议 0 0 500 24）
 *                         设计原则：每阵营独立视觉符号，道教母题只分配给黑铁会
 *
 * 渲染入口（挂到 window.Factions）:
 *   Factions.pickActive()                   — 随机返回一个阵营 key
 *   Factions.renderDivider(key, elementId)
 *   Factions.renderList(activeKey, elementId)
 *   Factions.renderActiveBrand(key, elementId)
 *   Factions.init(elementIds)               — 一次性渲染（默认随机 active），返回 activeKey
 *
 * 调试 hotkey：默认关闭。设 window.__FACTION_DEBUG = true 开启按 F 循环预览。
 */

(function () {
  const archiveFontStack = window.CF7FontCatalog && typeof window.CF7FontCatalog.role === 'function'
    ? window.CF7FontCatalog.role('web.intelligence.archive')
    : "STSong, SimSun, serif";
  const FACTIONS = {
    iron: {
      name: '黑铁会',
      enName: 'IRON SOCIETY',
      baseStatus: 'standby',
      color: '#d45848',
      colorDim: '#7d2418',
      slogan: '天地有呼吸 · 政教合一',
      quotes: [
        '“那不是电波，是天地这口大钟的呼吸。”',
        '“此剑有余响，非风声，非剑鸣——乃回声也。”',
        '“经脉有时候嗡嗡响。管它呢，不影响砍人。”'
      ],
      rune: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 24" preserveAspectRatio="none" style="width:100%;height:100%">
        <g stroke="#b83a2e" stroke-width=".9" fill="none">
          <path d="M 0 12 L 218 12 M 282 12 L 500 12"/>
          <circle cx="250" cy="12" r="9"/>
          <circle cx="250" cy="12" r="11" opacity=".45"/>
          <text x="250" y="16.5" text-anchor="middle" fill="#b83a2e"
                font-family='${archiveFontStack}' font-size="11" font-weight="700">道</text>
          <g stroke="#c8b28a" stroke-width=".5">
            <path d="M 232 8 L 237 8 M 232 12 L 234 12 M 235 12 L 237 12 M 232 16 L 237 16"/>
            <path d="M 263 8 L 268 8 M 263 12 L 265 12 M 266 12 L 268 12 M 263 16 L 268 16"/>
          </g>
        </g>
      </svg>`
    },

    noah: {
      name: '诺亚',
      enName: 'NOAH',
      baseStatus: 'standby',
      color: '#3dd5ff',
      colorDim: '#1e90b3',
      slogan: '半张地图',
      quotes: [
        '“导波网络重锁周期约 1.3 秒，耦合超出预期。”',
        '“‘自我’不过是真空里的皱褶，我只是把它抹平。”',
        '“高阶耦合出现目标静止；建议增加环境屏蔽。”'
      ],
      rune: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 24" preserveAspectRatio="none" style="width:100%;height:100%">
        <g stroke="#3dd5ff" stroke-width=".9" fill="none">
          <path d="M 0 12 L 215 12 M 285 12 L 500 12"/>
          <path d="M 250 3 L 264 20 L 236 20 Z"/>
          <path d="M 250 3 L 250 20" stroke-dasharray="1.5 2" opacity=".7"/>
          <g stroke-width=".55" opacity=".85">
            <path d="M 222 9 L 222 15 M 227 10 L 227 14 M 232 11 L 232 13"/>
            <path d="M 268 11 L 268 13 M 273 10 L 273 14 M 278 9 L 278 15"/>
          </g>
        </g>
      </svg>`
    },

    univ: {
      name: '联合大学',
      enName: 'UNITED UNIV.',
      baseStatus: 'standby',
      color: '#cbba93',
      colorDim: '#85775e',
      slogan: '网络意识生态',
      quotes: [
        '“一切能量屏障都只是有待求解的方程式。”',
        '“玩弄认知能像塑造物质一样精确地塑造现实。”',
        '“掌握蓝图，就等于掌握通往所有造物的后门。”'
      ],
      rune: '<span class="univ-divider" aria-hidden="true"></span>'
    },

    mercenary: {
      name: 'A兵团',
      enName: 'A-CORPS',
      baseStatus: 'standby',
      color: '#d4be8e',
      colorDim: '#6a5f48',
      slogan: '打出去有效果就行',
      quotes: [
        '“别问原理，知道这东西是真的、会越来越多就行。”',
        '“别看那根蓝柱子，那玩意儿早断了。”',
        '“那一拳打出去，空气好像变硬了——有效就行。”'
      ],
      rune: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 24" preserveAspectRatio="none" style="width:100%;height:100%">
        <g fill="none">
          <path d="M 0 12 L 222 12 M 278 12 L 500 12" stroke="#c8b28a" stroke-width=".9"/>
          <g stroke="#c8b28a" stroke-width="1.4" stroke-linecap="square">
            <path d="M 242 4 L 258 20"/>
            <path d="M 258 4 L 242 20"/>
          </g>
          <path d="M 242 4 L 240 7 L 244 7 Z M 258 4 L 256 7 L 260 7 Z M 242 20 L 240 17 L 244 17 Z M 258 20 L 256 17 L 260 17 Z"
                fill="#c8b28a" stroke="none"/>
          <g stroke="#8a7c5e" stroke-width=".8">
            <path d="M 215 7 L 215 17 M 219 8 L 219 16 M 223 9 L 223 15 M 227 10 L 227 14"/>
            <path d="M 273 10 L 273 14 M 277 9 L 277 15 M 281 8 L 281 16 M 285 7 L 285 17"/>
          </g>
        </g>
      </svg>`
    },

    skynet: {
      name: '天网残余',
      enName: 'SKYNET SUBSTRATE',
      baseStatus: 'offline',
      color: '#88ad64',
      colorDim: '#3d4d2d',
      isLog: true,
      slogan: '环境基底残余日志',
      quotes: [
        '[WARNING] 异常能量波动：超出白名单阈值',
        '[UNKNOWN] 非注册信息结构 · 匹配率 < 12%',
        '[ERROR] 中枢响应超时 · 基站维持 1.3s 同步'
      ],
      rune: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 24" preserveAspectRatio="none" style="width:100%;height:100%">
        <g stroke="#7a9a5a" fill="none">
          <path d="M 0 12 L 215 12 M 285 12 L 500 12" stroke-width=".7" stroke-dasharray="6 3" opacity=".75"/>
          <circle cx="250" cy="12" r="6.5" stroke-width=".9"/>
          <circle cx="250" cy="12" r="2" stroke-width=".8"/>
          <g stroke-width=".9">
            <path d="M 250 3.5 L 250 5.5 M 250 18.5 L 250 20.5 M 241 12 L 243 12 M 257 12 L 259 12"/>
            <path d="M 243.5 5.5 L 245 7 M 256.5 5.5 L 255 7 M 243.5 18.5 L 245 17 M 256.5 18.5 L 255 17"/>
          </g>
          <circle cx="244" cy="12" r=".8" fill="#7a9a5a" stroke="none"/>
          <circle cx="256" cy="12" r=".8" fill="#7a9a5a" stroke="none"/>
        </g>
      </svg>`
    }
  };

  const STATUS_LABEL = { sync: '同步中', standby: '待机', offline: '离线' };
  const quoteCursor = {};

  function pickQuote(key) {
    const f = FACTIONS[key];
    if (!f || !Array.isArray(f.quotes) || !f.quotes.length) return f ? f.slogan : '';
    if (quoteCursor[key] === undefined) {
      quoteCursor[key] = Math.floor(Math.random() * f.quotes.length);
    } else {
      quoteCursor[key] = (quoteCursor[key] + 1) % f.quotes.length;
    }
    return f.quotes[quoteCursor[key]];
  }

  function pickActive() {
    const keys = Object.keys(FACTIONS);
    return keys[Math.floor(Math.random() * keys.length)];
  }

  function renderDivider(key, containerId) {
    const el = document.getElementById(containerId);
    if (!el || !FACTIONS[key]) return;
    el.innerHTML = FACTIONS[key].rune;
    el.dataset.faction = key;
  }

  function renderList(activeKey, containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;
    el.innerHTML = Object.entries(FACTIONS).map(([k, f]) => {
      const status = (k === activeKey) ? 'sync' : f.baseStatus;
      const dotColor = status === 'sync' ? f.color : f.colorDim;
      const glow = status === 'sync' ? `box-shadow:0 0 6px ${f.color}` : '';
      const nameStyle = k === activeKey ? ' style="color:#d4d8dc"' : '';
      const statStyle = status === 'sync' ? ` style="color:${f.color}"` : '';
      const sample = (f.quotes && f.quotes[0]) || f.slogan;
      return '<div class="f" title="' + sample + '">'
           +   '<span class="dot" style="background:' + dotColor + ';' + glow + '"></span>'
           +   '<span class="f-name"' + nameStyle + '>' + f.name + '</span>'
           +   '<span class="f-sep">·</span>'
           +   '<span class="f-term"' + statStyle + '>' + sample + '</span>'
           + '</div>';
    }).join('');
  }

  function renderActiveBrand(key, containerId) {
    const f = FACTIONS[key];
    if (!f) return;
    const quote = pickQuote(key);
    const hud = document.getElementById('welcome-hud');
    const nameEl = document.getElementById('hud-faction-name');
    const summary = document.getElementById('hud-faction');
    const toggle = document.getElementById('hud-toggle');
    if (hud) {
      hud.style.setProperty('--faction-color', f.color);
      hud.dataset.faction = key;
      hud.dataset.logStyle = f.isLog ? '1' : '0';
    }
    if (nameEl) nameEl.textContent = f.name;
    if (summary) summary.textContent = quote;
    if (toggle && (!hud || hud.dataset.tone !== 'error')) {
      toggle.title = f.name + ' · ' + quote + '（点击切换频道）';
    }
    const el = containerId ? document.getElementById(containerId) : null;
    if (el && el !== hud) {
      el.textContent = f.name + ' · ' + quote;
      el.style.setProperty('--faction-color', f.color);
    }
  }

  function init(ids) {
    ids = ids || {};
    const active = pickActive();
    window.__activeFaction = active;
    if (ids.dividerId)     renderDivider(active, ids.dividerId);
    if (ids.listId)        renderList(active, ids.listId);
    if (ids.activeBrandId) renderActiveBrand(active, ids.activeBrandId);
    return active;
  }

  function cycleNext(ids) {
    ids = ids || {};
    const keys = Object.keys(FACTIONS);
    const cur = window.__activeFaction || keys[0];
    const next = keys[(keys.indexOf(cur) + 1) % keys.length];
    window.__activeFaction = next;
    if (ids.dividerId)     renderDivider(next, ids.dividerId);
    if (ids.listId)        renderList(next, ids.listId);
    if (ids.activeBrandId) renderActiveBrand(next, ids.activeBrandId);
    return next;
  }

  // 调试 hotkey opt-in: window.__FACTION_DEBUG = true 才启用 F 循环
  document.addEventListener('keydown', function (e) {
    if (!window.__FACTION_DEBUG) return;
    if (e.key !== 'f' && e.key !== 'F') return;
    if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
    const stored = window.__factionIds || {};
    cycleNext(stored);
  });

  window.Factions = {
    FACTIONS: FACTIONS,
    STATUS_LABEL: STATUS_LABEL,
    pickActive: pickActive,
    renderDivider: renderDivider,
    renderList: renderList,
    renderActiveBrand: renderActiveBrand,
    init: init,
    cycleNext: cycleNext
  };
})();
