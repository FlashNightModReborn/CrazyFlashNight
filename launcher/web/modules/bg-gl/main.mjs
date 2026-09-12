// CF7 PM19 V2. The launch controller owns all commands; this module observes.
import { loadPrimeMagicSeedBank, loadPrimeMagicSeed } from './pm19/binary-seed.js';
import { PrimeMagicSeedBankOrbitEngine } from './pm19/seed-bank-engine.js';
import { transformBoardInto, DIHEDRAL_KINDS } from './dihedral.mjs';
import { EnvironmentRenderer } from './environment-renderer.mjs';

const SEED_BANK = new URL('../../assets/pm19/seed-bank.json', import.meta.url);
const CYCLE_MS = 8000, CUE_MS = 2000;
const media = window.matchMedia('(prefers-reduced-motion: reduce)');
let canvas = document.getElementById('bg-gl');
let renderer = null, engine = null, board = null, scratch = null;
let retired = false, failed = false, userPaused = false, blocked = false;
let time = 0, previousNow = 0, nextCycle = CYCLE_MS;
let timer = 0, raf = 0, layoutDirty = true, paintDirty = true;
let cue = null, firstList = false, hostState = null, userIntent = false;
let commits = 0, cycles = 0, callbacks = 0, cues = 0;
const unsubs = [], observers = [], disposers = [];
const state = { kind: 'quiet', progress: 0, still: false };

function listen(target, name, fn, options) {
  if (!target) return;
  target.addEventListener(name, fn, options);
  disposers.push(() => target.removeEventListener(name, fn, options));
}
function clearSchedule() {
  if (timer) clearTimeout(timer);
  if (raf) cancelAnimationFrame(raf);
  timer = raf = 0;
}
function covered() {
  const b = document.body;
  const modal = document.getElementById('modal-host');
  // 普通加载是透明遮罩，背景仍可见；视频与建角才停止持续绘制。
  return document.hidden || b.classList.contains('intro-video')
    || b.classList.contains('character-create-preparing') || b.classList.contains('character-create-active')
    || (modal && modal.style.display !== 'none')
    || !canvas || !canvas.isConnected
    || (!loading() && ['view-welcome', 'view-slots'].every(id => document.getElementById(id)?.hidden));
}
function loading() { return document.body.classList.contains('intro-playing'); }
function isStatic() { return userPaused || media.matches || failed; }
function visualKind() { return hostState === 'Error' ? 'error' : cue ? cue.kind : loading() ? 'loading' : 'quiet'; }

function measure() {
  const masks = [];
  function add(selector, fade) {
    for (const el of document.querySelectorAll(selector)) {
      if (!el.getClientRects().length || el.closest('[hidden]')) continue;
      const r = el.getBoundingClientRect();
      if (r.width && r.height) masks.push({ x: r.x - 2, y: r.y - 2, width: r.width + 4, height: r.height + 4, fade });
    }
  }
  add('.welcome-card', 22);
  add('.side-l .block', 14);
  add('.side-r > .lbl, .side-r > .ver, .side-r > .ver-tail, .side-r > .row, .side-r .faction', 6);
  add('.topbar, .bottom', 8);
  add('#intro-ov.on.loading .loading-indicator', 24);
  add('#view-slots .slots-header, #view-slots .toolbar', 10);
  // Slot cards have opaque backing; masking the scrolling grid also keeps light
  // out of card gaps when reading an unfamiliar or corrupt save.
  add('#view-slots .cards', 8);
  renderer.resize(canvas.clientWidth, canvas.clientHeight, masks);
  layoutDirty = false;
}
function paint() {
  if (!renderer || retired) return;
  if (layoutDirty) measure();
  state.still = isStatic();
  state.kind = visualKind();
  state.progress = cue ? Math.min(1, (time - cue.at) / cue.duration) : 0;
  renderer.render(time / 1000, state);
  paintDirty = false;
}
function safePaint() {
  try { paint(); }
  catch (error) { fail(error); }
}
function beginCue(kind, duration = CUE_MS, commit = false) {
  if (retired || failed) return;
  // Cancel the OLD uncommitted animation. There is no half-board to finalize.
  cue = { kind, at: time, duration, commit };
  cues++;
  paintDirty = true;
}
function commitBoard() {
  if (cycles % 2 === 1) transformBoardInto(board, scratch, 19, DIHEDRAL_KINDS[1]);
  else engine.nextInto(scratch);
  const old = board; board = scratch; scratch = old;
  renderer.updateValues(board);
  commits++;
}
function frame(now) {
  raf = 0; callbacks++;
  if (retired || blocked || isStatic() || !renderer) return;
  // Only visible active time advances. No resume catch-up and no hidden swaps.
  if (previousNow) time += Math.min(120, Math.max(0, now - previousNow));
  previousNow = now;
  try {
    if (cue && time - cue.at >= cue.duration) {
      if (cue.commit) commitBoard();
      cue = null;
    }
    if (!cue && !loading() && hostState !== 'Error' && time >= nextCycle) {
      cycles++;
      beginCue('exchange', CUE_MS, true);
      nextCycle = time + CYCLE_MS;
    }
    paint();
  } catch (error) { fail(error); return; }
  schedule();
}
function schedule() {
  if (retired || failed || blocked || isStatic() || !renderer || timer || raf) return;
  // A timeout sleeps BETWEEN useful frames. Unlike the original, it does not
  // pump 144/240-Hz rAF merely to discard almost all callbacks.
  const period = cue || loading() ? 1000 / 24 : 1000 / 12;
  const delay = Math.max(0, period - (performance.now() - previousNow) - 5);
  timer = setTimeout(() => {
    timer = 0;
    if (!retired && !blocked && !isStatic()) raf = requestAnimationFrame(frame);
  }, delay);
}
function reconcile() {
  if (retired) return;
  if (document.body.classList.contains('cf7-host-hidden')) { retire('host-retired'); return; }
  const topHeight = document.querySelector('.topbar')?.getBoundingClientRect().height || 46;
  const topValue = `${Math.ceil(topHeight)}px`;
  if (document.body.style.getPropertyValue('--pm19-topbar-height') !== topValue) document.body.style.setProperty('--pm19-topbar-height', topValue);
  const wasBlocked = blocked;
  blocked = covered();
  document.body.dataset.bgGlLifecycle = failed ? 'static-fallback' : blocked ? 'paused-covered' : isStatic() ? 'paused-static' : renderer ? 'active' : 'loading';
  if (blocked || isStatic()) { clearSchedule(); previousNow = 0; }
  else if (wasBlocked) { previousNow = performance.now(); layoutDirty = paintDirty = true; }
  if (!blocked && paintDirty) safePaint();
  schedule();
  updatePauseControl();
}
function onLayout() {
  if (retired) return;
  layoutDirty = paintDirty = true;
  // Resize in static mode repaints ONCE with the same committed board.
  reconcile();
}
function pauseBackground(value) {
  if (retired) return;
  userPaused = !!value;
  previousNow = 0;
  paintDirty = true;
  reconcile();
}
function updatePauseControl() {
  const checkbox = document.getElementById('pm19-pause');
  if (!checkbox) return;
  checkbox.checked = userPaused;
  checkbox.disabled = failed;
  const text = document.getElementById('pm19-motion-note');
  const copy = failed ? '背景已静态回退；启动与存档操作不受影响。' : media.matches ? '系统已启用减少动态，背景保持静止。' : '仅本次启动生效；不改变音频和显示设置。';
  if (text && text.textContent !== copy) text.textContent = copy;
}
function mountPauseControl() {
  if (retired) return;
  const parent = document.querySelector('#about-pane-document .audio-toggles');
  if (parent && !document.getElementById('pm19-pause')) {
    const section = document.createElement('div');
    section.id = 'pm19-motion';
    section.innerHTML = '<label class="audio-toggle"><input type="checkbox" id="pm19-pause"><span>暂停背景动态</span></label><p id="pm19-motion-note"></p>';
    parent.after(section);
    section.querySelector('input').addEventListener('change', event => pauseBackground(event.target.checked));
  }
  updatePauseControl();
}
function fail(error) {
  if (retired || failed) return;
  failed = true;
  clearSchedule(); cue = null;
  console.warn('[bg-gl] V2 static fallback:', error);
  // Retain CSS environmental detail; release damaged bitmaps. Never remove UI.
  if (renderer) renderer.dispose();
  renderer = null;
  if (canvas) canvas.hidden = true;
  document.body.dataset.bgGlLifecycle = 'static-fallback';
  updatePauseControl();
}
function retire(reason = 'retired') {
  if (retired) return;
  retired = true;
  clearSchedule();
  for (const observer of observers) observer.disconnect();
  for (const dispose of disposers.splice(0)) dispose();
  for (const off of unsubs.splice(0)) off();
  if (renderer) renderer.dispose();
  renderer = engine = board = scratch = null;
  cue = null;
  if (canvas) canvas.remove();
  canvas = null;
  document.getElementById('pm19-motion')?.remove();
  document.body.dataset.bgGlLifecycle = reason;
}

// Dev-only pull inspection, no production toolbar and no hot-path snapshots.
// Callers receive COPIES, never a mutable authoritative board or engine.
export function inspect() {
  return { version: 2, renderer: renderer ? 'canvas2d-cached' : null,
    retired, failed, blocked, paused: userPaused, reduced: media.matches,
    time, commits, cycles, callbacks, cues, scheduled: !!(timer || raf),
    cue: cue ? { ...cue } : null, hostState, userIntent, visualKind: visualKind(),
    canvas: renderer ? { width: renderer.width, height: renderer.height, cache: renderer.useCache,
      masks: renderer.masks.map(({ x, y, w, h }) => ({ x, y, w, h })),
      renders: renderer.renders, rebuilds: renderer.rebuilds, estimatedPixelBytes: renderer.width * renderer.height * 4 * (renderer.surfaces.length + 1) } : null,
    board: board ? Array.from(board) : null };
}

async function main() {
  if (!(canvas instanceof HTMLCanvasElement)) return;
  // Arm single-way teardown BEFORE the first await.
  listen(window, 'pagehide', () => retire('pagehide'));
  listen(document, 'visibilitychange', reconcile);
  listen(window, 'resize', onLayout);
  listen(document, 'scroll', onLayout, true);
  listen(media, 'change', () => { paintDirty = true; previousNow = 0; reconcile(); });
  listen(canvas, 'contextlost', () => fail(new Error('2D context lost')));
  const bodyObserver = new MutationObserver(onLayout);
  bodyObserver.observe(document.body, { attributes: true, attributeFilter: ['class'] });
  observers.push(bodyObserver);
  const viewObserver = new MutationObserver(onLayout);
  for (const id of ['view-welcome', 'view-slots']) {
    const el = document.getElementById(id);
    if (el) viewObserver.observe(el, { attributes: true, attributeFilter: ['hidden', 'class'] });
  }
  viewObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['style'] });
  observers.push(viewObserver);
  const modal = document.getElementById('modal-host');
  if (modal) {
    const mo = new MutationObserver(() => { mountPauseControl(); reconcile(); });
    mo.observe(modal, { attributes: true, attributeFilter: ['style'], childList: true, subtree: true });
    observers.push(mo);
  }
  if (typeof ResizeObserver === 'function') {
    const ro = new ResizeObserver(onLayout);
    for (const selector of ['.welcome-card', '.topbar', '#cards', '.side-r .faction']) {
      const el = document.querySelector(selector); if (el) ro.observe(el);
    }
    observers.push(ro);
  }
  reconcile();
  if (retired) return;
  const app = window.BootstrapApp;
  if (app?.onMessage) {
    unsubs.push(app.onMessage('list_resp', () => {
      if (!firstList) { firstList = true; beginCue('arrival'); }
      layoutDirty = paintDirty = true; reconcile();
    }, { replayLatest: true }));
    unsubs.push(app.onMessage('state', message => {
      const next = message.state;
      if (next === hostState) return;
      const old = hostState; hostState = next;
      paintDirty = true;
      if (old === 'Error') cue = null;
      if (next === 'Error') { userIntent = false; beginCue('error', 1500); }
      else if (next === 'Idle' && old && old !== 'Idle') {
        userIntent = false; nextCycle = time + CYCLE_MS; beginCue('return', 1200);
      }
      // Ready is often PREWARM. Never start, reveal, retire or declare success.
      reconcile();
    }, { replayLatest: true }));
    unsubs.push(app.onMessage('flash_ready', () => { reconcile(); }, { replayLatest: true }));
  }
  listen(document.getElementById('btn-confirm-start'), 'click', event => {
    if (event.currentTarget.disabled || retired || covered()) return;
    userIntent = true; beginCue('confirm', 1200); safePaint();
    // Original handler continues immediately, including video/loading coverage.
  }, true);
  for (const id of ['btn-switch-slot', 'btn-back-welcome']) {
    listen(document.getElementById(id), 'click', () => { beginCue('return', 1000); });
  }
  const manifest = await loadPrimeMagicSeedBank(SEED_BANK);
  if (retired) return;
  const entries = manifest.seeds.map(entry => ({ ...entry,
    url: new URL(entry.url.slice(entry.url.lastIndexOf('/') + 1), SEED_BANK).href }));
  const seeds = await Promise.all(entries.map(loadPrimeMagicSeed));
  if (retired) return;
  engine = new PrimeMagicSeedBankOrbitEngine(seeds, crypto.getRandomValues(new BigUint64Array(1))[0]);
  board = new Uint32Array(engine.cellCount); scratch = new Uint32Array(engine.cellCount);
  engine.nextInto(board); commits++;
  renderer = new EnvironmentRenderer(canvas);
  renderer.updateValues(board);
  previousNow = performance.now();
  layoutDirty = paintDirty = true;
  reconcile();
  // Fonts may settle after cached numerals. Invalidate only once and never revive.
  const fontsPending = document.fonts?.status !== 'loaded';
  document.fonts?.ready.then(() => {
    if (fontsPending && !retired && !failed && renderer) { renderer.dirty = true; paintDirty = true; reconcile(); }
  });
}
main().catch(fail);
