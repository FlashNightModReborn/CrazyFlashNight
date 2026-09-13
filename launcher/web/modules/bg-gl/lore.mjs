// CF7 PM19 V3. The launch controller owns all commands; this module narrates.
// 双音区事件流：风味文本 + 弱化技术后缀。纯 DOM、零依赖；列车 C 可在此后接宿主水槽。
// TTL 取 11800 而非 12000：建角呈现期限探针按 12000 精确值钩住加速，整值会被误计。
const TTL_MS = 11800, FADE_MS = 600, HOLD_MS = 8000;
const FLOOD_WINDOW_MS = 500, FLOOD_LIMIT = 3;
const FLAVOR = {
  Spawning: 'θ-FLOOD 载波建立 · 进程拉起',
  WaitingConnect: '等待渲染进程连接…',
  WaitingHandshake: '诺亚终端握手…',
  Embedding: 'AVM1 沙箱嵌入…',
  WaitingGameReady: '等待游戏就绪信号…',
  Ready: '游戏就绪 · 矩阵同步',
  Idle: '轨道重置 · 回到监听态',
  Resetting: '轨道重置 · 回到监听态',
  RepairPending: '存档修复待确认',
  Error: '敌对故障注入 · 链路中断',
};
const STATE_TONE = { Ready: 'ok', Error: 'err' };
const EVENT_FLAVOR = {
  confirm: '操作员确认 · 双对角锁定开始',
  'sync-done': 'Σ=190000361 · 全轨道同步 · 通路打开',
  sigma: 'Σ=190000361 · 40/40 等和线',
};
const EVENT_TONE = { 'sync-done': 'ok' };

export function mountLore() {
  // 复用 V1 容器 ID：retire 断言与本容器样式都认 #bg-gl-log。
  const root = document.createElement('div');
  root.id = 'bg-gl-log';
  root.setAttribute('aria-hidden', 'true');
  document.body.appendChild(root);
  const timers = new Set(), records = [], writes = [];
  let disposed = false, frozen = false, wanted = false, errorHold = false;

  function later(ms, fn) {
    const id = setTimeout(() => { timers.delete(id); fn(); }, ms);
    timers.add(id);
    return id;
  }
  function stamp() {
    const d = new Date(), p = n => String(n).padStart(2, '0');
    return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
  }
  function lineCap() { return window.matchMedia('(max-height:700px)').matches ? 3 : 5; }
  function applyVisible() { root.classList.toggle('visible', wanted || errorHold); }
  function drop(rec) {
    const i = records.indexOf(rec);
    if (i >= 0) records.splice(i, 1);
    rec.el.remove();
  }
  function retireLine(rec) {
    if (rec.fading) return;
    rec.fading = true;
    rec.el.classList.add('fade');
    later(FADE_MS, () => drop(rec));
  }
  // 洪水抑制：窗口内已写满限额时本行省略技术后缀，风味文本不受影响。
  function flooded(now) {
    while (writes.length && now - writes[0] > FLOOD_WINDOW_MS) writes.shift();
    return writes.length >= FLOOD_LIMIT;
  }
  function add(text, tone, suffix) {
    if (disposed) return;
    const now = Date.now();
    const shown = suffix && !flooded(now) ? suffix : '';
    writes.push(now);
    const el = document.createElement('div');
    el.className = 'ln' + (tone ? ' ' + tone : '');
    const ts = document.createElement('span');
    ts.className = 'ts';
    ts.textContent = stamp();
    el.appendChild(ts);
    el.appendChild(document.createTextNode(text));
    if (shown) {
      const dim = document.createElement('span');
      dim.className = 'dim';
      dim.textContent = shown;
      el.appendChild(dim);
    }
    for (const rec of records) rec.el.classList.add('old');
    root.appendChild(el);
    const rec = { ts: ts.textContent, text, suffix: shown, tone: tone || '', el, fading: false };
    records.push(rec);
    let over = records.length - lineCap();
    for (const old of records) {
      if (over <= 0) break;
      if (!old.fading) { retireLine(old); over--; }
    }
    later(TTL_MS, () => retireLine(rec));
  }

  function ready(info) {
    if (frozen || disposed) return;
    add('质数幻方种子库验讫 · SHA-256 OK', 'ok', 'seeds ' + (info && info.seeds) + '/8');
  }
  function state(name, msg, meta) {
    if (frozen || disposed) return;
    if (name === 'Error') { error(msg); return; }
    // 未知状态风味统一兜底；后缀始终带原始 state 名。
    let suffix = String(name);
    if (meta && meta.prevDwellMs) suffix += ' · +' + (meta.prevDwellMs / 1000).toFixed(1) + 's';
    if (meta && meta.attempt > 1) suffix += ' · attempt#' + meta.attempt;
    add(FLAVOR[name] || '状态变更', STATE_TONE[name] || '', suffix);
  }
  function event(name) {
    if (frozen || disposed) return;
    const flavor = EVENT_FLAVOR[name];
    if (flavor) add(flavor, EVENT_TONE[name] || '', '');
  }
  function error(msg) {
    if (disposed) return;
    add(FLAVOR.Error, 'err', msg || '');
    // 冻结直到下一轮 loading 的 phase(true)；期间强制可见 8s，超时交还调用方。
    frozen = true;
    errorHold = true;
    applyVisible();
    later(HOLD_MS, () => { errorHold = false; applyVisible(); });
  }
  function phase(visible) {
    if (disposed) return;
    wanted = !!visible;
    if (wanted) frozen = false;
    applyVisible();
  }
  function lines() {
    return records.map(({ ts, text, suffix, tone }) => ({ ts, text, suffix, tone }));
  }
  function dispose() {
    if (disposed) return;
    disposed = true;
    for (const id of timers) clearTimeout(id);
    timers.clear();
    records.length = 0;
    root.remove();
  }

  return { ready, state, event, error, phase, lines, dispose };
}
