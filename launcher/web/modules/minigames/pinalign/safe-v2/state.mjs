import { CONFIG, STRUCTURES, TOOLS, resolveStructureSpec } from './config.mjs';
import { createRng, deriveSafeSeed, generatePuzzle } from './puzzles.mjs';

const passwordFormat = new RegExp(CONFIG.password.pattern);
const stages = ['a', 'b'];
const defaultClock = () => globalThis.performance?.now() ?? Date.now();
const ok = (code, rest = {}) => ({ ok: true, code, ...rest });
const fail = (code, message, rest = {}) => ({ ok: false, code, message, ...rest });

/**
 * Pure interaction authority. No DOM, timers, rendering, storage, or game protocol.
 * Rendering reads state; only these methods should write it.
 * clock is injectable and must return milliseconds. Methods are synchronous.
 */
export class SafeSession {
  constructor({ seed = 'CF7-20261018', safeIndex = 0, overrides = {}, documentHidden = false, clock = defaultClock } = {}) {
    if (typeof clock !== 'function') throw new TypeError('clock must be a function');
    this.clock = clock;
    this.listeners = new Set();
    this.log = [];
    this._lastNow = Number(clock());
    if (!Number.isFinite(this._lastNow)) throw new TypeError('clock must return finite milliseconds');
    this._origin = this._lastNow;
    this._run = 0;
    this._unlockSequence = 0;
    this._passwordAuthorized = false;
    this._buildRun(seed, overrides, { safeIndex, documentHidden: Boolean(documentHidden), reason: 'initial' });
  }

  _now() {
    const current = Number(this.clock());
    if (Number.isFinite(current)) this._lastNow = Math.max(current, this._lastNow);
    return this._lastNow;
  }

  _buildRun(seriesSeed, overrides, { safeIndex = 0, attempt = 1, reason = 'reset', documentHidden = this.state?.documentHidden ?? false } = {}) {
    const baseSeed = String(seriesSeed);
    const seedText = deriveSafeSeed(baseSeed, safeIndex);
    if (!overrides || typeof overrides !== 'object' || Array.isArray(overrides)) {
      throw new TypeError('overrides must be an object');
    }
    const rng = createRng(`${seedText}:structures`);
    // Consume all four independent slots even when one has a development override.
    // Pinning A must not silently change an otherwise random B or its polarity.
    const randomA = Math.floor(rng() * 3), randomB = Math.floor(rng() * 3);
    const randomADir = rng() < 0.5 ? 1 : -1, randomBDir = rng() < 0.5 ? 1 : -1;
    const a = overrides.a ?? randomA;
    const b = overrides.b ?? randomB;
    const aDir = overrides.aDir ?? (overrides.a !== undefined ? 1 : randomADir);
    const bDir = overrides.bDir ?? (overrides.b !== undefined ? 1 : randomBDir);
    if (![a, b].every(v => Number.isInteger(v) && v >= 0 && v <= 2)) {
      throw new RangeError('Structure variants must be integers 0, 1, or 2');
    }
    if (![aDir, bDir].every(v => v === 1 || v === -1)) {
      throw new RangeError('Structure polarities must be 1 or -1');
    }
    // Build fallible data before modifying current state so an invalid debug override is atomic.
    const puzzle = generatePuzzle(seedText, { type: overrides.puzzleType, params: overrides.puzzleParams });
    const savedOverrides = structuredClone(overrides);
    if (this.state) {
      this.cancelAction(reason);
      if (!this.state.suspended && this.state.help.open) this._record('help_close', { page: this.state.help.page, reason });
      if (this.state.door === 'opening') this._record('animation_cancel', { token: this.state.unlock.token, reason });
      this._record('session_reset', {
        nextRun: this._run + 1, nextSeed: seedText, nextSeriesSeed: baseSeed,
        nextSafeIndex: safeIndex, nextAttempt: attempt, previousDoor: this.state.door, reason,
      });
    }
    this._run++;
    this._runStart = this._now();
    this._pausedMs = 0;
    this._pauseStart = documentHidden ? this._runStart : null;
    this._firstInput = false;
    this._readyLogged = false;
    this._passwordAuthorized = false;
    this._overrides = savedOverrides;
    this.state = {
      version: CONFIG.version, run: this._run, seed: seedText,
      seriesSeed: baseSeed, safeIndex, attempt,
      puzzle, variants: { a, b, aDir, bDir }, note: '', noteSource: null, skill: false,
      route: 'password', selectedTool: null,
      mechanics: {
        a: { progress: 0, complete: false },
        b: { progress: 0, complete: false },
        smallBoltRetracted: false, fenceDropped: false, releaseMode: null, releaseAuthorized: false,
      },
      drag: null, door: 'locked', unlock: null,
      panelOpen: true, documentHidden, suspended: documentHidden,
      help: { open: true, page: 0 },
      validation: null, destroyed: false,
    };
    this._record('session_initialized', { ...this._runIdentity(), documentHidden, reason });
    if (documentHidden) this._record('activity_pause', { reason: 'initial_hidden', ...this._suspensionCauses() });
    else {
      this._recordReady('initial');
      this._record('help_open', { page: 0, reason: 'initial' });
    }
  }

  stageSpec(stage) {
    if (!stages.includes(stage)) throw new RangeError('Unknown stage');
    const dir = stage === 'a' ? (this.state.variants.aDir ?? 1) : (this.state.variants.bDir ?? 1);
    return resolveStructureSpec(stage, this.state.variants[stage], dir);
  }

  stageDirection(stage) {
    return this.stageSpec(stage).direction;
  }

  _runIdentity() {
    const { seed, seriesSeed, safeIndex, attempt, variants, puzzle } = this.state;
    return {
      seed, seriesSeed, safeIndex, attempt, variants: { ...variants },
      puzzleType: puzzle.type, puzzleParams: structuredClone(puzzle.params), answer: puzzle.answer,
    };
  }

  _recordReady(reason) {
    if (this._readyLogged) return;
    this._readyLogged = true;
    this._record('session_ready', { ...this._runIdentity(), reason });
  }

  _suspensionCauses() {
    return { panelClosed: !this.state.panelOpen, documentHidden: this.state.documentHidden };
  }

  /** One interval represents the UNION of closed panel and hidden document. */
  _syncSuspension(reason, now = this._now()) {
    const suspended = !this.state.panelOpen || this.state.documentHidden;
    if (suspended === this.state.suspended) return;
    this.state.suspended = suspended;
    if (suspended) {
      this._pauseStart = now;
      this._record('activity_pause', { reason, ...this._suspensionCauses() });
      this.cancelAction(reason);
      if (this.state.help.open) this._record('help_close', { page: this.state.help.page, reason });
      if (this.state.door === 'opening') this._record('animation_pause', { token: this.state.unlock.token, reason });
    } else {
      const intervalMs = now - this._pauseStart;
      this._pausedMs += intervalMs;
      this._pauseStart = null;
      this._record('activity_resume', { reason, intervalMs, pausedMs: this._pausedMs, ...this._suspensionCauses() });
      this._recordReady(reason);
      if (this.state.help.open) this._record('help_open', { page: this.state.help.page, reason });
      if (this.state.door === 'opening') this._record('animation_resume', { token: this.state.unlock.token, reason });
    }
  }

  _activeMs(now = this._now()) {
    const openPause = this._pauseStart === null ? 0 : now - this._pauseStart;
    return Math.max(0, now - this._runStart - this._pausedMs - openPause);
  }

  _record(type, details = {}) {
    const now = this._now();
    const entry = {
      index: this.log.length, run: this._run, type,
      atMs: now - this._origin, elapsedMs: now - this._runStart,
      activeMs: this._activeMs(now), ...details,
    };
    this.log.push(entry);
    return entry;
  }

  _notify(reason) {
    for (const listener of [...this.listeners]) listener(this.state, reason);
  }

  _guard({ locked = false } = {}) {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    if (!this.state.panelOpen) return fail('closed', '面板已关闭，请重新打开。');
    if (this.state.documentHidden) return fail('hidden', '页面暂在后台；回到页面后继续。');
    if (locked && this.state.door !== 'locked') {
      return fail(this.state.door === 'opening' ? 'already_opening' : 'already_open',
        this.state.door === 'opening' ? '机构正在开启。' : '箱体已经打开。',
        { token: this.state.unlock?.token });
    }
    return null;
  }

  _reject(code, message, details = {}) {
    this.state.validation = { kind: code, message };
    this._record('operation_rejected', { code, ...details });
    this._notify('feedback');
    return fail(code, message);
  }

  subscribe(listener) {
    if (this.state.destroyed) return () => {};
    if (typeof listener !== 'function') throw new TypeError('listener must be a function');
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  snapshot() { return structuredClone(this.state); }

  /** Ordinary telemetry contains clues and player inputs, never a prepared answer. */
  publicSnapshot() {
    const state = this.snapshot();
    delete state.puzzle.answer;
    delete state.puzzle.solvedSvg;
    if (state.noteSource !== 'user' && state.note.length) {
      delete state.note;
      state.noteRedacted = true;
    }
    return state;
  }

  exportLog({ includeAnswers = false } = {}) {
    const events = structuredClone(this.log);
    if (!includeAnswers) for (const event of events) {
      delete event.answer;
      if (Object.hasOwn(event, 'value') &&
          ((event.source !== undefined && event.source !== 'user') || event.type === 'skill_autofill')) {
        delete event.value;
        event.valueRedacted = true;
      }
    }
    return {
      version: CONFIG.version, clock: 'monotonic milliseconds; instance origin = 0',
      timingNote: 'elapsedMs 保留墙钟区间；activeMs 扣除面板关闭与页面隐藏区间的并集，重叠不双扣。已开启总时长停在 unlock_complete。无输入区间不等于精确思考时间。',
      humanTimingValidated: false,
      answersIncluded: Boolean(includeAnswers),
      state: includeAnswers ? this.snapshot() : this.publicSnapshot(), events,
    };
  }

  timing() {
    const now = this._now();
    const events = this.log.filter(e => e.run === this.state.run);
    const finish = events.find(e => e.type === 'unlock_complete');
    return {
      elapsedMs: finish?.elapsedMs ?? now - this._runStart,
      activeMs: finish?.activeMs ?? this._activeMs(now),
      completed: Boolean(finish), humanTimingValidated: false,
    };
  }

  setNote(value, { source = 'user' } = {}) {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    const text = String(value);
    this.state.note = text;
    this.state.noteSource = source;
    this.state.validation = null;
    this._passwordAuthorized = false;
    if (source === 'user' && text.length && !this._firstInput) {
      this._firstInput = true;
      this._record('note_first_input', { value: text });
    }
    this._record('note_changed', { value: text, source });
    this._notify('note');
    return ok('note_changed');
  }

  submitPassword() {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    const note = this.state.note;
    if (note.length !== CONFIG.password.digits || !passwordFormat.test(note)) {
      this._record('password_submit', { value: note, source: this.state.noteSource, accepted: false, reason: 'format' });
      return this._reject('format', '请输入 100–999 的三位整数；不补零、不倒序。');
    }
    if (note !== this.state.puzzle.answer) {
      this._record('password_submit', { value: note, source: this.state.noteSource, accepted: false, reason: 'password' });
      return this._reject('password', '密码不符，请重新核对柜主备忘。');
    }
    this._record('password_submit', { value: note, source: this.state.noteSource, accepted: true });
    this._passwordAuthorized = true;
    return this.requestUnlock('password');
  }

  setSkill(value) {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    this.state.skill = Boolean(value);
    this.state.validation = null;
    this._record('skill_changed', { eligible: this.state.skill });
    this._notify('skill');
    return ok('skill_changed');
  }

  identifyPassword() {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    if (!this.state.skill) return this._reject('skill', '解密技能未达标；仍可看图推导或使用工具。');
    this.setNote(this.state.puzzle.answer, { source: 'skill' });
    this._record('password_identified');
    return ok('password_identified');
  }

  setRoute(route) {
    const blocked = this._guard();
    if (blocked) return blocked;
    if (route !== 'password' && route !== 'tools') return fail('route', '未知路线。');
    if (this.state.route !== route) {
      this.cancelAction('route_change');
      this.state.route = route;
      this._record('route_changed', { route });
      this._notify('route');
    }
    return ok('route_changed');
  }

  selectTool(tool) {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    if (tool !== null && !TOOLS.some(t => t.id === tool)) return this._reject('unknown_tool', '没有这件工具。');
    if (tool !== this.state.selectedTool) this.cancelAction('tool_change');
    this.state.selectedTool = tool;
    this.state.validation = null;
    this._record('tool_selected', { tool });
    this._notify('tool');
    return ok('tool_selected');
  }

  /**
   * progress is normalized displacement, not elapsed time. Preview commits nothing.
   * A valid release >= threshold snaps to its stop; shorter release restores only
   * the current unfinished component. No hold-to-wait completion path exists.
   */
  operate(stage, { direction, progress = 1, commit = true } = {}) {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    if (!stages.includes(stage)) return this._reject('stage', '未知作用点。');
    const mechanism = this.state.mechanics[stage];
    const spec = this.stageSpec(stage);
    if (mechanism.complete) return fail('already_complete', '这个结构已在止点，无需重做。');
    if (!Number.isFinite(progress)) return this._reject('progress', '拖动位移无效。', { stage });
    if (stage === 'b' && !this.state.mechanics.a.complete) {
      return this._reject('prerequisite', '承压联锁仍在阻挡；先完成结构Ⅰ卸载。', { stage });
    }
    if (this.state.selectedTool !== spec.tool) {
      return this._reject('tool', this.state.selectedTool ? spec.error : `先取${stage === 'a' ? '卸载键' : '牵引钩'}。`, { stage, tool: this.state.selectedTool });
    }
    if (direction !== spec.direction) return this._reject('direction', spec.error, { stage, direction, expectedDirection: spec.direction });
    if (this.state.drag && this.state.drag.stage !== stage) this.cancelAction('new_action');
    if (!this.state.drag) {
      this.state.drag = { stage, from: mechanism.progress, direction };
      this._record('tool_action_start', { stage, variant: spec.id, polarity: spec.dir, tool: spec.tool, direction });
    }
    mechanism.progress = Math.min(1, Math.max(0, progress));
    this.state.validation = null;
    if (!commit) {
      this._notify('tool_preview');
      return ok('preview', { progress: mechanism.progress });
    }
    if (mechanism.progress < CONFIG.interaction.completionThreshold) {
      const attempted = mechanism.progress;
      this.cancelAction('short_release');
      return ok('incomplete', { attempted, progress: mechanism.progress });
    }
    mechanism.progress = 1;
    mechanism.complete = true;
    this.state.drag = null;
    this._record('tool_action_complete', { stage, variant: spec.id, polarity: spec.dir, progress: 1 });
    if (stage === 'b') return this.requestUnlock('tools');
    this._notify('tool_complete');
    return ok('complete', { stage });
  }

  cancelAction(reason = 'cancel') {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    const drag = this.state.drag;
    if (!drag) return ok('no_action');
    const mechanism = this.state.mechanics[drag.stage];
    if (!mechanism.complete) mechanism.progress = drag.from;
    this.state.drag = null;
    this._record('tool_action_cancel', { stage: drag.stage, reason, progress: mechanism.progress });
    this._notify('tool_cancel');
    return ok('cancelled');
  }

  setHelp(open, page = this.state.help.page) {
    const blocked = this._guard();
    if (blocked) return blocked;
    if (!Number.isInteger(page) || page < 0 || page > 8) return fail('help_page', '手册页必须在 0–8 内。');
    const isOpen = Boolean(open);
    if (isOpen !== this.state.help.open) this._record(isOpen ? 'help_open' : 'help_close', { page });
    if (page !== this.state.help.page) this._record('help_page', { from: this.state.help.page, to: page });
    this.state.help = { open: isOpen, page };
    this._notify('help');
    return ok('help_changed');
  }

  requestUnlock(route) {
    const blocked = this._guard({ locked: true });
    if (blocked) return blocked;
    if (route !== 'password' && route !== 'tools') return fail('route', '未知路线。');
    if (route === 'password' && !this._passwordAuthorized) return fail('not_authorized', '必须先显式提交完整的正确密码。');
    if (route === 'tools' && !(this.state.mechanics.a.complete && this.state.mechanics.b.complete)) {
      return fail('not_authorized', '两个结构尚未完成。');
    }
    this.cancelAction('unlock');
    this._passwordAuthorized = false;
    const token = `${this.state.run}:${++this._unlockSequence}`;
    this.state.door = 'opening';
    this.state.unlock = { route, token };
    this.state.validation = null;
    this.state.mechanics.releaseAuthorized = true;
    this.state.mechanics.releaseMode = route;
    this._record('unlock_request', { route, token });
    this._record('animation_start', { route, token, plannedMs: CONFIG.timing.unlockMs });
    this._notify('unlock');
    return ok('opening', { token, route });
  }

  /** token is mandatory to reject stale callbacks from a reset/destroyed animation. */
  finishUnlock(token) {
    const blocked = this._guard();
    if (blocked) return blocked;
    if (this.state.door !== 'opening') return fail('not_opening', '没有等待完成的开启动画。');
    if (!token || token !== this.state.unlock.token) return fail('stale_token', '过期或缺失的开启动画标记。');
    this.state.door = 'open';
    this.state.mechanics.smallBoltRetracted = true;
    this.state.mechanics.fenceDropped = this.state.unlock.route === 'password';
    this._record('animation_end', { route: this.state.unlock.route, token });
    this._record('unlock_complete', { route: this.state.unlock.route, token });
    this._notify('open');
    return ok('open', { token });
  }

  close() {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    if (!this.state.panelOpen) return ok('already_closed');
    const now = this._now();
    this.state.panelOpen = false;
    this._syncSuspension('panel_close', now);
    this._record('panel_closed', { door: this.state.door, suspended: this.state.suspended, ...this._suspensionCauses() });
    this._notify('close');
    return ok('closed');
  }

  reopen() {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    if (this.state.panelOpen) return ok('already_open_panel');
    const now = this._now();
    this.state.panelOpen = true;
    this._syncSuspension('panel_reopen', now);
    this._record('panel_reopened', { door: this.state.door, suspended: this.state.suspended, ...this._suspensionCauses() });
    this._notify('reopen');
    return ok('reopened', { token: this.state.unlock?.token });
  }

  /** Browser adapter calls this BEFORE pausing/resuming the deterministic scene. */
  setDocumentHidden(hidden) {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    if (typeof hidden !== 'boolean') return fail('visibility', '页面隐藏状态必须是布尔值。');
    if (hidden === this.state.documentHidden) return ok('visibility_unchanged');
    const now = this._now();
    this.state.documentHidden = hidden;
    const reason = hidden ? 'document_hidden' : 'document_visible';
    this._syncSuspension(reason, now);
    this._record(reason, { door: this.state.door, suspended: this.state.suspended, ...this._suspensionCauses() });
    this._notify('visibility');
    return ok(reason, { suspended: this.state.suspended, token: this.state.unlock?.token });
  }

  _retryCurrent(reason) {
    if (!Number.isSafeInteger(this.state.attempt + 1)) return fail('attempt_limit', '本箱重试次数已到原型计数上限。');
    this._buildRun(this.state.seriesSeed, this._overrides, {
      safeIndex: this.state.safeIndex, attempt: this.state.attempt + 1, reason,
    });
    this._notify('reset');
    return ok(reason, { safeIndex: this.state.safeIndex, attempt: this.state.attempt });
  }

  retryCurrent() {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    return this._retryCurrent('retry_current');
  }

  nextSafe() {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    const safeIndex = this.state.safeIndex + 1;
    if (!Number.isSafeInteger(safeIndex)) return fail('safe_index', '保险箱序列已到原型编号上限。');
    this._buildRun(this.state.seriesSeed, {}, { safeIndex, reason: 'next_safe' });
    this._notify('reset');
    return ok('next_safe', { safeIndex, attempt: 1 });
  }

  reset(seed, overrides, options) {
    if (this.state.destroyed) return fail('destroyed', '原型实例已销毁。');
    if (seed === undefined && overrides === undefined && options === undefined) return this._retryCurrent('reset');
    const { safeIndex = 0 } = options ?? {};
    this._buildRun(seed === undefined ? this.state.seriesSeed : seed, overrides === undefined ? {} : overrides, { safeIndex });
    this._notify('reset');
    return ok('reset');
  }

  destroy() {
    if (this.state.destroyed) return ok('already_destroyed');
    this.close();
    if (this.state.door === 'opening') this._record('animation_cancel', { token: this.state.unlock.token, reason: 'destroy' });
    this.state.destroyed = true;
    this._record('session_destroyed');
    this._notify('destroy');
    this.listeners.clear();
    return ok('destroyed');
  }
}

export default SafeSession;
