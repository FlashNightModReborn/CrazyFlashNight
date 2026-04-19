/**
 * 阵营配置 — 欢迎页 mockup 可维护数据源
 *
 * 新增阵营只需要往 FACTIONS 里 push 一个对象。每个阵营字段：
 *   name / enName       — 显示名（中文 / 英文）
 *   baseStatus          — 基础状态: 'sync' | 'standby' | 'offline'
 *                         （本次加载被选为 active 的阵营一律显示 'sync' 覆盖 baseStatus）
 *   color / colorDim    — 主色 / 衰减色（用于 rune 描边、右栏点状状态灯、未来扩展）
 *   slogan              — 阵营标语（可选，预留未来显示）
 *   rune                — 中部分割线 SVG 字符串，viewBox 建议 0 0 500 24，宽度随容器
 *                         设计原则：每个阵营独立视觉符号，避免道教母题污染到非道教势力
 *
 * 渲染入口：renderDivider(key) / renderFactionList(activeKey) / pickActiveFaction()
 */

const FACTIONS = {
  iron: {
    name: '黑铁会',
    enName: 'IRON SOCIETY',
    baseStatus: 'standby',
    color: '#b83a2e',
    colorDim: '#7d2418',
    slogan: '天地有呼吸 · 政教合一',
    // 道教 / 八卦 / 篆书"道" — 只有黑铁会带道教意象
    rune: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 24" preserveAspectRatio="none" style="width:100%;height:100%">
      <g stroke="#b83a2e" stroke-width=".9" fill="none">
        <path d="M 0 12 L 218 12 M 282 12 L 500 12"/>
        <circle cx="250" cy="12" r="9"/>
        <circle cx="250" cy="12" r="11" opacity=".45"/>
        <text x="250" y="16.5" text-anchor="middle" fill="#b83a2e"
              font-family="STSong,SimSun,'Noto Serif CJK SC',serif" font-size="11" font-weight="700">道</text>
        <g stroke="#c8b28a" stroke-width=".5">
          <path d="M 232 8 L 237 8 M 232 12 L 234 12 M 235 12 L 237 12 M 232 16 L 237 16"/>
          <path d="M 263 8 L 268 8 M 263 12 L 265 12 M 266 12 L 268 12 M 263 16 L 268 16"/>
        </g>
      </g>
    </svg>`,
  },

  noah: {
    name: '诺亚',
    enName: 'NOAH',
    baseStatus: 'standby',
    color: '#3dd5ff',
    colorDim: '#1e90b3',
    slogan: '半张地图',
    // 三角 / 金字塔 + 数据阶梯线 — 计算逃生航线的冷意
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
    </svg>`,
  },

  mercenary: {
    name: 'A兵团',
    enName: 'A-CORPS',
    baseStatus: 'standby',
    color: '#c8b28a',
    colorDim: '#6a5f48',
    slogan: '打出去有效果就行',
    // 交叉刀刃 + 侧翼凹痕（击杀刻度） — 体感格斗的硬朗
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
    </svg>`,
  },

  skynet: {
    name: '天网',
    enName: 'SKYNET',
    baseStatus: 'offline',
    color: '#7a9a5a',
    colorDim: '#3d4d2d',
    slogan: '(无口号)',
    // 齿轮 / 节点环 + 损坏虚线 — 植物神经 / CRT 残余
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
    </svg>`,
  },

  // ── 未来扩展位置（示例模板，注释掉）────────────────────────────
  // university: {
  //   name: '联合大学', enName: 'JOINT UNIV.',
  //   baseStatus: 'standby',
  //   color: '#d8b06c', colorDim: '#6a5430',
  //   slogan: '验真之塔',
  //   rune: `<svg ...></svg>`, // 学术徽章 / 罗盘 / 书
  // },
  // mutant: {
  //   name: '变异节点', enName: 'MUTANT NODE',
  //   baseStatus: 'offline',
  //   color: '#b45bd8', colorDim: '#5a2d6e',
  //   slogan: '协议冲突',
  //   rune: `<svg ...></svg>`, // 碎片 / 故障 / 抖动线
  // },
  // wings: {
  //   name: 'WINGS', enName: 'WINGS',
  //   baseStatus: 'offline',
  //   color: '#e0e0e0', colorDim: '#444',
  //   slogan: '(身份待揭露)',
  //   rune: `<svg ...></svg>`, // 两翼轮廓
  // },
};

// ── 渲染层 ─────────────────────────────────────────────

const STATUS_LABEL = { sync: '同步中', standby: '待机', offline: '离线' };

function pickActiveFaction() {
  const keys = Object.keys(FACTIONS);
  return keys[Math.floor(Math.random() * keys.length)];
}

function renderDivider(key, containerId) {
  const el = document.getElementById(containerId);
  if (!el || !FACTIONS[key]) return;
  el.innerHTML = FACTIONS[key].rune;
}

function renderFactionList(activeKey, containerId) {
  const el = document.getElementById(containerId);
  if (!el) return;
  el.innerHTML = Object.entries(FACTIONS).map(([k, f]) => {
    const status = (k === activeKey) ? 'sync' : f.baseStatus;
    const dotColor = status === 'sync' ? f.color : f.colorDim;
    const glow = status === 'sync' ? `box-shadow:0 0 6px ${f.color}` : '';
    return `<div class="f">
      <span class="dot" style="background:${dotColor};${glow}"></span>
      <span class="f-name"${k === activeKey ? ' style="color:#d4d8dc"' : ''}>${f.name}</span>
      <span class="f-sep">·</span>
      <span class="f-status"${status === 'sync' ? ` style="color:${f.color}"` : ''}>${STATUS_LABEL[status]}</span>
    </div>`;
  }).join('');
}

function renderActiveBrand(key, containerId) {
  const el = document.getElementById(containerId);
  if (!el || !FACTIONS[key]) return;
  const f = FACTIONS[key];
  el.textContent = `${f.enName} · ${f.slogan}`;
  el.style.color = f.color;
}

// ── Debug hotkey: 按 F 循环预览全部阵营 ────────────────
(function installFactionCycleHotkey() {
  if (typeof document === 'undefined') return;
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'f' && e.key !== 'F') return;
    if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
    const keys = Object.keys(FACTIONS);
    window.__activeFaction = window.__activeFaction || keys[0];
    const idx = keys.indexOf(window.__activeFaction);
    window.__activeFaction = keys[(idx + 1) % keys.length];
    renderDivider(window.__activeFaction, 'rune-divider');
    renderFactionList(window.__activeFaction, 'faction-list');
    renderActiveBrand(window.__activeFaction, 'active-brand');
  });
})();
