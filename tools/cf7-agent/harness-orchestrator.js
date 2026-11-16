'use strict';

const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const path = require('path');
const { execFileSync, spawn } = require('child_process');
const { assertAgentSlot } = require('./player-save-guard');
const { inspectSave } = require('./save-manager');

function findRepoRoot(startDir) {
  let cur = path.resolve(startDir || __dirname);
  for (let i = 0; i < 10; i++) {
    if (fs.existsSync(path.join(cur, 'crossdomain.xml'))) return cur;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  throw new Error('Could not locate project root containing crossdomain.xml');
}

function resolveRuntimeExecutable(projectRoot, runtimeMode = 'auto') {
  const absRoot = path.resolve(projectRoot);

  const buildDescriptor = (deploymentRoot, mode, source) => {
    const bootstrapExe = path.join(deploymentRoot, 'CRAZYFLASHER7MercenaryEmpire.exe');
    const coreExe = path.join(deploymentRoot, 'runtime', 'CRAZYFLASHER7MercenaryEmpire.Core.exe');
    if (!fs.existsSync(bootstrapExe) || !fs.existsSync(coreExe)) return null;
    return {
      deploymentRoot,
      bootstrapExe,
      coreExe,
      verifyFlag: mode === 'isolated_candidate' ? '--verify-runtime-only' : '--verify-only',
      mode,
      source
    };
  };

  const resolveCandidate = () => {
    const pointerPath = path.join(absRoot, 'tmp', 'runtime-dev', 'active.v1.json');
    if (fs.existsSync(pointerPath)) {
      try {
        const ptr = JSON.parse(fs.readFileSync(pointerPath, 'utf8'));
        if (ptr && ptr.candidateRelativePath) {
          const desc = buildDescriptor(
            path.join(absRoot, ptr.candidateRelativePath),
            'isolated_candidate',
            'active.v1.json'
          );
          if (desc) return desc;
        }
      } catch (_) {}
    }

    const candBase = path.join(absRoot, 'tmp', 'runtime-candidates', 'v2');
    if (fs.existsSync(candBase)) {
      const dirs = fs.readdirSync(candBase, { withFileTypes: true })
        .filter((d) => d.isDirectory())
        .map((d) => {
          const full = path.join(candBase, d.name);
          const meta = path.join(full, 'runtime-build-metadata.v2.json');
          const desc = fs.existsSync(meta) ? buildDescriptor(full, 'isolated_candidate', 'latest_v2_candidate') : null;
          return desc ? { desc, mtimeMs: fs.statSync(meta).mtimeMs } : null;
        })
        .filter(Boolean)
        .sort((a, b) => b.mtimeMs - a.mtimeMs);
      if (dirs.length > 0) return dirs[0].desc;
    }
    return null;
  };

  if (runtimeMode === 'formal_runtime') {
    const desc = buildDescriptor(absRoot, 'formal_runtime', 'root');
    if (!desc) {
      throw new Error(`Formal runtime entry not found under ${absRoot}`);
    }
    return desc;
  }

  if (runtimeMode === 'isolated_candidate') {
    const cand = resolveCandidate();
    if (!cand) {
      throw new Error('No built isolated candidate found. Run automation/dev.ps1 -BuildOnly first.');
    }
    return cand;
  }

  // 'auto': prefer active isolated_candidate if available, else formal_runtime.
  const cand = resolveCandidate();
  if (cand) return cand;
  const formal = buildDescriptor(absRoot, 'formal_runtime', 'root_fallback');
  if (formal) return formal;
  throw new Error('Neither isolated_candidate nor formal_runtime executable was found.');
}

function isPidAlive(pid) {
  if (!pid || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err && err.code === 'EPERM';
  }
}

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

class PipeRpcClient {
  constructor(pipePath, sessionEpoch) {
    this.pipePath = pipePath;
    this.sessionEpoch = sessionEpoch;
    this.socket = null;
    this.buffer = '';
    this.nextId = 1;
    this.pending = new Map();
    this.closed = false;
  }

  connect(timeoutMs = 15000) {
    if (this.socket && !this.closed) return Promise.resolve();
    const deadline = Date.now() + timeoutMs;

    const tryOnce = () => new Promise((resolve, reject) => {
      const sock = net.connect(this.pipePath);
      const onErr = (err) => {
        sock.destroy();
        reject(err);
      };
      sock.once('error', onErr);
      sock.once('connect', () => {
        sock.removeListener('error', onErr);
        this.socket = sock;
        this.closed = false;
        sock.setEncoding('utf8');
        sock.on('data', (chunk) => this._onData(chunk));
        sock.on('close', () => this._onClose('pipe_closed'));
        sock.on('error', (err) => this._onClose(err ? err.message : 'pipe_error'));
        resolve();
      });
    });

    return (async () => {
      let lastErr = null;
      while (Date.now() < deadline) {
        try {
          await tryOnce();
          return;
        } catch (err) {
          lastErr = err;
          await sleep(120);
        }
      }
      throw lastErr || new Error(`Timed out connecting to pipe ${this.pipePath}`);
    })();
  }

  _onData(chunk) {
    this.buffer += chunk;
    for (;;) {
      const nl = this.buffer.indexOf('\n');
      if (nl < 0) break;
      const line = this.buffer.slice(0, nl).trim();
      this.buffer = this.buffer.slice(nl + 1);
      if (!line) continue;
      try {
        const msg = JSON.parse(line);
        const id = msg && msg.id !== undefined ? String(msg.id) : null;
        if (id && this.pending.has(id)) {
          const entry = this.pending.get(id);
          this.pending.delete(id);
          clearTimeout(entry.timer);
          entry.resolve(msg);
        }
      } catch (_) {}
    }
  }

  _onClose(reason) {
    this.closed = true;
    this.socket = null;
    for (const [, entry] of this.pending) {
      clearTimeout(entry.timer);
      entry.reject(new Error(`Harness pipe disconnected (${reason})`));
    }
    this.pending.clear();
  }

  request(method, params = {}, timeoutMs = 15000) {
    if (!this.socket || this.closed) {
      return Promise.reject(new Error('Harness pipe client is not connected'));
    }
    const id = 'rpc_' + this.nextId++;
    const payload = JSON.stringify({
      id,
      sessionEpoch: this.sessionEpoch,
      method,
      params: params || {}
    }) + '\n';

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`RPC "${method}" timed out after ${timeoutMs}ms`));
        }
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });
      this.socket.write(payload, 'utf8', (err) => {
        if (err && this.pending.has(id)) {
          this.pending.delete(id);
          clearTimeout(timer);
          reject(err);
        }
      });
    });
  }

  close() {
    this.closed = true;
    if (this.socket) {
      try { this.socket.end(); } catch (_) {}
      try { this.socket.destroy(); } catch (_) {}
      this.socket = null;
    }
    for (const [, entry] of this.pending) {
      clearTimeout(entry.timer);
      entry.reject(new Error('Pipe client closed'));
    }
    this.pending.clear();
  }
}

class HarnessOrchestrator {
  constructor(projectRoot) {
    this.projectRoot = findRepoRoot(projectRoot || __dirname);
    this.activeSession = null;
  }

  _requireSession() {
    if (!this.activeSession || !this.activeSession.client) {
      throw new Error('No active CF7 harness session. Call cf7_session_start first.');
    }
    return this.activeSession;
  }

  async _rpc(method, params, timeoutMs = 15000) {
    const sess = this._requireSession();
    const env = await sess.client.request(method, params, timeoutMs);
    const result = env && env.result ? env.result : {};
    if (env && env.ok === false && result.ok === undefined && result.success === undefined) {
      result.ok = false;
    }
    return result;
  }

  async startSession(options = {}) {
    const runtimeMode = options.runtimeMode || 'auto';
    const slot = options.slot || null;
    if (slot) assertAgentSlot(slot);

    if (this.activeSession) {
      await this.shutdownSession({ forceOnTimeout: true });
    }

    const bin = resolveRuntimeExecutable(this.projectRoot, runtimeMode);
    const sessionEpoch = 'ah_' + Date.now() + '_' + crypto.randomBytes(6).toString('hex');
    const pipeName = 'cf7-ah-' + process.pid + '-' + crypto.randomBytes(4).toString('hex');
    const sessionDir = path.join(this.projectRoot, 'tmp', 'agent-harness', 'sessions', sessionEpoch);
    const configPath = path.join(sessionDir, 'launch.json');
    const stateFilePath = path.join(sessionDir, 'harness-state.json');

    fs.mkdirSync(sessionDir, { recursive: true });
    const cfg = {
      schema: 'cf7-agent-harness.v1',
      projectRoot: this.projectRoot,
      pipeName,
      sessionEpoch,
      stateRoot: sessionDir,
      stateFilePath,
      allowHeadlessFallback: options.allowHeadlessFallback !== false,
      headlessSceneFallbackDelayMs: options.headlessSceneFallbackDelayMs || 750
    };
    fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2), 'utf8');

    // Verify bootstrap manifest & payload integrity before starting Core.exe
    execFileSync(bin.bootstrapExe, [bin.verifyFlag], {
      cwd: bin.deploymentRoot,
      stdio: 'ignore',
      timeout: 15000
    });

    const child = spawn(bin.coreExe, ['--project-root', this.projectRoot, '--agent-harness', configPath], {
      cwd: this.projectRoot,
      detached: true,
      stdio: 'ignore',
      windowsHide: false
    });
    child.unref();

    const bootTimeoutMs = options.bootTimeoutMs || 30000;
    const deadline = Date.now() + bootTimeoutMs;
    let stateDoc = null;
    let coreEarlyExit = null;
    child.once('exit', (code) => {
      if (code !== null) coreEarlyExit = code;
    });

    while (Date.now() < deadline) {
      if (fs.existsSync(stateFilePath)) {
        try {
          stateDoc = JSON.parse(fs.readFileSync(stateFilePath, 'utf8'));
          if (stateDoc && stateDoc.pid && stateDoc.pipeName === pipeName) break;
        } catch (_) {}
      }
      if (coreEarlyExit !== null) {
        throw new Error(`Core exited early with code ${coreEarlyExit} before publishing harness-state.json`);
      }
      await sleep(100);
    }

    if (!stateDoc || !stateDoc.pid) {
      throw new Error(`Timed out waiting for harness-state.json at ${stateFilePath}`);
    }

    const pipePath = '\\\\.\\pipe\\' + pipeName;
    const client = new PipeRpcClient(pipePath, sessionEpoch);
    await client.connect(10000);

    this.activeSession = {
      sessionEpoch,
      pipeName,
      sessionDir,
      stateFilePath,
      corePid: stateDoc.pid,
      runtimeMode: bin.mode,
      executable: bin.coreExe,
      runtimeIdentity: stateDoc.runtimeIdentity || null,
      slot: null,
      client
    };

    const ping = await this._rpc('session.status', {}, 5000);
    let enterResult = null;
    if (slot) {
      const enterTimeout = options.enterTimeoutMs || 45000;
      enterResult = await this._rpc(
        'session.enter_slot',
        { slot, fresh: !!options.fresh, timeoutMs: enterTimeout },
        enterTimeout + 5000
      );
      if (!enterResult || enterResult.ok !== true) {
        return {
          ok: false,
          error: (enterResult && enterResult.error) || 'enter_slot_failed',
          sessionEpoch,
          corePid: stateDoc.pid,
          runtimeMode: bin.mode,
          executable: bin.coreExe,
          runtimeIdentity: stateDoc.runtimeIdentity || null,
          enterResult
        };
      }
      this.activeSession.slot = slot;
    }

    return {
      ok: true,
      sessionEpoch,
      corePid: stateDoc.pid,
      pipeName,
      runtimeMode: bin.mode,
      executable: bin.coreExe,
      runtimeIdentity: stateDoc.runtimeIdentity || null,
      slot: this.activeSession.slot,
      status: enterResult ? enterResult.status : ping.launch,
      world: enterResult ? enterResult.world : null
    };
  }

  async status() {
    if (!this.activeSession) {
      return { ok: true, active: false };
    }
    const alive = isPidAlive(this.activeSession.corePid);
    if (!alive) {
      this.activeSession.client.close();
      this.activeSession = null;
      return { ok: true, active: false, note: 'process_exited' };
    }
    const res = await this._rpc('session.status', {}, 5000);
    return Object.assign({ active: true, slot: this.activeSession.slot }, res);
  }

  async saveAndExit(options = {}) {
    if (!this.activeSession) {
      return { ok: true, alreadyExited: true };
    }
    const sess = this.activeSession;
    const timeoutMs = options.timeoutMs || 15000;
    let res;
    try {
      res = await this._rpc('session.save_and_exit', options, timeoutMs);
    } finally {
      sess.client.close();
      this.activeSession = null;
    }

    const exitDeadline = Date.now() + 12000;
    while (Date.now() < exitDeadline && isPidAlive(sess.corePid)) {
      await sleep(100);
    }
    const exitedCleanly = !isPidAlive(sess.corePid);

    let saveSummary = null;
    if (sess.slot) {
      try {
        saveSummary = inspectSave({ projectRoot: this.projectRoot, slot: sess.slot }).summary;
      } catch (_) {}
    }

    return {
      ok: !!(res && res.ok === true && exitedCleanly),
      exitedCleanly,
      corePid: sess.corePid,
      slot: sess.slot,
      saveAndExitResult: res,
      saveSummary
    };
  }

  async shutdownSession(options = {}) {
    if (!this.activeSession) return { ok: true, alreadyExited: true };
    const sess = this.activeSession;
    try {
      await this._rpc('session.shutdown', {}, 5000);
    } catch (_) {}
    sess.client.close();
    this.activeSession = null;

    const deadline = Date.now() + 8000;
    while (Date.now() < deadline && isPidAlive(sess.corePid)) {
      await sleep(100);
    }
    if (isPidAlive(sess.corePid) && options.forceOnTimeout !== false) {
      try { process.kill(sess.corePid, 'SIGKILL'); } catch (_) {}
    }
    return { ok: !isPidAlive(sess.corePid), corePid: sess.corePid };
  }

  async restart(options = {}) {
    const prevSlot = options.slot || (this.activeSession && this.activeSession.slot);
    const prevMode = options.runtimeMode || (this.activeSession && this.activeSession.runtimeMode) || 'auto';
    if (!prevSlot) {
      throw new Error('Cannot restart: no slot specified and no active session slot.');
    }
    let saveExitRes = null;
    if (this.activeSession) {
      saveExitRes = await this.saveAndExit({ timeoutMs: options.exitTimeoutMs || 15000 });
      await sleep(300);
    }
    const startRes = await this.startSession({
      slot: prevSlot,
      runtimeMode: prevMode,
      fresh: !!options.fresh,
      allowHeadlessFallback: options.allowHeadlessFallback,
      bootTimeoutMs: options.bootTimeoutMs,
      enterTimeoutMs: options.enterTimeoutMs
    });
    return {
      ok: !!startRes.ok,
      saveAndExit: saveExitRes,
      started: startRes
    };
  }

  async panelOpen(options) {
    return this._rpc('panel.open', options, (options && options.timeoutMs ? options.timeoutMs : 8000) + 3000);
  }

  async panelClose(options = {}) {
    return this._rpc('panel.close', options, (options && options.timeoutMs ? options.timeoutMs : 5000) + 3000);
  }

  async webSnapshot(options = {}) {
    return this._rpc('web.snapshot', options, 10000);
  }

  async webAct(options) {
    return this._rpc('web.act', options, 10000);
  }

  async webScreenshot(options = {}) {
    return this._rpc('web.screenshot', options, 10000);
  }

  async worldSnapshot(options = {}) {
    return this._rpc('world.snapshot', options, 8000);
  }

  async worldAct(options) {
    const opts = options && typeof options === 'object' ? Object.assign({}, options) : {};
    if (opts.act === 'move_to') {
      if (opts.maxFrames === undefined && typeof opts.timeoutFrames === 'number') {
        opts.maxFrames = opts.timeoutFrames;
      }
      if ((typeof opts.x !== 'number' || typeof opts.z !== 'number')
          && (typeof opts.dx === 'number' || typeof opts.dz === 'number')) {
        const snap = await this.worldSnapshot({});
        const hero = snap && snap.data && snap.data.hero;
        if (!hero || hero.present !== true) {
          return { ok: false, error: 'hero_missing_for_relative_move' };
        }
        if (typeof opts.x !== 'number') opts.x = Number(hero.x) + Number(opts.dx || 0);
        if (typeof opts.z !== 'number') opts.z = Number(hero.z) + Number(opts.dz || 0);
      }
    }
    return this._rpc('world.act', opts, 10000);
  }

  async hitLedger(options = {}) {
    return this._rpc('combat.hit_ledger', options, 8000);
  }

  async waitFor(options = {}) {
    const t = options && options.timeoutMs ? options.timeoutMs : 10000;
    return this._rpc('events.wait_for', options, t + 4000);
  }

  async logsQuery(options = {}) {
    return this._rpc('logs.query', options, 8000);
  }
}

module.exports = {
  findRepoRoot,
  resolveRuntimeExecutable,
  PipeRpcClient,
  HarnessOrchestrator
};
