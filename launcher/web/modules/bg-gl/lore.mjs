// CF7 PM19 V3. The launch controller owns all commands; this module narrates.
// 双音区事件流：风味文本 + 弱化技术后缀。纯 DOM、零依赖；列车 C 可在此后接宿主水槽。
// 渲染模型是 FIFO 队列：新行顶入、超上限时最老行淡出，没有时间处死——
// 阶段行是"走到哪一步"的足迹不是会过期的新闻；头部 state 行驻留计时每秒跳动。
// 过渡时长随队列静默时长自适应：沉寂十几秒的慢机屏幕不容 600ms 闪烁，
// 洪水期仍按地板值保持节奏。
const FADE_MIN_MS = 600, FADE_MAX_MS = 2600, ENTER_MIN_MS = 240, ENTER_MAX_MS = 900;
const HOLD_MS = 8000, TICK_MS = 1000;
const FLOOD_WINDOW_MS = 500, FLOOD_LIMIT = 3;
// 头亮尾暗的余烬带（自头向尾），队列停顿时也保持完整踪迹。
const OPACITIES = [1, .62, .45, .34, .26];
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
  'degraded-reveal': '封面帧到达 · 降级开门（看门狗）',
};
const EVENT_TONE = { 'sync-done': 'ok' };
const EVENT_SUFFIX = { 'degraded-reveal': 'degraded:true' };
// boot 行纯信号 token 过滤：S2_ENTER 类节拍与全大写蛇形名都不是玩家文案。
const BOOT_SIGNAL = /^S\d+_[A-Z_]+$/;
const BOOT_TOKEN = /^[A-Z][A-Z0-9_]{3,}$/;
const REDUCED = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : { matches: false };

export function mountLore(options) {
  // 复用 V1 容器 ID：retire 断言与本容器样式都认 #bg-gl-log。
  const root = document.createElement('div');
  root.id = 'bg-gl-log';
  root.setAttribute('aria-hidden', 'true');
  document.body.appendChild(root);
  const timers = new Set(), records = [], writes = [];
  let disposed = false, frozen = false, wanted = false, errorHold = false;
  const sink = options && typeof options.sink === 'function' ? options.sink : null;
  const sinkQueue = [];
  let sinkDropped = 0, lastAddAt = 0, lastGapMs = 0;

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
  // 位置渐隐：按自头距离重排透明度；transition 让队列整体流动而不是跳变。
  function restyle() {
    for (let i = 0; i < records.length; i++) {
      const fromHead = records.length - 1 - i;
      records[i].el.style.transition = 'opacity .8s';
      records[i].el.style.opacity = OPACITIES[Math.min(fromHead, OPACITIES.length - 1)];
    }
  }
  function drop(rec) {
    const i = records.indexOf(rec);
    if (i >= 0) { records.splice(i, 1); rec.el.remove(); restyle(); }
  }
  // 淡出时长取"本行写入前的队列静默间隔"的六分之一，夹在 0.6–2.6s：
  // 慢机长停顿后老行从容消散，快机洪水维持 0.6s 地板节奏。
  function retireLine(rec) {
    if (rec.fading) return;
    rec.fading = true;
    const fade = Math.min(FADE_MAX_MS, Math.max(FADE_MIN_MS, Math.round(lastGapMs / 6)));
    rec.el.style.transition = `opacity ${fade}ms`;
    rec.el.style.opacity = '0';
    later(fade, () => drop(rec));
  }
  // 洪水抑制：窗口内已写满限额时本行省略技术后缀，风味文本不受影响。
  function flooded(now) {
    while (writes.length && now - writes[0] > FLOOD_WINDOW_MS) writes.shift();
    return writes.length >= FLOOD_LIMIT;
  }
  function setDim(rec, text) {
    if (!text) return;
    if (!rec.dimEl) {
      rec.dimEl = document.createElement('span');
      rec.dimEl.className = 'dim';
      rec.el.appendChild(rec.dimEl);
    }
    rec.dimEl.textContent = text;
  }
  // state 行后缀 = 原始 state 名 + 该行自身的驻留秒（头部每秒刷新，被顶替后定格）。
  function stateSuffix(rec) {
    const m = rec.stateMeta;
    const dwell = ((Date.now() - m.enteredAt) / 1000).toFixed(1);
    return m.name + ' · +' + dwell + 's' + (m.extras.length ? ' · ' + m.extras.join(' · ') : '');
  }
  function tick() {
    if (disposed) return;
    if (!frozen && !REDUCED.matches && records.length) {
      const head = records[records.length - 1];
      if (head && head.stateMeta && !head.fading) setDim(head, stateSuffix(head));
    }
    later(TICK_MS, tick);
  }
  later(TICK_MS, tick);

  function add(text, tone, suffix) {
    if (disposed) return null;
    const now = Date.now();
    const shown = suffix && !flooded(now) ? suffix : '';
    writes.push(now);
    // 队列静默间隔（两次写入之间）：驱动本行进场与后续老行淡出的自适应时长。
    lastGapMs = lastAddAt ? now - lastAddAt : 0;
    lastAddAt = now;
    // 宿主水槽按"文本+实际显示后缀"入队；洪水省后缀的行也入队，只是不带后缀。
    if (sink) {
      if (sinkQueue.length >= 50) { sinkQueue.shift(); sinkDropped++; }
      sinkQueue.push(shown ? text + ' ' + shown : text);
    }
    const el = document.createElement('div');
    el.className = 'ln' + (tone ? ' ' + tone : '');
    // 进场动画时长同源于静默间隔（0.24–0.9s），CSS 侧用 --ln-in 变量驱动。
    el.style.setProperty('--ln-in',
      Math.min(ENTER_MAX_MS, Math.max(ENTER_MIN_MS, Math.round(lastGapMs / 8))) + 'ms');
    const ts = document.createElement('span');
    ts.className = 'ts';
    ts.textContent = stamp();
    el.appendChild(ts);
    el.appendChild(document.createTextNode(text));
    root.appendChild(el);
    const rec = { ts: ts.textContent, text, suffix: shown, tone: tone || '', el, dimEl: null, stateMeta: null, fading: false };
    if (shown) setDim(rec, shown);
    records.push(rec);
    let over = records.length - lineCap();
    for (const old of records) {
      if (over <= 0) break;
      if (!old.fading) { retireLine(old); over--; }
    }
    restyle();
    return rec;
  }

  // 宿主水槽：每 2s 把积压行批量交给 sink；溢出丢弃在下一批补记一条汇总。
  function flushSink() {
    if (!sink || (!sinkQueue.length && !sinkDropped)) return;
    const lines = sinkQueue.splice(0);
    if (sinkDropped) { lines.unshift('… 丢弃 ' + sinkDropped + ' 条'); sinkDropped = 0; }
    try { sink(lines); } catch (_) {}
  }
  if (sink) {
    const pump = () => { flushSink(); later(2000, pump); };
    later(2000, pump);
  }

  function ready(info) {
    if (frozen || disposed) return;
    add('质数幻方种子库验讫 · SHA-256 OK', 'ok', 'seeds ' + (info && info.seeds) + '/8');
  }
  function state(name, msg, meta) {
    if (frozen || disposed) return;
    if (name === 'Error') { error(msg); return; }
    // 未知状态风味统一兜底；extras 是后缀里不随时间跳的部分（尝试计数/通信端口）。
    const extras = [];
    if (meta && meta.attempt > 1) extras.push('attempt#' + meta.attempt);
    if (name === 'WaitingGameReady' && meta && meta.socketPort) extras.push('socket=' + meta.socketPort);
    const rec = add(FLAVOR[name] || '状态变更', STATE_TONE[name] || '',
      String(name) + (extras.length ? ' · ' + extras.join(' · ') : ''));
    if (rec) {
      rec.stateMeta = { name: String(name), enteredAt: Date.now(), extras };
      rec.suffix = stateSuffix(rec);
      if (!flooded(Date.now())) setDim(rec, rec.suffix);
    }
  }
  function event(name) {
    if (frozen || disposed) return;
    const flavor = EVENT_FLAVOR[name];
    if (flavor) add(flavor, EVENT_TONE[name] || '', EVENT_SUFFIX[name] || '');
  }
  function boot(text, meta) {
    if (frozen || disposed) return;
    const value = String(text == null ? '' : text);
    if (!value || BOOT_SIGNAL.test(value) || BOOT_TOKEN.test(value)) return;
    const frame = meta && meta.frame;
    add(value, '', frame == null ? 'boot' : 'boot · 批次 f' + frame);
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
    flushSink();
    disposed = true;
    for (const id of timers) clearTimeout(id);
    timers.clear();
    records.length = 0;
    root.remove();
  }

  return { ready, state, event, error, phase, lines, dispose, boot };
}
