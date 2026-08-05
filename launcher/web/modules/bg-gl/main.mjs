// PM19 质数幻方电子战背景层 · 控制器与装配
// 叙事绑定：相位由真实启动事件驱动（BootstrapApp 消息 + DOM 事件），不是定时循环演示。
// 性能契约（交付方）：仅 SCRAMBLE / FAULT / RESCRAMBLE 相位期间以 8–12Hz 换棋盘
// （engine.nextInto + renderer.updateValues）；ROW / COLUMN / DIAGONAL / SYNCHRONIZED
// 期间冻结当前合法棋盘，只更新视觉 uniform。
// 二面体变轨间奏（约每 2–4 个环境插播周期一次）期间换盘暂停，动画结束瞬间换数据。

import { loadPrimeMagicSeedBank, loadPrimeMagicSeed } from "./pm19/binary-seed.js";
import { PrimeMagicSeedBankOrbitEngine } from "./pm19/seed-bank-engine.js";
import { PrimeMagicGridRenderer } from "./renderer.mjs";
import { PrimeMagicCanvasRenderer } from "./canvas-renderer.mjs";
import { DIHEDRAL_KINDS, transformBoardInto } from "./dihedral.mjs";

// ───────────────────────── 常量区 ─────────────────────────

// 相位 id（渲染器 uniform 契约）
const PHASE = {
  SCRAMBLE: 0,      // 频谱扰动（环境底态）
  ROW: 1,           // 行向量捕获
  COLUMN: 2,        // 列相干校验
  DIAGONAL: 3,      // 双对角锁定
  SYNCHRONIZED: 4,  // 矩阵同步完成
  FAULT: 5,         // 敌对故障注入
  RESCRAMBLE: 6,    // 轨道重置
};

const GRID_SIZE = 19;
const DIGIT_SLOTS = 8;
const MAX_DPR = 1.0; // 背景层 DPR 上限

// iGPU 性能压制（实测 240Hz 全速 rAF 会把核显压到 80%+）：
// 限帧 30fps + 半分辨率渲染（CSS 放大，背景层视觉无损）；两项合计填充率开销约降为 1/16
const TARGET_FPS = 30;
const FRAME_INTERVAL_MS = 1000 / TARGET_FPS;
const RENDER_SCALE = 0.5;

// 相位时长（ms）
const ROW_SWEEP_MS = 1700;       // 首个 list_resp → 扫行
const COLUMN_SWEEP_MS = 1600;    // 扫行后 → 扫列
const DIAGONAL_SWEEP_MS = 1800;  // 确认启动 → 双对角扫描
const RESCRAMBLE_MS = 700;       // 状态回到 Idle → 轨道重置

// 环境态插播：每 6–10s 一次 ROW / COLUMN 扫描（交替）
const AMBIENT_SCAN_MIN_MS = 6000;
const AMBIENT_SCAN_MAX_MS = 10000;

// 换棋盘频率 8–12Hz（仅 SCRAMBLE / FAULT / RESCRAMBLE 相位）
const BOARD_SWAP_MIN_MS = 1000 / 12;
const BOARD_SWAP_MAX_MS = 1000 / 8;

// 二面体变轨间奏：环境态下约每 2–4 个插播周期触发一次整盘旋转 / 镜像
const SPIN_PERIOD_MIN = 2;
const SPIN_PERIOD_MAX = 4;
const SPIN_MIN_MS = 900;
const SPIN_MAX_MS = 1400;
const FAULT_SPIN = 0.30;              // 变轨期间短暂升高的故障强度（「变轨」感）

// 校验和读数：19×19 完整质数幻方行 / 列 / 双对角和恒等，读数直接写真值
const MAGIC_SUM = 190000361;
const READOUT_SETTLE_MS = 70;         // 行 / 列号切换后读数「收敛」伪动画时长
const READOUT_PENDING_SUM = "·········"; // 降级模式下锁定前的静态占位

// SYNCHRONIZED 进入脉冲（破门冲击波）时长，播完转保持
const SYNC_BURST_MS = 900;

// 叙事日志（左下角事件流）：相位与真实启动事件 → 电子战 lore 文本
const LOG_MAX_LINES = 5;              // 最多保留行数（旧行自动淘汰）
const LOG_LINE_TTL_MS = 12000;        // 单行滞留上限（超时淡出，避免陈年信息残留）

// prefers-reduced-motion 降级
const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";
const REDUCED_FAULT_SCALE = 0.3;      // 降级模式故障强度统一缩放
const REDUCED_SWAP_MIN_MS = 1000 / 4; // 降级换盘 2–4Hz
const REDUCED_SWAP_MAX_MS = 1000 / 2;

// 读数 DOM 样式（运行时注入 <style>，不触碰 bg-gl 以外的任何文件）
const READOUT_CSS = `
#bg-gl-readout {
  position: fixed;
  right: 14px;
  bottom: 44px; /* 避开 .bottom 底栏（z-20），两行读数不与其文字重叠 */
  z-index: 3;
  pointer-events: none;
  font: 11px/1.6 ui-monospace, "Cascadia Mono", Consolas, monospace;
  letter-spacing: 0.08em;
  text-align: right;
  color: rgba(61, 213, 255, 0.62);
  text-shadow: 0 0 6px rgba(61, 213, 255, 0.30);
  opacity: 0.55;
  user-select: none;
}
#bg-gl-readout .lock {
  color: rgba(200, 178, 138, 0.80);
  text-shadow: 0 0 6px rgba(200, 178, 138, 0.30);
}
#bg-gl-readout.quiet {
  opacity: 0.16;
}
/* 双对角锁定保持期：读数呼吸（reduced-motion 下 JS 侧不会加这个 class） */
#bg-gl-readout.breathe {
  animation: bgGlReadoutBreathe 1.6s ease-in-out infinite;
}
@keyframes bgGlReadoutBreathe {
  0%, 100% { opacity: 0.55; }
  50% { opacity: 0.95; }
}
`;

// 叙事日志 DOM 样式（左下角事件流；与读数同为运行时注入，不触碰 HTML）
const LOG_CSS = `
#bg-gl-log {
  position: fixed;
  left: 50%;
  transform: translateX(-50%);
  bottom: 44px; /* 与读数同高，避开 .bottom 底栏；居中落在中央卡片正下方的空白带 */
  z-index: 3;
  pointer-events: none;
  font: 11px/1.7 ui-monospace, "Cascadia Mono", Consolas, monospace;
  letter-spacing: 0.08em;
  color: rgba(61, 213, 255, 0.60);
  text-shadow: 0 0 6px rgba(61, 213, 255, 0.28);
  user-select: none;
  max-width: 44vw;
}
#bg-gl-log .ln {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  animation: bgGlLogIn 0.24s ease-out;
}
#bg-gl-log .ln.old { opacity: 0.34; }
#bg-gl-log .ln.fade { opacity: 0; transition: opacity 0.6s; }
#bg-gl-log .ln .ts { color: rgba(106, 98, 88, 0.85); margin-right: 8px; }
#bg-gl-log .ln.ok { color: rgba(200, 178, 138, 0.85); text-shadow: 0 0 6px rgba(200, 178, 138, 0.3); }
#bg-gl-log .ln.err { color: rgba(255, 92, 78, 0.9); text-shadow: 0 0 8px rgba(184, 58, 46, 0.5); }
@keyframes bgGlLogIn {
  from { opacity: 0; transform: translateX(-8px); }
  to { opacity: 1; transform: none; }
}
/* reduced-motion：JS 侧不加 ln 动画无妨，这里统一关停 */
@media (prefers-reduced-motion: reduce) {
  #bg-gl-log .ln { animation: none; }
}
`;

// 故障强度（faultIntensity）
const FAULT_BOOT = 0.45;        // 页面加载完成后的初始 SCRAMBLE
const FAULT_AMBIENT = 0.18;     // 环境态（低）
const FAULT_SWEEP = 0.10;       // 行/列扫描期间
const FAULT_DIAGONAL = 0.05;    // 对角锁定期间
const FAULT_SYNC = 0.0;         // 矩阵同步完成
const FAULT_RESCRAMBLE = 0.85;  // 轨道重置
const FAULT_ERROR = 1.0;        // Error 态故障注入（拉满）

// 允许换棋盘的相位集合
const SWAP_PHASES = new Set([PHASE.SCRAMBLE, PHASE.FAULT, PHASE.RESCRAMBLE]);

// 种子库 URL：相对本模块解析，与页面 base URL 解耦
const SEED_BANK_URL = new URL("../../assets/pm19/seed-bank.json", import.meta.url);

// ───────────────────────── 运行态 ─────────────────────────

let engine = null;
let renderer = null;
let board = null;

const machine = {
  phase: PHASE.SCRAMBLE,
  startedAt: performance.now(),
  duration: Infinity,  // 有限时长相位到期触发 onDone；Infinity = 保持相位
  holdProgress: 0,     // 保持相位使用的 progress
  fault: FAULT_BOOT,
  signal: 1,
  onDone: null,
};

let phaseTimer = null;    // 有限时长相位的到期定时器
let ambientTimer = null;  // 环境态插播定时器
let swapTimer = null;     // 换棋盘定时器链
let rafId = 0;
let paused = false;
let lastFrameAt = -Infinity; // 上一实际渲染帧时刻（限帧用）
let sawFirstListResp = false;
let lastState = null;
let ambientAlternate = false; // 环境插播 ROW / COLUMN 交替

// 二面体变轨间奏运行态
let spinCountdown = 0;    // 距下次变轨的插播周期数（main 中初始化）
const spin = { active: false, kind: null, startedAt: 0, duration: 0 };
let spinScratch = null;   // 变轨数据变换复用缓冲（与 board 双缓冲互换）

// 校验和读数运行态（DOM 运行时注入，teardown 移除）
const readout = {
  style: null, root: null, lineMain: null, lineSub: null,
  key: "",               // 上一帧读数指纹（避免无谓 DOM 写）
  phase: -1, lastIndex: -1, indexChangedAt: 0,
};

// 叙事日志运行态（DOM 运行时注入，teardown 移除）
const logBox = { style: null, root: null, lines: 0 };

// prefers-reduced-motion 降级运行态
let reducedMedia = null;
let reducedMotion = false;

// ───────────────────── 相位机 ─────────────────────

function clearPhaseTimers() {
  if (phaseTimer !== null) { clearTimeout(phaseTimer); phaseTimer = null; }
  if (ambientTimer !== null) { clearTimeout(ambientTimer); ambientTimer = null; }
}

function startSwapLoop() {
  if (swapTimer !== null || engine === null || renderer === null) return;
  const step = () => {
    swapTimer = null;
    if (!SWAP_PHASES.has(machine.phase)) return; // 相位已切走，链自然终止
    engine.nextInto(board);
    renderer.updateValues(board);
    swapTimer = setTimeout(step, nextSwapDelay());
  };
  swapTimer = setTimeout(step, nextSwapDelay());
}

// 换盘间隔：常规 8–12Hz；prefers-reduced-motion 降级为 2–4Hz
function nextSwapDelay() {
  const min = reducedMotion ? REDUCED_SWAP_MIN_MS : BOARD_SWAP_MIN_MS;
  const max = reducedMotion ? REDUCED_SWAP_MAX_MS : BOARD_SWAP_MAX_MS;
  return min + Math.random() * (max - min);
}

// 故障强度单点缩放：prefers-reduced-motion 降级统一 ×REDUCED_FAULT_SCALE
function scaleFault(fault) {
  return reducedMotion ? fault * REDUCED_FAULT_SCALE : fault;
}

function stopSwapLoop() {
  if (swapTimer !== null) { clearTimeout(swapTimer); swapTimer = null; }
}

function enterPhase(phase, options = {}) {
  const {
    duration = Infinity,
    fault = machine.fault,
    signal = 1,
    holdProgress = 0,
    onDone = null,
  } = options;
  finalizeSpin(); // 真实事件打断变轨动画：先落盘到终态再进新相位
  clearPhaseTimers();
  machine.phase = phase;
  machine.startedAt = performance.now();
  machine.duration = duration;
  machine.holdProgress = holdProgress;
  machine.fault = scaleFault(fault);
  machine.signal = signal;
  machine.onDone = onDone;
  if (SWAP_PHASES.has(phase)) startSwapLoop(); else stopSwapLoop();
  if (Number.isFinite(duration)) {
    phaseTimer = setTimeout(() => {
      phaseTimer = null;
      const callback = machine.onDone;
      machine.onDone = null;
      if (callback) callback();
    }, duration);
  }
}

// 对角锁定：扫满 1.8s 后进保持期（双对角行波循环）。
// 注意：任何快速到达的真实事件都不许截断扫描 —— WaitingGameReady 不再拉满、
// Ready / flash_ready 只置 syncPending，等扫描自然播完再进 SYNCHRONIZED（保证动画可见）。
let syncPending = false; // Ready/flash_ready 已到达但对角扫描未播完

function onDiagonalSweepDone() {
  machine.duration = Infinity;
  machine.holdProgress = 1;
  if (syncPending) {
    syncPending = false;
    enterSynchronized();
  }
}

function enterDiagonalLock() {
  if (machine.phase !== PHASE.DIAGONAL) {
    enterPhase(PHASE.DIAGONAL, {
      duration: DIAGONAL_SWEEP_MS,
      fault: FAULT_DIAGONAL,
      onDone: onDiagonalSweepDone,
    });
  }
}

function enterSynchronized() {
  syncPending = false;
  narrativeLog(`Σ=${MAGIC_SUM} · 全轨道同步 · 通路打开`, "ok");
  // 进入脉冲：900ms 破门冲击波（shader 按 progress<1 播径向爆闪），随后转保持
  enterPhase(PHASE.SYNCHRONIZED, {
    duration: SYNC_BURST_MS,
    fault: FAULT_SYNC,
    onDone: () => {
      machine.duration = Infinity;
      machine.holdProgress = 1;
    },
  });
}

// Ready / flash_ready 入口：对角扫描在播则挂起等播完，否则立即同步
function requestSynchronized() {
  if (machine.phase === PHASE.DIAGONAL && Number.isFinite(machine.duration)) {
    syncPending = true;
    return;
  }
  enterSynchronized();
}

function enterAmbient() {
  enterPhase(PHASE.SCRAMBLE, { fault: FAULT_AMBIENT });
  ambientTimer = setTimeout(() => {
    ambientTimer = null;
    // 二面体变轨间奏：约每 2–4 个插播周期一次（prefers-reduced-motion 降级下禁用）
    if (!reducedMotion) {
      spinCountdown -= 1;
      if (spinCountdown <= 0) {
        spinCountdown = randomSpinCountdown();
        startSpinInterlude();
        return;
      }
    }
    const isRow = !ambientAlternate;
    ambientAlternate = !ambientAlternate;
    enterPhase(isRow ? PHASE.ROW : PHASE.COLUMN, {
      duration: isRow ? ROW_SWEEP_MS : COLUMN_SWEEP_MS,
      fault: FAULT_SWEEP,
      onDone: enterAmbient,
    });
  }, AMBIENT_SCAN_MIN_MS + Math.random() * (AMBIENT_SCAN_MAX_MS - AMBIENT_SCAN_MIN_MS));
}

// ───────────────────── 二面体变轨间奏 ─────────────────────

function randomSpinCountdown() {
  return SPIN_PERIOD_MIN + Math.floor(Math.random() * (SPIN_PERIOD_MAX - SPIN_PERIOD_MIN + 1));
}

// 触发变轨：相位保持 SCRAMBLE，仅故障短暂升高制造「变轨」感；动画期间棋盘数据不变
function startSpinInterlude() {
  stopSwapLoop(); // 换盘暂停，动画结束（或被打断落盘）后由 enterAmbient 恢复
  spin.active = true;
  spin.kind = DIHEDRAL_KINDS[Math.floor(Math.random() * DIHEDRAL_KINDS.length)];
  spin.startedAt = performance.now();
  spin.duration = SPIN_MIN_MS + Math.random() * (SPIN_MAX_MS - SPIN_MIN_MS);
  machine.fault = scaleFault(FAULT_SPIN);
  narrativeLog(`ORBIT 变轨 · ${spin.kind.name.toUpperCase()} · 幻性保持`);
}

// 动画结束 / 被打断：把棋盘数据替换为旋转 / 镜像后的棋盘（二面体对称，恒为合法幻方），
// uSpin / uMirror 归零 —— 终态变换与变换后数据渲染结果一致，视觉无缝。
function finalizeSpin() {
  if (!spin.active) return;
  spin.active = false;
  const kind = spin.kind;
  spin.kind = null;
  transformBoardInto(board, spinScratch, GRID_SIZE, kind);
  const previous = board;
  board = spinScratch;
  spinScratch = previous;
  if (renderer !== null) {
    renderer.updateValues(board);
    renderer.setDihedralTransform(0, 1);
  }
}

// 渲染循环中推进变轨动画：缓入缓出插值 uSpin / uMirror；镜像以 x 缩放连续翻过 0
function updateSpin(now) {
  if (!spin.active || renderer === null) return;
  const raw = Math.min(1, (now - spin.startedAt) / spin.duration);
  const eased = 0.5 - 0.5 * Math.cos(raw * Math.PI); // 缓入缓出
  const mirror = spin.kind.mirror < 0 ? 1 - 2 * eased : 1;
  renderer.setDihedralTransform(spin.kind.spin * eased, mirror);
  if (raw >= 1) {
    finalizeSpin();
    enterAmbient(); // 恢复换盘链并排程下一轮插播
  }
}

// ───────────────────── 事件映射 ─────────────────────

function onFirstListResp() {
  if (sawFirstListResp) return;
  sawFirstListResp = true;
  narrativeLog("黑铁网络接入 · 存档清单同步", "ok");
  narrativeLog("行向量捕获开始");
  enterPhase(PHASE.ROW, {
    duration: ROW_SWEEP_MS,
    fault: FAULT_SWEEP,
    onDone: () => {
      narrativeLog("19 行向量捕获 · Σ 全部命中");
      narrativeLog("列相干校验开始");
      enterPhase(PHASE.COLUMN, {
        duration: COLUMN_SWEEP_MS,
        fault: FAULT_SWEEP,
        onDone: () => {
          narrativeLog("19 列相干校验通过 · 转入监听态", "ok");
          enterAmbient();
        },
      });
    },
  });
}

function onLaunchState(msg) {
  const state = msg && msg.state;
  if (typeof state !== "string") return;
  const previous = lastState;
  lastState = state;
  switch (state) {
    case "Spawning":
      narrativeLog("θ-FLOOD 载波建立 · 进程拉起");
      enterDiagonalLock();
      break;
    case "WaitingConnect":
      narrativeLog("等待渲染进程连接…");
      enterDiagonalLock();
      break;
    case "WaitingHandshake":
      narrativeLog("诺亚终端握手…");
      enterDiagonalLock();
      break;
    case "Embedding":
      narrativeLog("AVM1 沙箱嵌入…");
      enterDiagonalLock();
      break;
    case "WaitingGameReady":
      narrativeLog("等待游戏就绪信号…");
      enterDiagonalLock();
      break;
    case "Ready":
      narrativeLog("游戏就绪 · 矩阵同步", "ok");
      requestSynchronized();
      break;
    case "Error":
      syncPending = false;
      narrativeLog("敌对故障注入 · 链路中断", "err");
      enterPhase(PHASE.FAULT, { fault: FAULT_ERROR, signal: 0.75 });
      break;
    case "Idle":
      // 首次消息或本就是 Idle 不算「回到 Idle」，避免开场误触发重置
      syncPending = false;
      if (previous !== null && previous !== "Idle") {
        narrativeLog("轨道重置 · 回到监听态");
        enterPhase(PHASE.RESCRAMBLE, {
          duration: RESCRAMBLE_MS,
          fault: FAULT_RESCRAMBLE,
          onDone: enterAmbient,
        });
      }
      break;
    default:
      break;
  }
}

// ───────────────────── 校验和收敛读数（叙事 DOM，全部运行时注入） ─────────────────────

function createReadout() {
  const style = document.createElement("style");
  style.id = "bg-gl-readout-style";
  style.textContent = READOUT_CSS;
  document.head.appendChild(style);

  const root = document.createElement("div");
  root.id = "bg-gl-readout";
  root.className = "quiet";
  const lineMain = document.createElement("div");
  const lineSub = document.createElement("div");
  root.appendChild(lineMain);
  root.appendChild(lineSub);
  document.body.appendChild(root);

  readout.style = style;
  readout.root = root;
  readout.lineMain = lineMain;
  readout.lineSub = lineSub;
}

function removeReadout() {
  if (readout.root !== null) { readout.root.remove(); readout.root = null; }
  if (readout.style !== null) { readout.style.remove(); readout.style = null; }
  readout.lineMain = null;
  readout.lineSub = null;
  readout.key = "";
  readout.phase = -1;
  readout.lastIndex = -1;
}

// ───────────────────── 叙事日志（电子战事件流） ─────────────────────

function createLog() {
  if (logBox.root !== null) return;
  const style = document.createElement("style");
  style.id = "bg-gl-log-style";
  style.textContent = LOG_CSS;
  document.head.appendChild(style);
  const root = document.createElement("div");
  root.id = "bg-gl-log";
  root.setAttribute("aria-hidden", "true");
  document.body.appendChild(root);
  logBox.style = style;
  logBox.root = root;
}

function removeLog() {
  if (logBox.root !== null) { logBox.root.remove(); logBox.root = null; }
  if (logBox.style !== null) { logBox.style.remove(); logBox.style = null; }
  logBox.lines = 0;
}

// tone: "" 默认信息 / "ok" 锁定与就绪 / "err" 敌对故障
function narrativeLog(text, tone = "") {
  if (logBox.root === null) return;
  const root = logBox.root;
  const line = document.createElement("div");
  line.className = "ln" + (tone ? " " + tone : "");
  const ts = document.createElement("span");
  ts.className = "ts";
  ts.textContent = new Date().toTimeString().slice(0, 8);
  line.appendChild(ts);
  line.appendChild(document.createTextNode(text));
  root.appendChild(line);
  // 超龄行先标 fade 再移除；旧行降透明度
  const items = root.children;
  while (items.length > LOG_MAX_LINES) {
    const oldest = items[0];
    oldest.classList.add("fade");
    setTimeout(() => oldest.remove(), 650);
    if (items.length > LOG_MAX_LINES * 2) oldest.remove(); // 兜底防堆积
    break;
  }
  for (let i = 0; i < items.length - 1; i += 1) items[i].classList.add("old");
  setTimeout(() => { line.classList.add("fade"); setTimeout(() => line.remove(), 650); }, LOG_LINE_TTL_MS);
  logBox.lines += 1;
}

// 收敛伪动画的随机滚动值（9 位数，与真值同量级）
function garbleSum() {
  return String(100000000 + Math.floor(Math.random() * 900000000));
}

function setReadout(mainText, mainLocked, subText, subLocked, quiet) {
  if (readout.root === null) return;
  const key = `${mainText}|${subText}|${mainLocked}|${subLocked}|${quiet}`;
  if (key === readout.key) return;
  readout.key = key;
  readout.lineMain.textContent = mainText;
  readout.lineSub.textContent = subText;
  readout.lineMain.className = mainLocked ? "lock" : "";
  readout.lineSub.className = subLocked ? "lock" : "";
  readout.root.className = quiet ? "quiet" : "";
}

function updateReadout(now, progress, activeRow, activeColumn) {
  if (readout.root === null) return;
  const phase = machine.phase;
  if (phase !== readout.phase) {
    readout.phase = phase;
    readout.lastIndex = -1;
    readout.indexChangedAt = now;
  }
  if (phase === PHASE.ROW || phase === PHASE.COLUMN) {
    // 行 / 列扫描：行号快速滚动，每次切换后先滚动随机值再定格真值（数学上恒等）
    const index = Math.max(0, phase === PHASE.ROW ? activeRow : activeColumn);
    if (index !== readout.lastIndex) {
      readout.lastIndex = index;
      readout.indexChangedAt = now;
    }
    // 降级模式无滚动动画，直接显示定格值
    const settled = reducedMotion || now - readout.indexChangedAt >= READOUT_SETTLE_MS;
    const sum = settled ? `${MAGIC_SUM} ✓` : garbleSum();
    const label = phase === PHASE.ROW ? "ROW" : "COL";
    setReadout(`${label} ${String(index).padStart(2, "0")} Σ=${sum}`, settled, "", false, false);
  } else if (phase === PHASE.DIAGONAL) {
    // 双对角锁定：MAIN 先收敛（前半程），ANTI 后收敛（后半程）
    const mainLocked = progress * 2 >= 1;
    const antiProgress = progress * 2 - 1;
    const antiLocked = antiProgress >= 1;
    const pending = reducedMotion ? READOUT_PENDING_SUM : garbleSum();
    const mainSum = mainLocked ? `${MAGIC_SUM} ✓` : pending;
    const subText = antiProgress <= 0 ? "" : `ANTI Σ=${antiLocked ? `${MAGIC_SUM} ✓` : pending}`;
    setReadout(`MAIN Σ=${mainSum}`, mainLocked, subText, antiLocked, false);
    // 锁定保持期：读数呼吸（与 shader 双对角行波同步的「等待 Ready」活信号）
    if (readout.root) readout.root.classList.toggle("breathe", progress >= 1 && !reducedMotion);
  } else if (phase === PHASE.SYNCHRONIZED) {
    setReadout(`Σ=${MAGIC_SUM} · 361/361 VALID`, true, "", false, false);
  } else {
    // SCRAMBLE / FAULT / RESCRAMBLE：极低透明度常显真值；变轨期间升级为 ORBIT 标签
    if (spin.active && spin.kind) {
      setReadout(`ORBIT ${spin.kind.name.toUpperCase()} · Σ=${MAGIC_SUM}`, false, "", false, false);
    } else {
      setReadout(`Σ=${MAGIC_SUM}`, false, "", false, true);
    }
  }
}

// ───────────────────── prefers-reduced-motion 降级 ─────────────────────

function applyReducedMotion() {
  if (renderer !== null) renderer.setVisualEffects(!reducedMotion); // 着色器动画总开关
  if (reducedMotion && spin.active) {
    finalizeSpin();   // 变轨间奏在降级下禁用：立即落盘
    enterAmbient();   // 恢复换盘链与插播排程
  }
}

function onReducedMotionChange(event) {
  reducedMotion = event.matches;
  applyReducedMotion();
}

// ───────────────────── 渲染循环与暂停 ─────────────────────

function tick(now) {
  rafId = 0;
  if (paused) return;
  // 限帧：rAF 链保持（240Hz 也照跑），但只在到达帧间隔时真正渲染
  if (now - lastFrameAt < FRAME_INTERVAL_MS) {
    rafId = requestAnimationFrame(tick);
    return;
  }
  lastFrameAt = now;
  try {
    const progress = machine.duration === Infinity
      ? machine.holdProgress
      : Math.min(1, (now - machine.startedAt) / machine.duration);
    let activeRow = -1;
    let activeColumn = -1;
    if (machine.phase === PHASE.ROW) {
      activeRow = Math.min(GRID_SIZE - 1, Math.floor(progress * GRID_SIZE));
    } else if (machine.phase === PHASE.COLUMN) {
      activeColumn = Math.min(GRID_SIZE - 1, Math.floor(progress * GRID_SIZE));
    }
    renderer.setVisualState({
      phase: machine.phase,
      progress,
      activeRow,
      activeColumn,
      faultIntensity: machine.fault,
      signalIntensity: machine.signal,
    });
    updateSpin(now); // 变轨动画推进 / 落盘（可能在 render 前换掉棋盘数据）
    updateReadout(now, progress, activeRow, activeColumn);
    renderer.render(now / 1000);
  } catch (error) {
    // 渲染期异常（如 GPU context lost）：静默撤下，绝不上抛到全局
    console.warn("[bg-gl] 渲染循环异常，背景层已撤下:", error);
    teardown();
    return;
  }
  rafId = requestAnimationFrame(tick);
}

function isPaused() {
  return document.hidden || document.body.classList.contains("intro-video");
}

function updatePause() {
  const shouldPause = isPaused();
  if (shouldPause === paused) return;
  paused = shouldPause;
  if (paused) {
    if (rafId !== 0) { cancelAnimationFrame(rafId); rafId = 0; }
  } else if (rafId === 0 && renderer !== null) {
    rafId = requestAnimationFrame(tick);
  }
}

function teardown() {
  clearPhaseTimers();
  stopSwapLoop();
  spin.active = false;
  spin.kind = null;
  if (reducedMedia !== null && typeof reducedMedia.removeEventListener === "function") {
    reducedMedia.removeEventListener("change", onReducedMotionChange);
  }
  reducedMedia = null;
  removeReadout();
  removeLog();
  if (rafId !== 0) { cancelAnimationFrame(rafId); rafId = 0; }
  const canvas = document.getElementById("bg-gl");
  if (canvas) canvas.remove();
  renderer = null;
  engine = null;
}

// ───────────────────── 装配 ─────────────────────

async function main() {
  const canvas = document.getElementById("bg-gl");
  if (!(canvas instanceof HTMLCanvasElement)) return; // 无挂载点，静默退出

  // 1) 加载种子库（8 张 verified seed，fetch + SHA-256 校验由引擎完成）。
  //    vendored manifest 的 url 是 /web/assets/... 站点绝对路径，在内存中重映射到
  //    与本模块相对的资产目录（vendored 文件保持逐字节不变）。
  const manifest = await loadPrimeMagicSeedBank(SEED_BANK_URL);
  const entries = manifest.seeds.map((entry) => ({
    ...entry,
    url: new URL(entry.url.slice(entry.url.lastIndexOf("/") + 1), SEED_BANK_URL).href,
  }));
  const seeds = await Promise.all(entries.map(loadPrimeMagicSeed));

  // 2) 引擎：随机种子取自 Web Crypto，避免固定轨道序列
  const randomSeed = crypto.getRandomValues(new BigUint64Array(1))[0];
  engine = new PrimeMagicSeedBankOrbitEngine(seeds, randomSeed);
  board = new Uint32Array(engine.cellCount);
  spinScratch = new Uint32Array(engine.cellCount); // 变轨数据变换复用缓冲
  spinCountdown = randomSpinCountdown();

  // 3) 渲染器：WebGL2 → Canvas2D 逐级回退；再失败由外层 catch 撤下 canvas
  try {
    renderer = new PrimeMagicGridRenderer(canvas, GRID_SIZE, DIGIT_SLOTS, MAX_DPR, RENDER_SCALE);
  } catch (glError) {
    console.warn("[bg-gl] WebGL2 不可用，回退 Canvas2D:", glError);
    renderer = new PrimeMagicCanvasRenderer(canvas, GRID_SIZE, DIGIT_SLOTS, MAX_DPR, RENDER_SCALE);
  }

  // 初始棋盘
  engine.nextInto(board);
  renderer.updateValues(board);

  // 3.5) 校验和读数 + 叙事日志 DOM + prefers-reduced-motion 监听（change 时即时切换降级）
  createReadout();
  createLog();
  narrativeLog("PM19 轨道引擎上线 · 8 轨 ×7.43 亿态", "ok");
  narrativeLog("质数幻方种子库验讫 · SHA-256 OK", "ok");
  reducedMedia = window.matchMedia(REDUCED_MOTION_QUERY);
  reducedMotion = reducedMedia.matches;
  if (typeof reducedMedia.addEventListener === "function") {
    reducedMedia.addEventListener("change", onReducedMotionChange);
  }
  applyReducedMotion();

  // 4) 初始相位：页面加载完成 → SCRAMBLE（持续）
  enterPhase(PHASE.SCRAMBLE, { fault: FAULT_BOOT });

  // 5) 事件订阅：BootstrapApp 可能尚未定义，缺失时退化为 DOM 事件 + 环境循环
  const app = window.BootstrapApp;
  if (app && typeof app.onMessage === "function") {
    app.onMessage("list_resp", onFirstListResp);
    app.onMessage("state", onLaunchState);
    app.onMessage("flash_ready", requestSynchronized);
    app.onMessage("flash_ready", () => narrativeLog("封面帧到达 · 黑铁通路打开", "ok"));
  } else {
    console.warn("[bg-gl] BootstrapApp 未就绪，仅使用 DOM 事件 + 环境循环");
    enterAmbient();
  }

  const confirmButton = document.getElementById("btn-confirm-start");
  if (confirmButton) {
    confirmButton.addEventListener("click", () => {
      narrativeLog("操作员确认 · 双对角锁定开始");
      enterDiagonalLock();
    }, true);
  }

  // 6) 暂停/恢复：页面隐藏或片头视频（body.intro-video）期间停 rAF
  document.addEventListener("visibilitychange", updatePause);
  new MutationObserver(updatePause).observe(document.body, { attributes: true, attributeFilter: ["class"] });
  updatePause();
  if (!paused) rafId = requestAnimationFrame(tick);
}

main().catch((error) => {
  // 静默回退总闸：种子/引擎/双渲染器任一失败，撤下 canvas 并告警，绝不影响主流程
  console.warn("[bg-gl] 背景层初始化失败，已静默撤下:", error);
  teardown();
});
