import { SafeSession } from './state.mjs';
import { SafeView } from './scene.mjs';
import { CONFIG, STRUCTURES, PUZZLE_TYPES, resolveStructureSpec } from './config.mjs';
import { manualPage, manualIndex } from './manual.mjs';
import { createPuzzle, enumerateParams, generatePuzzle, isLegalParams, solvePuzzle, createRng, deriveSafeSeed } from './puzzles.mjs';

export {
  SafeSession,
  SafeView,
  CONFIG,
  STRUCTURES,
  PUZZLE_TYPES,
  resolveStructureSpec,
  createPuzzle,
  enumerateParams,
  generatePuzzle,
  isLegalParams,
  solvePuzzle,
  createRng,
  deriveSafeSeed,
};

function createFallbackView(container, callbacks = {}) {
  let state = null;
  let demo = null;
  let animTimer = 0;
  return {
    drag: null,
    demo: null,
    cutaway: false,
    cameraName: 'default',
    inspection: false,
    serviceOpen: false,
    listenerCount: 0,
    targets: { a: { x: 160, y: 180, z: 0.5 }, b: { x: 160, y: 260, z: 0.5 } },
    async ready() {},
    setState(nextState) {
      state = nextState;
      if (animTimer) { clearTimeout(animTimer); animTimer = 0; }
      if (state.door === 'opening' && state.unlock?.token) {
        const token = state.unlock.token;
        animTimer = setTimeout(() => {
          animTimer = 0;
          callbacks.onFinish?.(token);
        }, 40);
      }
    },
    renderNow() {
      const a = state?.mechanics.a.progress || 0;
      const b = state?.mechanics.b.progress || 0;
      const door = state?.door === 'open' ? 1 : 0;
      callbacks.onPose?.({ a, b, latch: b || door, fence: door, bolts: door, door, label: '软件回退视图' }, !!demo);
    },
    setCutaway(v) { this.cutaway = !!v; this.renderNow(); },
    setCamera(name) { this.cameraName = name; this.inspection = !['default', 'operation'].includes(name); this.renderNow(); return true; },
    prepareTool() { this.serviceOpen = true; this.cameraName = 'operation'; this.inspection = false; this.renderNow(); return true; },
    preparePassword() { this.cameraName = 'default'; this.inspection = false; this.renderNow(); },
    cancelDrag() { this.drag = null; },
    startDemo() { demo = { active: true }; this.demo = demo; return true; },
    stopDemo() { demo = null; this.demo = null; },
    setHidden() {},
    stats() { return { disposed: false, frames: 1, fallback: true }; },
    dispose() { if (animTimer) clearTimeout(animTimer); animTimer = 0; },
  };
}

export async function mountSafeRuntime(rootEl, options = {}) {
  const q = sel => rootEl.querySelector(sel);
  const byId = id => rootEl.querySelector(`#${id}`) || rootEl.querySelector(`[data-safe-id="${id}"]`);
  const started = performance.now();
  const devMode = Boolean(options.devMode ?? true);
  const abort = new AbortController();
  const urls = new Set();
  const revokeTimers = new Set();
  const uiEvents = [];
  let session = null;
  let view = null;
  let unsubscribe = null;
  let destroyed = false;
  let manualCache = '';
  let memoSvgCache = '';
  let uiListenerCount = 0;
  let firstInteractiveMs = null;
  let sessionClockOrigin = null;

  const playSound = (name, meta) => {
    try {
      if (typeof options.onSound === 'function') {
        options.onSound(name, meta);
        return;
      }
      if (typeof globalThis.LockboxAudio !== 'undefined' && globalThis.LockboxAudio && !globalThis.LockboxAudio.isMuted()) {
        globalThis.LockboxAudio.resume?.();
        globalThis.LockboxAudio.play?.(name, meta);
      }
    } catch {}
  };

  const listen = (element, event, fn, opts = {}) => {
    if (!element) return;
    element.addEventListener(event, fn, { ...opts, signal: abort.signal });
    uiListenerCount++;
  };

  function record(type, details = {}) {
    uiEvents.push({ type, atNavigationMs: performance.now(), run: session?.state.run ?? 0, ...details });
  }

  function feedback(message, kind = '') {
    if (!message) return;
    const node = byId('feedback');
    if (!node) return;
    node.textContent = message;
    node.className = 'feedback ' + kind;
  }

  function download(blob, name) {
    const url = URL.createObjectURL(blob);
    urls.add(url);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    a.click();
    const t = setTimeout(() => {
      URL.revokeObjectURL(url);
      urls.delete(url);
      revokeTimers.delete(t);
    }, 1500);
    revokeTimers.add(t);
  }

  function payload({ includeAnswers = false } = {}) {
    const include = devMode && includeAnswers;
    const stats = view ? view.stats() : {};
    if (!include) {
      delete stats.modelAudit;
      delete stats.poseAudit;
    }
    return {
      prototype: 'CF7 safe dual-route V2 (Visual Cipher + T1/T2)',
      version: CONFIG.version,
      firstInteractiveMs,
      moduleInitializationMs: firstInteractiveMs === null ? null : firstInteractiveMs - started,
      environment: {
        userAgent: navigator.userAgent,
        devicePixelRatio: globalThis.devicePixelRatio || 1,
        viewport: { width: globalThis.innerWidth || 0, height: globalThis.innerHeight || 0 },
        ...stats,
      },
      humanTimingValidated: false,
      ...(session ? session.exportLog({ includeAnswers: include }) : {}),
      uiEvents: structuredClone(uiEvents),
    };
  }

  function saveLog() {
    if (!session) return null;
    const data = payload({ includeAnswers: devMode });
    if (!options.skipDownload) {
      download(
        new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }),
        `CF7-safe-V2-log-${session.state.seriesSeed.replace(/[^a-z0-9-]/gi, '_')}-${session.state.safeIndex}.json`
      );
    }
    options.onExport?.(data);
    return data;
  }

  function drawGestureGuide() {
    const svg = byId('gesture-guide');
    if (!svg || !view) return;
    const d = view.drag;
    svg.toggleAttribute('hidden', !d);
    if (!d) return;
    const vp = byId('viewport');
    if (!vp) return;
    const r = vp.getBoundingClientRect(), g = d.gesture;
    let points;
    if (g.kind === 'arc') {
      points = g.path.map(q => [q.x - r.left, q.y - r.top]);
    } else {
      const p = d.operation.path[0];
      points = [[p.x, p.y], [p.x + g.vector[0] * g.distance, p.y + g.vector[1] * g.distance]];
    }
    const path = points.map((q, i) => (i ? 'L' : 'M') + q.map(v => v.toFixed(1)).join(' ')).join(' ');
    svg.setAttribute('viewBox', `0 0 ${Math.max(1, r.width)} ${Math.max(1, r.height)}`);
    const strokeColor = d.jammed || d.wrong ? '#e06c58' : '#efd099';
    svg.innerHTML = `<defs><marker id="drag-arrow" markerWidth="7" markerHeight="7" refX="5" refY="3.5" orient="auto"><path d="M0 0 7 3.5 0 7Z" fill="${strokeColor}"/></marker></defs><path d="${path}" fill="none" stroke="#182831" stroke-width="6"/><path d="${path}" fill="none" stroke="${strokeColor}" stroke-width="2" stroke-dasharray="3 3" marker-end="url(#drag-arrow)"/>`;
  }

  function reflectPose(p, demo) {
    for (const key of ['a', 'b']) {
      const node = byId('target-' + key), target = view?.targets?.[key];
      if (!node || !target) continue;
      node.style.left = target.x + 'px';
      node.style.top = target.y + 'px';
      const active = !demo && session?.state.panelOpen && !session.state.suspended && session.state.door === 'locked' && view.serviceOpen && !view.inspection && view.cameraName === 'operation' && target.z < 1;
      node.classList.toggle('ready', !!active);
      node.classList.toggle('completed', !!session?.state.mechanics[key].complete);
      node.classList.toggle('selected', !!session && session.state.selectedTool === STRUCTURES[key][session.state.variants[key]].tool);
    }
    drawGestureGuide();
    const stopDemoBtn = byId('stop-demo'), demoCap = byId('demo-caption');
    if (stopDemoBtn) stopDemoBtn.hidden = !demo;
    if (demoCap) {
      demoCap.hidden = !demo;
      if (demo) demoCap.textContent = '机构演示 · ' + p.label + '（演示结束返回本箱）';
    }
    const status = p.door > .995
      ? '门闩收回 · 箱体已开启'
      : p.door > 0
        ? '门铰外开'
        : p.bolts > 0
          ? '把手转动 · 粗门闩回收'
          : p.latch > .99
            ? '小锁舌已让位'
            : p.fence > 0
              ? '三轮槽对齐 · 整体栅杆落下'
              : p.b > 0
                ? '牵引输出 · 小锁舌回收'
                : p.jamB > 0.01
                  ? '联锁受阻 · 挡肩撞击黄铜下舌 (~12%)'
                  : p.a > .99
                    ? '卸荷止点保持（咔哒） · 可牵引释放'
                    : '小锁舌保持 · 门闩伸出';
    const mechStatus = byId('mechanical-status');
    if (mechStatus) mechStatus.textContent = status;
    const viewDesc = byId('view-description');
    if (viewDesc && view) {
      viewDesc.textContent = view.inspection
        ? '检查视角 · 重新取工具可回到稳定近景'
        : view.cameraName === 'operation'
          ? (view.cutaway ? '机构近景 / 局部剖视 · 认准黄铜止挡销向敞口拖' : '维护盖已揭开 · 认准黄铜止挡销，向敞口方向短拖')
          : (view.cutaway ? '局部剖视 · 工具从门外作用' : '正常外观 · 取工具即进入双机构近景');
    }
    byId('normal-view')?.classList.toggle('active', !view?.cutaway);
    byId('cutaway-view')?.classList.toggle('active', !!view?.cutaway);
    const openLabel = byId('open-label');
    if (openLabel) openLabel.hidden = demo || session?.state.door !== 'open';
    const badge = byId('phase-badge');
    if (badge && session) {
      badge.textContent = session.state.door === 'open'
        ? 'OPEN'
        : session.state.door === 'opening'
          ? 'OPENING'
          : session.state.mechanics.a.complete
            ? 'STAGE Ⅱ'
            : 'LOCKED';
    }
  }

  function renderState(state, reason = '') {
    if (destroyed && reason !== 'destroy') return;
    view?.setState(state, reason);
    if (reason === 'tool_preview') return;
    const memoEl = byId('memo'), memoTitleEl = byId('memo-title'), memoDiagramEl = byId('memo-diagram');
    if (memoEl) memoEl.textContent = state.puzzle.memo;
    if (memoTitleEl) memoTitleEl.textContent = state.puzzle.title;
    if (memoDiagramEl) {
      const svgKey = `${state.run}:${state.noteSource === 'skill' ? 'solved' : 'raw'}`;
      if (memoSvgCache !== svgKey) {
        memoSvgCache = svgKey;
        memoDiagramEl.innerHTML = (state.noteSource === 'skill' && state.puzzle.solvedSvg) ? state.puzzle.solvedSvg : (state.puzzle.svg || '');
      }
    }
    const codeInput = byId('code');
    if (codeInput && codeInput.value !== state.note) codeInput.value = state.note;
    const skillChk = byId('skill'), skillLbl = byId('skill-label');
    if (skillChk) skillChk.checked = state.skill;
    if (skillLbl) skillLbl.textContent = state.skill ? '已达标' : '未达标';
    const blocked = state.door !== 'locked' || state.suspended || !!view?.demo;
    for (const id of ['code', 'unlock', 'skill', 'tool-wedge', 'tool-hook']) {
      const el = byId(id);
      if (el) el.disabled = blocked;
    }
    const idBtn = byId('identify'), demoBtn = byId('demo');
    if (idBtn) idBtn.disabled = blocked || !state.skill;
    if (demoBtn) demoBtn.disabled = state.suspended || state.door === 'opening';
    byId('tool-wedge')?.classList.toggle('active', state.selectedTool === 'wedge');
    byId('tool-hook')?.classList.toggle('active', state.selectedTool === 'hook');
    byId('stage-a')?.classList.toggle('done', state.mechanics.a.complete);
    byId('stage-b')?.classList.toggle('done', state.mechanics.b.complete);
    const closedOverlay = byId('closed-overlay');
    if (closedOverlay) closedOverlay.hidden = state.panelOpen && !state.destroyed;
    const manualBody = byId('manual-body'), toggleHelpBtn = byId('toggle-help');
    if (manualBody) manualBody.hidden = !state.help.open;
    if (toggleHelpBtn) {
      toggleHelpBtn.textContent = state.help.open ? '收起' : '展开';
      toggleHelpBtn.setAttribute('aria-expanded', String(state.help.open));
    }
    const manualKey = String(state.help.page);
    if (manualCache !== manualKey) {
      manualCache = manualKey;
      const mc = byId('manual-content'), mi = byId('manual-index');
      if (mc) { mc.innerHTML = manualPage(state.help.page); mc.scrollTop = 0; }
      if (mi) mi.innerHTML = manualIndex(state.help.page);
    }
    const pageNum = byId('page-number');
    if (pageNum) pageNum.textContent = String(state.help.page + 1).padStart(2, '0') + ' / 09';
    byId('tab-mechanism')?.classList.toggle('active', state.help.page < 6);
    byId('tab-puzzles')?.classList.toggle('active', state.help.page >= 6);
    const seedLbl = byId('seed-label'), safeIdxLbl = byId('safe-index'), totalTimeLbl = byId('total-time'), polarityLbl = byId('polarity-label');
    if (seedLbl) seedLbl.textContent = state.seriesSeed;
    if (safeIdxLbl) safeIdxLbl.textContent = `第 ${state.safeIndex + 1} 箱 / 第 ${state.attempt} 次`;
    if (polarityLbl) {
      const specA = session.stageSpec('a'), specB = session.stageSpec('b');
      polarityLbl.textContent = `Ⅰ:${specA.id}(${specA.dir > 0 ? '+' : '-'}) · Ⅱ:${specB.id}(${specB.dir > 0 ? '+' : '-'})`;
    }
    const timing = session.timing();
    if (totalTimeLbl) totalTimeLbl.textContent = timing.completed ? (timing.elapsedMs / 1000).toFixed(2) + ' s' : '待开箱';
    if (state.validation) {
      feedback(state.validation.message, 'error');
    } else if (reason === 'open') {
      playSound('finishPerfect');
      feedback('保险柜已打开！可重试本箱，或继续下一只。', 'success');
      options.onUnlockComplete?.(session.snapshot(), timing);
    } else if (reason === 'reset') {
      feedback('本箱已就绪。看图推导三位密码，或取工具按止挡销方向操作。');
    }
    if (devMode && (reason === 'reset' || reason === 'initial')) {
      const va = byId('variant-a'), vb = byId('variant-b'), vad = byId('polarity-a'), vbd = byId('polarity-b'), pt = byId('puzzle-type'), si = byId('seed-input');
      if (va) va.value = String(state.variants.a);
      if (vb) vb.value = String(state.variants.b);
      if (vad) vad.value = String(state.variants.aDir ?? 1);
      if (vbd) vbd.value = String(state.variants.bDir ?? 1);
      if (pt) pt.value = state.puzzle.type;
      if (si) si.value = state.seriesSeed;
    }
    options.onStateChange?.(state, reason);
  }

  function selectTool(tool) {
    if (destroyed || view?.demo || session.state.door !== 'locked' || session.state.suspended) return;
    session.setRoute('tools');
    const result = session.selectTool(tool);
    if (result.ok) {
      playSound('tapLegal', { tokenId: tool === 'wedge' ? 1 : 0 });
      view.prepareTool();
      const stage = tool === 'wedge' ? 'a' : 'b';
      const spec = session.stageSpec(stage);
      feedback(`已取${tool === 'wedge' ? '卸载键' : '牵引钩'}。观察${spec.title}上的黄铜止挡销，向敞口方向短拖至止点。`);
    }
  }

  function prepareNewRun() {
    view?.cancelDrag('new_run');
    view?.stopDemo();
  }

  function reset(seed, overrides, resetOpts) {
    prepareNewRun();
    const result = session.reset(seed, overrides, resetOpts);
    options.onReset?.(session.state);
    return result;
  }

  function retryCurrent() {
    prepareNewRun();
    const result = session.retryCurrent();
    options.onReset?.(session.state);
    return result;
  }

  function nextSafe() {
    prepareNewRun();
    const result = session.nextSafe();
    options.onReset?.(session.state);
    return result;
  }

  function startDemo() {
    if (view.demo) {
      view.stopDemo();
      renderState(session.state, 'demo_end');
      return;
    }
    if (view.startDemo()) {
      renderState(session.state, 'demo_start');
      feedback('正在展示密码机构的完整联动动作；演示不会解锁或改写当前箱体。');
    }
  }

  function destroy() {
    if (destroyed) return;
    view?.cancelDrag('destroy');
    session?.destroy();
    unsubscribe?.();
    view?.dispose();
    abort.abort();
    uiListenerCount = 0;
    for (const timer of revokeTimers) clearTimeout(timer);
    revokeTimers.clear();
    for (const url of urls) URL.revokeObjectURL(url);
    urls.clear();
    destroyed = true;
    record('instance_disposed');
  }

  const seed = String(options.seed ?? 'CF7-20261029');
  const requestedIndex = Number(options.safeIndex ?? 0);
  const safeIndex = Number.isSafeInteger(requestedIndex) && requestedIndex >= 0 ? requestedIndex : 0;
  const overrides = options.overrides && typeof options.overrides === 'object' ? { ...options.overrides } : {};

  const toggleDebugBtn = byId('toggle-debug');
  if (toggleDebugBtn) toggleDebugBtn.hidden = !devMode;

  const viewportEl = byId('viewport');
  const viewCallbacks = {
    onFinish: token => session.finishUnlock(token),
    onAction: (stage, action) => {
      session.setRoute('tools');
      const res = session.operate(stage, action);
      if (action.commit && res.code === 'complete') playSound('mainSolved');
      else if (action.commit && res.code === 'opening') playSound('finisherArm');
      else if (!res.ok && (res.code === 'prerequisite' || res.code === 'direction')) playSound('illegalPulse');
      return res;
    },
    onCancel: reason => session?.cancelAction(reason),
    onUIEvent: (type, details) => {
      record(type, details);
      if (type === 'demo_end' && session) renderState(session.state, 'demo_end');
    },
    onFeedback: feedback,
    onPose: reflectPose,
  };

  try {
    view = new SafeView(viewportEl, viewCallbacks);
  } catch (err) {
    console.warn('[SafeRuntime] WebGL fallback activated:', err?.message || err);
    view = createFallbackView(viewportEl, viewCallbacks);
  }

  await view.ready();
  session = new SafeSession({
    seed,
    safeIndex,
    overrides,
    documentHidden: document.hidden,
    clock: () => sessionClockOrigin === null ? 0 : performance.now() - sessionClockOrigin,
  });
  unsubscribe = session.subscribe(renderState);
  renderState(session.state, 'initial');
  view.renderNow();

  listen(byId('code'), 'focus', () => {
    if (!view.demo) {
      session.setRoute('password');
      view.preparePassword();
    }
  });
  listen(byId('code'), 'input', e => session.setNote(e.target.value));
  listen(byId('code-form'), 'submit', e => {
    e.preventDefault();
    if (view.demo) return;
    session.setRoute('password');
    view.preparePassword();
    const r = session.submitPassword();
    if (r.ok) {
      playSound('finisherArm');
      feedback('密码已确认，角色正在代办拨盘与开门。', 'success');
    } else if (r.message) {
      playSound('illegalGrace');
      feedback(r.message, 'error');
    }
  });
  listen(byId('skill'), 'change', () => session.setSkill(byId('skill').checked));
  listen(byId('identify'), 'click', () => {
    const r = session.identifyPassword();
    if (r.ok) {
      playSound('seqMatch', { which: 'A' });
      byId('code')?.focus({ preventScroll: true });
      feedback('图推暗语已标红解析并填入纸条。按 Enter 或点击“开锁”。', 'success');
    }
  });
  listen(byId('tool-wedge'), 'click', () => selectTool('wedge'));
  listen(byId('tool-hook'), 'click', () => selectTool('hook'));
  listen(byId('normal-view'), 'click', () => { view.setCutaway(false); record('cutaway_changed', { value: false }); });
  listen(byId('cutaway-view'), 'click', () => { view.setCutaway(true); record('cutaway_changed', { value: true }); });
  listen(byId('home-view'), 'click', () => { view.setCamera('default'); record('camera_changed', { name: 'default' }); });
  listen(byId('demo'), 'click', startDemo);
  listen(byId('stop-demo'), 'click', () => { view.stopDemo(); renderState(session.state, 'demo_end'); });
  listen(byId('toggle-help'), 'click', () => session.setHelp(!session.state.help.open));
  listen(byId('puzzle-help'), 'click', () => session.setHelp(true, session.state.puzzle.manualPage));
  listen(byId('tab-mechanism'), 'click', () => session.setHelp(true, Math.min(session.state.help.page, 5)));
  listen(byId('tab-puzzles'), 'click', () => session.setHelp(true, session.state.puzzle.manualPage));
  listen(byId('previous-page'), 'click', () => session.setHelp(true, (session.state.help.page + 8) % 9));
  listen(byId('next-page'), 'click', () => session.setHelp(true, (session.state.help.page + 1) % 9));
  listen(byId('manual-index'), 'click', e => {
    const node = e.target.closest('[data-page]');
    if (node) session.setHelp(true, Number(node.dataset.page));
  });
  listen(byId('reset'), 'click', retryCurrent);
  listen(byId('next-safe'), 'click', nextSafe);
  listen(byId('close-panel'), 'click', () => options.onRequestClose?.('button'));
  listen(byId('reopen'), 'click', () => session.reopen());
  listen(byId('export-log'), 'click', saveLog);
  listen(byId('mute-toggle'), 'click', () => options.onToggleMute?.());

  if (devMode) {
    listen(byId('toggle-debug'), 'click', () => {
      const dbg = byId('debug-panel');
      if (!dbg) return;
      dbg.hidden = !dbg.hidden;
      record('debug_panel', { open: !dbg.hidden });
    });
    listen(byId('hide-debug'), 'click', () => {
      const dbg = byId('debug-panel');
      if (dbg) dbg.hidden = true;
    });
    listen(byId('apply-config'), 'click', () => {
      try {
        reset(byId('seed-input').value, {
          a: Number(byId('variant-a').value),
          b: Number(byId('variant-b').value),
          aDir: Number(byId('polarity-a')?.value || 1),
          bDir: Number(byId('polarity-b')?.value || 1),
          puzzleType: byId('puzzle-type').value,
        });
        feedback('已生成指定结构极性与图推组合。');
      } catch (e) {
        feedback(e.message, 'error');
      }
    });
    listen(byId('random-config'), 'click', () => {
      try {
        reset(byId('seed-input').value, {});
        feedback('已按种子随机抽取 36 种极性结构与图推备忘。');
      } catch (e) {
        feedback(e.message, 'error');
      }
    });
    for (const button of rootEl.querySelectorAll('[data-camera]')) {
      listen(button, 'click', () => {
        view.setCamera(button.dataset.camera);
        record('camera_changed', { name: button.dataset.camera });
      });
    }
    listen(byId('export-glb'), 'click', async () => {
      try {
        const { GLTFExporter } = await import('../vendor/GLTFExporter.js');
        const result = await new GLTFExporter().parseAsync(view.model.root, { binary: true, onlyVisible: true });
        download(new Blob([result], { type: 'model/gltf-binary' }), 'CF7-safe-V2-current.glb');
        feedback('已导出当前可见姿态 GLB。');
      } catch (e) {
        feedback('GLB 导出失败：' + e.message, 'error');
      }
    });
    listen(byId('destroy-instance'), 'click', destroy);
  }

  listen(document, 'keydown', e => {
    if (destroyed || !session?.state.panelOpen) return;
    if (e.key === 'Escape') {
      if (view.demo) {
        e.preventDefault();
        view.stopDemo();
        renderState(session.state, 'demo_end');
        return;
      }
      if (view.drag) {
        e.preventDefault();
        view.cancelDrag('escape');
        return;
      }
      return;
    }
    const typing = /INPUT|TEXTAREA|SELECT/.test(e.target?.tagName || '');
    if (!typing && session.state.panelOpen) {
      if (e.key === '1') selectTool('wedge');
      if (e.key === '2') selectTool('hook');
    }
  });

  listen(document, 'visibilitychange', () => {
    if (destroyed) return;
    session.setDocumentHidden(document.hidden);
    view.setHidden(document.hidden);
    record(document.hidden ? 'document_hidden' : 'document_visible');
  });

  firstInteractiveMs = performance.now();
  sessionClockOrigin = firstInteractiveMs;
  const loadTimeEl = byId('load-time'), loadingEl = byId('loading');
  if (loadTimeEl) loadTimeEl.textContent = ((firstInteractiveMs - started) / 1000).toFixed(2) + ' s';
  if (loadingEl) loadingEl.hidden = true;
  if (!document.hidden) byId('code')?.focus({ preventScroll: true });
  record('panel_interactive', { firstInteractiveMs });

  const api = {
    session,
    view,
    reset,
    retryCurrent,
    nextSafe,
    destroy,
    dispose: destroy,
    startDemo,
    stopDemo: () => { view.stopDemo(); renderState(session.state, 'demo_end'); },
    selectTool,
    exportLog: payload,
    saveLog,
    stats: () => ({ uiListeners: uiListenerCount, urlCount: urls.size, revokeTimers: revokeTimers.size, destroyed, ...(view ? view.stats() : {}) }),
    get ready() { return firstInteractiveMs !== null; },
  };

  if (devMode) {
    Object.defineProperty(globalThis, '__CF7_SAFE', { value: api, configurable: true });
  }
  Object.defineProperty(globalThis, '__CF7_SAFE_PUBLIC', {
    value: Object.freeze({
      snapshot: () => session.publicSnapshot(),
      exportLog: () => payload(),
      get ready() { return firstInteractiveMs !== null; },
    }),
    configurable: true,
  });

  return api;
}
