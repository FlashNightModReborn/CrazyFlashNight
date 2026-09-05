import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const artifactRoot = resolve(root, 'artifacts', 'browser-qa');
const profileDir = mkdtempSync(resolve(tmpdir(), 'cf7-warlord-edge-'));
const viewports = [
  { width: 1024, height: 576 },
  { width: 1366, height: 768 },
  { width: 1920, height: 1080 },
];

function delay(milliseconds) {
  return new Promise((complete) => setTimeout(complete, milliseconds));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function allocatePort() {
  return new Promise((complete, reject) => {
    const listener = createServer();
    listener.once('error', reject);
    listener.listen(0, '127.0.0.1', () => {
      const address = listener.address();
      if (!address || typeof address === 'string') {
        listener.close();
        reject(new Error('Unable to allocate a loopback port.'));
        return;
      }
      listener.close((error) => error ? reject(error) : complete(address.port));
    });
  });
}

async function waitForHttp(url, timeoutMs = 15_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { cache: 'no-store' });
      if (response.ok) return response;
      lastError = new Error(`${response.status} ${response.statusText}`);
    } catch (error) {
      lastError = error;
    }
    await delay(100);
  }
  throw new Error(`Timed out waiting for ${url}: ${String(lastError)}`);
}

function resolveEdgePath() {
  const candidates = [
    process.env.CF7_EDGE_PATH,
    process.env.EDGE_PATH,
    process.env['ProgramFiles(x86)'] && resolve(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'),
    process.env.ProgramFiles && resolve(process.env.ProgramFiles, 'Microsoft/Edge/Application/msedge.exe'),
    process.env.LOCALAPPDATA && resolve(process.env.LOCALAPPDATA, 'Microsoft/Edge/Application/msedge.exe'),
  ].filter(Boolean);
  const path = candidates.find((candidate) => existsSync(candidate));
  if (!path) throw new Error(`Microsoft Edge was not found. Checked: ${candidates.join(', ')}`);
  return path;
}

class CdpClient {
  constructor(url) {
    this.url = url;
    this.nextId = 0;
    this.pending = new Map();
    this.listeners = new Map();
  }

  async connect() {
    assert(typeof WebSocket === 'function', 'Node WebSocket is unavailable; run with --experimental-websocket on Node 20.');
    this.socket = new WebSocket(this.url);
    await new Promise((complete, reject) => {
      const timer = setTimeout(() => reject(new Error(`Timed out opening CDP socket ${this.url}`)), 10_000);
      this.socket.addEventListener('open', () => {
        clearTimeout(timer);
        complete();
      }, { once: true });
      this.socket.addEventListener('error', (event) => {
        clearTimeout(timer);
        reject(new Error(`CDP socket error: ${event.type}`));
      }, { once: true });
    });
    this.socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (typeof message.id === 'number') {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(`${pending.method}: ${message.error.message}`));
        else pending.resolve(message.result ?? {});
        return;
      }
      for (const listener of this.listeners.get(message.method) ?? []) listener(message.params ?? {});
    });
    this.socket.addEventListener('close', () => {
      for (const pending of this.pending.values()) pending.reject(new Error('CDP socket closed.'));
      this.pending.clear();
    });
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) ?? [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  send(method, params = {}) {
    const id = ++this.nextId;
    return new Promise((complete, reject) => {
      this.pending.set(id, { method, resolve: complete, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.socket?.close();
  }
}

async function terminate(child) {
  if (!child?.pid || child.exitCode !== null) return { pid: child?.pid ?? null, stopped: true, forced: false };
  child.kill('SIGTERM');
  await Promise.race([
    new Promise((complete) => child.once('exit', complete)),
    delay(2_000),
  ]);
  if (child.exitCode !== null) return { pid: child.pid, stopped: true, forced: false };
  if (process.platform === 'win32') {
    const result = spawnSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], {
      windowsHide: true,
      encoding: 'utf8',
    });
    await delay(100);
    return {
      pid: child.pid,
      stopped: child.exitCode !== null || result.status === 0 || result.status === 128,
      forceAttempted: true,
      forced: result.status === 0,
      taskkillStatus: result.status,
    };
  }
  child.kill('SIGKILL');
  await Promise.race([new Promise((complete) => child.once('exit', complete)), delay(1_000)]);
  return { pid: child.pid, stopped: child.exitCode !== null, forced: true };
}

mkdirSync(artifactRoot, { recursive: true });
const appPort = await allocatePort();
const debugPort = await allocatePort();
const appOrigin = `http://127.0.0.1:${appPort}`;
const harnessUrl = `${appOrigin}/modules/minigames/warlord/dev/harness.html?qa=1`;
const edgePath = resolveEdgePath();
const startedAt = new Date().toISOString();
let server;
let browser;
let cdp;
let runError;
const serverOutput = [];
const browserOutput = [];
const summary = {
  schemaVersion: 1,
  evidenceTier: 'ordinary_edge_cdp_harness',
  explicitlyNot: ['WebView2', 'Launcher', 'deployment', 'human_visual_acceptance'],
  runner: 'custom-edge-cdp',
  startedAt,
  edgePath,
  harnessUrl,
  qa: null,
  commandView: null,
  productionView: null,
  productionExactView: null,
  tacticalView: null,
  tacticalMaxView: null,
  themePreview: null,
  viewports: [],
  network: { requests: [], responses: [], failures: [], externalRequests: [] },
  consoleErrors: [],
  runtimeExceptions: [],
  cleanup: {},
  passed: false,
};

try {
  server = spawn(process.execPath, [resolve(root, 'dev/server.mjs'), String(appPort)], {
    cwd: root,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  server.stdout.on('data', (chunk) => serverOutput.push(String(chunk)));
  server.stderr.on('data', (chunk) => serverOutput.push(String(chunk)));
  await waitForHttp(harnessUrl);

  browser = spawn(edgePath, [
    '--headless=new',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-default-apps',
    '--disable-extensions',
    '--disable-features=Translate,MediaRouter,OptimizationHints',
    '--disable-sync',
    '--metrics-recording-only',
    '--no-default-browser-check',
    '--no-first-run',
    '--use-angle=swiftshader',
    '--window-size=1024,576',
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${profileDir}`,
    'about:blank',
  ], {
    cwd: root,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  browser.stdout.on('data', (chunk) => browserOutput.push(String(chunk)));
  browser.stderr.on('data', (chunk) => browserOutput.push(String(chunk)));

  const versionResponse = await waitForHttp(`http://127.0.0.1:${debugPort}/json/version`);
  const versionInfo = await versionResponse.json();
  summary.browserVersion = versionInfo.Browser;
  const targetsResponse = await waitForHttp(`http://127.0.0.1:${debugPort}/json/list`);
  const targets = await targetsResponse.json();
  const pageTarget = targets.find((target) => target.type === 'page' && target.url === 'about:blank')
    ?? targets.find((target) => target.type === 'page');
  assert(pageTarget?.webSocketDebuggerUrl, 'Edge did not expose a page CDP target.');

  cdp = new CdpClient(pageTarget.webSocketDebuggerUrl);
  await cdp.connect();
  await Promise.all([
    cdp.send('Page.enable'),
    cdp.send('Runtime.enable'),
    cdp.send('Network.enable'),
    cdp.send('Log.enable'),
  ]);
  cdp.on('Network.requestWillBeSent', ({ request }) => {
    if (!request?.url) return;
    summary.network.requests.push({ method: request.method, url: request.url });
    if (!request.url.startsWith(appOrigin) && !/^(data|blob|devtools):/.test(request.url)) {
      summary.network.externalRequests.push(request.url);
    }
  });
  cdp.on('Network.responseReceived', ({ response }) => {
    if (response?.url) summary.network.responses.push({ status: response.status, url: response.url });
  });
  cdp.on('Network.loadingFailed', ({ errorText, canceled, blockedReason, requestId }) => {
    summary.network.failures.push({ requestId, errorText, canceled: Boolean(canceled), blockedReason: blockedReason ?? null });
  });
  cdp.on('Runtime.exceptionThrown', ({ exceptionDetails }) => {
    summary.runtimeExceptions.push({
      text: exceptionDetails?.text ?? 'Unknown runtime exception',
      description: exceptionDetails?.exception?.description ?? null,
      url: exceptionDetails?.url ?? null,
      lineNumber: exceptionDetails?.lineNumber ?? null,
    });
  });
  cdp.on('Log.entryAdded', ({ entry }) => {
    if (entry?.level === 'error') summary.consoleErrors.push({ source: entry.source, text: entry.text, url: entry.url ?? null });
  });
  cdp.on('Runtime.consoleAPICalled', ({ type, args }) => {
    if (type !== 'error' && type !== 'assert') return;
    summary.consoleErrors.push({
      source: `console.${type}`,
      text: (args ?? []).map((argument) => argument.value ?? argument.description ?? '').join(' '),
      url: null,
    });
  });

  const evaluate = async (expression) => {
    const result = await cdp.send('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: true,
    });
    if (result.exceptionDetails) {
      const description = result.exceptionDetails.exception?.description ?? result.exceptionDetails.text;
      throw new Error(`Browser evaluation failed: ${description}`);
    }
    return result.result?.value;
  };

  // `--window-size` still leaves browser-chrome-dependent content bounds in
  // some headless Edge builds. Fix the CSS viewport before navigation so the
  // in-page geometry and hit-testing gates truly run at the declared 1024x576.
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1024,
    height: 576,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await cdp.send('Page.navigate', { url: harnessUrl });
  // The 29-check contract includes stage-v1 terminal/close generation, encounter
  // distance guidance, TaskGroup representative tokens, and bounded AS2 rejection recovery alongside camera/full-turn paths. Keep a
  // bounded margin above the observed ~34 s baseline plus the 30-cycle modal
  // lifecycle stress. Software-rendered/headless WebGL can spend close to two
  // minutes rebuilding and retiring those contexts, so the runner deadline
  // must not race a still-progressing final cycle.
  const qaDeadline = Date.now() + 180_000;
  let qaState = 'pending';
  while (Date.now() < qaDeadline) {
    qaState = await evaluate('document.documentElement.getAttribute("data-warlord-qa") || "pending"');
    if (qaState === 'passed' || qaState === 'failed') break;
    await delay(100);
  }
  if (qaState === 'pending') {
    const progress = await evaluate('window.__WARLORD_QA_PROGRESS__ || null');
    throw new Error(`Harness QA did not reach a terminal state; progress=${JSON.stringify(progress)}.`);
  }
  summary.qa = await evaluate('window.__WARLORD_QA_RESULTS__ || null');
  assert(Array.isArray(summary.qa), 'Harness did not expose QA results.');
  assert(qaState === 'passed', `Harness QA ended in ${qaState}.`);
  assert(summary.qa.length === 29 && summary.qa.every((check) => check.pass === true), 'Harness QA results contain a failure or the 29-check contract drifted.');
  await evaluate('document.getElementById("qa-results").hidden = true');

  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1024,
    height: 576,
    deviceScaleFactor: 1,
    mobile: false,
  });
  const commandState = await evaluate(`(async () => {
    const waitFor = async (check, timeoutMs = 12000) => {
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const value = check();
        if (value) return value;
        await new Promise((complete) => setTimeout(complete, 40));
      }
      throw new Error('command screenshot setup timed out');
    };
    const stage = document.getElementById('harness-stage');
    stage.style.width = '1024px';
    stage.style.height = '576px';
    window.dispatchEvent(new Event('resize'));
    window.__warlordHarness.close();
    await new Promise((complete) => setTimeout(complete, 30));
    window.__warlordHarness.open({ seed: 'qa-command-screenshot' });
    const root = await waitFor(() => document.querySelector('.warlord-scale-shell[data-ready="true"]'));
    for (let index = 0; index < 2; index += 1) {
      const input = document.querySelector('.warlord-piece input[data-field="piece"]:not(:disabled):not(:checked)');
      if (!input) break;
      input.checked = true;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }
    await new Promise((complete) => setTimeout(complete, 120));
    const host = document.querySelector('.warlord-scene-host');
    const intent = document.querySelector('.warlord-command-intent:not([hidden])');
    return {
      selectedNode: root.getAttribute('data-selected-node'),
      selectedPieceCount: Number(root.getAttribute('data-selected-piece-count')),
      legalSceneTargets: (host?.getAttribute('data-legal-command-targets') || '').split(',').filter(Boolean),
      legalNodeCards: document.querySelectorAll('.warlord-node-card[data-command-state="move"], .warlord-node-card[data-command-state="attack"], .warlord-node-card[data-command-state="partial"]').length,
      invalidNodeCards: document.querySelectorAll('.warlord-node-card[data-command-state="invalid"]').length,
      intentCopy: intent?.textContent?.replace(/\\s+/g, ' ').trim() || null,
    };
  })()`);
  assert(commandState.selectedPieceCount === 2, 'Command screenshot did not select two pieces.');
  assert(commandState.legalSceneTargets.length > 0 && commandState.legalNodeCards > 0, 'Command screenshot has no legal highlighted target.');
  assert(commandState.intentCopy, 'Command screenshot has no compact command intent.');
  const commandScreenshotName = 'warlord-1024x576-command.png';
  const commandCapture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, commandScreenshotName), Buffer.from(commandCapture.data, 'base64'));
  summary.commandView = { ...commandState, screenshot: commandScreenshotName };

  const productionState = await evaluate(`(async () => {
    const waitFor = async (check, timeoutMs = 12000) => {
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        const value = check();
        if (value) return value;
        await new Promise((complete) => setTimeout(complete, 40));
      }
      throw new Error('production screenshot setup timed out');
    };
    const stage = document.getElementById('harness-stage');
    stage.style.width = '1024px';
    stage.style.height = '576px';
    window.dispatchEvent(new Event('resize'));
    window.__warlordHarness.close();
    await new Promise((complete) => setTimeout(complete, 40));
    window.__warlordHarness.open({ preset: 'all-units', seed: 'qa-production-screenshot' });
    await waitFor(() => document.querySelector('.warlord-scale-shell[data-ready="true"]'));
    (await waitFor(() => document.querySelector('[data-action="end-action"]:not(:disabled)'))).click();
    // 蓝方 AI 回合已改为 ≥460ms 逐条重放 + 战斗排队 4× 播放，等待窗口随节奏放宽
    await waitFor(() => document.querySelector('.warlord-scale-shell[data-phase="SETTLEMENT_PLANNING"]'), 30000);
    const skip = document.querySelector('[data-action="battle-skip"]');
    if (skip) {
      skip.click();
      await new Promise((complete) => setTimeout(complete, 30));
      document.querySelector('[data-action="battle-close"]:not(:disabled)')?.click();
    }
    for (const cardId of ['12', '13', '14', '15']) {
      const production = await waitFor(() => document.querySelector('[data-action="production"][data-card="' + cardId + '"]:not(:disabled)'));
      production.click();
      await new Promise((complete) => setTimeout(complete, 45));
    }
    await new Promise((complete) => setTimeout(complete, 160));
    const console = document.querySelector('.warlord-production-console');
    return {
      phase: document.querySelector('.warlord-scale-shell')?.getAttribute('data-phase') || null,
      mode: console?.getAttribute('data-mode') || null,
      orderCount: Number(console?.getAttribute('data-order-count')),
      recommendedNode: console?.getAttribute('data-recommended-node') || null,
      recommendedSlot: console?.getAttribute('data-recommended-slot') || null,
      queuedLanes: document.querySelectorAll('.warlord-production-lane[data-queue-length="1"]').length,
      networkOrders: Number(document.querySelector('.warlord-production-network')?.getAttribute('data-total-orders')),
      networkPortraits: document.querySelectorAll('.warlord-production-network-order [data-warlord-portrait]').length,
      legacySlotRadios: document.querySelectorAll('[data-field="slot"]').length,
    };
  })()`);
  assert(productionState.phase === 'SETTLEMENT_PLANNING', 'Production screenshot is not in planning phase.');
  assert(productionState.mode === 'auto' && productionState.orderCount === 4, 'Automatic production state was not projected.');
  assert(productionState.queuedLanes >= 1 && productionState.legacySlotRadios === 0, 'Production lane projection or legacy-control removal failed.');
  assert(productionState.networkOrders === 4 && productionState.networkPortraits === 4, 'Production network portrait strip was not projected.');
  const productionScreenshotName = 'warlord-1024x576-production.png';
  const productionCapture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, productionScreenshotName), Buffer.from(productionCapture.data, 'base64'));
  summary.productionView = { ...productionState, screenshot: productionScreenshotName };
  const productionExactState = await evaluate(`(() => {
    document.querySelector('.warlord-production-console [data-action="toggle-production-mode"]')?.click();
    const lanes = document.querySelectorAll('.warlord-production-console [data-action="choose-production-slot"]');
    lanes[1]?.click();
    const console = document.querySelector('.warlord-production-console');
    const selected = console?.querySelector('[data-action="choose-production-slot"][aria-pressed="true"]');
    return {
      mode: console?.getAttribute('data-mode') || null,
      selectedSlot: selected?.getAttribute('data-slot') || null,
      selectedState: selected?.getAttribute('data-state') || null,
    };
  })()`);
  assert(productionExactState.mode === 'exact' && productionExactState.selectedSlot, 'Exact production lane did not become selected.');
  await delay(100);
  const productionExactScreenshotName = 'warlord-1024x576-production-exact.png';
  const productionExactCapture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, productionExactScreenshotName), Buffer.from(productionExactCapture.data, 'base64'));
  summary.productionExactView = { ...productionExactState, screenshot: productionExactScreenshotName };
  await evaluate(`(async () => {
    window.__warlordHarness.close();
    await new Promise((complete) => setTimeout(complete, 30));
    window.__warlordHarness.open();
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      if (document.querySelector('.warlord-scale-shell[data-ready="true"]')) return true;
      await new Promise((complete) => setTimeout(complete, 40));
    }
    throw new Error('default harness restore timed out');
  })()`);
  await delay(120);

  const tacticalState = await evaluate(`(async () => {
    const stage = document.getElementById('harness-stage');
    stage.style.width = '1024px';
    stage.style.height = '576px';
    window.dispatchEvent(new Event('resize'));
    document.querySelector('[data-action="select-node"][data-node="R-HQ"]')?.click();
    document.querySelector('[data-action="camera-focus"]')?.click();
    // 定位运镜 240ms 过渡 + 帧饥饿兜底计时器 300ms 收敛窗，等其落位后再采样
    await new Promise((complete) => setTimeout(complete, 450));
    const host = document.querySelector('.warlord-scene-host');
    const hud = document.querySelector('.warlord-camera-hud');
    return {
      zoomPercent: Number(host?.getAttribute('data-camera-zoom')),
      detailTier: host?.getAttribute('data-camera-detail') || null,
      selectedNode: document.querySelector('.warlord-scale-shell')?.getAttribute('data-selected-node') || null,
      cameraExpanded: hud?.getAttribute('data-expanded') || null,
      pieceVisualStyle: host?.getAttribute('data-piece-visual-style') || null,
      pieceScalePolicy: host?.getAttribute('data-piece-scale-policy') || null,
      pieceScale: Number(host?.getAttribute('data-piece-scale')),
      pieceScreenGrowth: Number(host?.getAttribute('data-piece-screen-growth')),
      visibleCameraControls: Array.from(hud?.querySelectorAll('.warlord-camera-controls button') || []).filter((button) => {
        const style = getComputedStyle(button);
        return style.visibility !== 'hidden' && button.getBoundingClientRect().width > 1;
      }).length,
    };
  })()`);
  assert(tacticalState.zoomPercent >= 200, 'Dedicated tactical screenshot did not reach tactical magnification.');
  assert(tacticalState.cameraExpanded === 'true' && tacticalState.visibleCameraControls === 4, 'Tactical activity screenshot did not expose camera details.');
  assert(tacticalState.pieceVisualStyle === 'tactical-badge-v1'
    && tacticalState.pieceScalePolicy === 'progressive-art-detail-v2'
    && tacticalState.pieceScreenGrowth >= 1.75
    && tacticalState.pieceScreenGrowth <= 1.78, 'Tactical badge art-growth contract failed.');
  const tacticalScreenshotName = 'warlord-1024x576-tactical.png';
  const tacticalCapture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, tacticalScreenshotName), Buffer.from(tacticalCapture.data, 'base64'));
  summary.tacticalView = { ...tacticalState, screenshot: tacticalScreenshotName };

  const tacticalMaxState = await evaluate(`(async () => {
    const zoomIn = document.querySelector('[data-action="camera-zoom-in"]');
    for (let index = 0; index < 6; index += 1) {
      zoomIn?.click();
      await new Promise((complete) => setTimeout(complete, 290));
    }
    document.querySelector('[data-action="camera-focus"]')?.click();
    await new Promise((complete) => setTimeout(complete, 450));
    const host = document.querySelector('.warlord-scene-host');
    return {
      zoomPercent: Number(host?.getAttribute('data-camera-zoom')),
      selectedNode: document.querySelector('.warlord-scale-shell')?.getAttribute('data-selected-node') || null,
      cameraX: Number(host?.getAttribute('data-camera-x')),
      cameraZ: Number(host?.getAttribute('data-camera-z')),
      pieceScalePolicy: host?.getAttribute('data-piece-scale-policy') || null,
      pieceScale: Number(host?.getAttribute('data-piece-scale')),
      pieceScreenGrowth: Number(host?.getAttribute('data-piece-screen-growth')),
    };
  })()`);
  assert(tacticalMaxState.zoomPercent >= 600 && tacticalMaxState.selectedNode === 'R-HQ',
    'Maximum tactical screenshot did not reach the close-inspection range.');
  assert(tacticalMaxState.pieceScalePolicy === 'progressive-art-detail-v2'
    && tacticalMaxState.pieceScale >= 0.54
    && tacticalMaxState.pieceScale <= 0.55
    && tacticalMaxState.pieceScreenGrowth >= 3.39
    && tacticalMaxState.pieceScreenGrowth < 3.401,
  'Maximum tactical badge is not large enough for portrait inspection.');
  const tacticalMaxScreenshotName = 'warlord-1024x576-tactical-max.png';
  const tacticalMaxCapture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, tacticalMaxScreenshotName), Buffer.from(tacticalMaxCapture.data, 'base64'));
  summary.tacticalMaxView = { ...tacticalMaxState, screenshot: tacticalMaxScreenshotName };
  await evaluate(`document.querySelector('[data-action="select-node"][data-node="R-HQ"]')?.click()`);
  await evaluate('document.querySelector(\'[data-action="camera-fit"]\')?.click()');
  await delay(1650);

  for (const viewport of viewports) {
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: viewport.width,
      height: viewport.height,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await evaluate(`(() => {
      const stage = document.getElementById('harness-stage');
      stage.style.width = '${viewport.width}px';
      stage.style.height = '${viewport.height}px';
      window.dispatchEvent(new Event('resize'));
    })()`);
    await delay(300);
    const layout = await evaluate(`(() => {
      const stage = document.getElementById('harness-stage').getBoundingClientRect();
      const root = document.querySelector('.warlord-app').getBoundingClientRect();
      const shell = document.querySelector('.warlord-scale-shell');
      const cameraHud = document.querySelector('.warlord-camera-hud');
      const nodeStrip = document.querySelector('.warlord-node-strip');
      return {
        viewport: { width: innerWidth, height: innerHeight },
        stage: { width: stage.width, height: stage.height },
        root: { left: root.left, top: root.top, right: root.right, bottom: root.bottom },
        panelScale: shell?.style?.getPropertyValue('--panel-scale') || null,
        documentOverflow: document.documentElement.scrollWidth > innerWidth || document.documentElement.scrollHeight > innerHeight,
        visibleCanvas: Boolean(document.querySelector('canvas')),
        fallbackVisible: Boolean(document.querySelector('.warlord-fallback:not([hidden])')),
        cameraHud: {
          expanded: cameraHud?.getAttribute('data-expanded') || null,
          width: Number.parseFloat(getComputedStyle(cameraHud).width),
          visibleControls: Array.from(cameraHud?.querySelectorAll('.warlord-camera-controls button') || []).filter((button) => {
            const style = getComputedStyle(button);
            return style.visibility !== 'hidden' && button.getBoundingClientRect().width > 1;
          }).length,
        },
        nodeStripHeight: Number.parseFloat(getComputedStyle(nodeStrip).height),
      };
    })()`);
    assert(layout.viewport.width === viewport.width && layout.viewport.height === viewport.height, `CDP viewport mismatch at ${viewport.width}x${viewport.height}.`);
    assert(layout.documentOverflow === false, `Document overflow at ${viewport.width}x${viewport.height}.`);
    assert(layout.visibleCanvas || layout.fallbackVisible, `Neither WebGL canvas nor fallback is visible at ${viewport.width}x${viewport.height}.`);
    assert(layout.cameraHud.expanded === 'false' && layout.cameraHud.width <= 108.5 && layout.cameraHud.visibleControls === 2, `Camera HUD did not stay compact at ${viewport.width}x${viewport.height}.`);
    assert(layout.nodeStripHeight <= 48.5, `Node strip did not stay compact at ${viewport.width}x${viewport.height}.`);
    const screenshotName = `warlord-${viewport.width}x${viewport.height}.png`;
    const screenshotPath = resolve(artifactRoot, screenshotName);
    const capture = await cdp.send('Page.captureScreenshot', {
      format: 'png',
      fromSurface: true,
      captureBeyondViewport: false,
    });
    writeFileSync(screenshotPath, Buffer.from(capture.data, 'base64'));
    summary.viewports.push({ ...viewport, screenshot: screenshotName, layout });
  }

  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1024,
    height: 576,
    deviceScaleFactor: 1,
    mobile: false,
  });
  const themeState = await evaluate(`(async () => {
    const stage = document.getElementById('harness-stage');
    stage.style.width = '1024px';
    stage.style.height = '576px';
    window.dispatchEvent(new Event('resize'));
    window.__warlordHarness.rebind({ mapTheme: 'tundra', seed: 'warlord-tundra-preview' });
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      const host = document.querySelector('.warlord-scene-host[data-map-theme="tundra"]');
      if (document.querySelector('.warlord-app[data-map-theme="tundra"]') && host?.querySelector('canvas')) {
        document.querySelector('[data-action="camera-fit"]')?.click();
        await new Promise((complete) => setTimeout(complete, 1650));
        return {
          mapTheme: host.getAttribute('data-map-theme'),
          nodeKinds: host.getAttribute('data-node-kinds'),
          landmarkCount: Number(host.getAttribute('data-landmark-count')),
        };
      }
      await new Promise((complete) => setTimeout(complete, 40));
    }
    throw new Error('tundra theme preview did not become ready');
  })()`);
  assert(themeState.mapTheme === 'tundra' && themeState.landmarkCount === 9, 'Theme preview contract is incomplete.');
  const themeScreenshotName = 'warlord-1024x576-tundra.png';
  const themeCapture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, themeScreenshotName), Buffer.from(themeCapture.data, 'base64'));
  summary.themePreview = { ...themeState, screenshot: themeScreenshotName };
  await evaluate(`window.__warlordHarness.rebind({ mapTheme: 'desert', seed: 'warlord-theme-restore' })`);
  await delay(180);

  await delay(300);
  assert(summary.consoleErrors.length === 0, `Browser console errors: ${JSON.stringify(summary.consoleErrors)}`);
  assert(summary.runtimeExceptions.length === 0, `Runtime exceptions: ${JSON.stringify(summary.runtimeExceptions)}`);
  assert(summary.network.failures.filter((failure) => !failure.canceled).length === 0, `Network failures: ${JSON.stringify(summary.network.failures)}`);
  assert(summary.network.externalRequests.length === 0, `Unexpected external requests: ${summary.network.externalRequests.join(', ')}`);
  summary.passed = true;
} catch (error) {
  runError = error;
  summary.error = error instanceof Error ? { message: error.message, stack: error.stack } : { message: String(error) };
} finally {
  cdp?.close();
  summary.cleanup.browser = await terminate(browser);
  summary.cleanup.server = await terminate(server);
  try {
    rmSync(profileDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
    summary.cleanup.profileRemoved = !existsSync(profileDir);
  } catch (error) {
    summary.cleanup.profileRemoved = false;
    summary.cleanup.profileError = error instanceof Error ? error.message : String(error);
  }
  summary.finishedAt = new Date().toISOString();
  summary.serverOutput = serverOutput.join('').trim();
  summary.browserOutput = browserOutput.join('').trim();
  const summaryPath = resolve(artifactRoot, 'summary.json');
  writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(`Edge/CDP QA: ${summary.passed ? 'PASS' : 'FAIL'}`);
  console.log(`Summary: ${summaryPath}`);
  if (summary.commandView) console.log(`Screenshot command: ${resolve(artifactRoot, summary.commandView.screenshot)}`);
  if (summary.tacticalView) console.log(`Screenshot tactical: ${resolve(artifactRoot, summary.tacticalView.screenshot)}`);
  if (summary.tacticalMaxView) console.log(`Screenshot tactical max: ${resolve(artifactRoot, summary.tacticalMaxView.screenshot)}`);
  if (summary.productionView) console.log(`Screenshot production: ${resolve(artifactRoot, summary.productionView.screenshot)}`);
  if (summary.productionExactView) console.log(`Screenshot production exact: ${resolve(artifactRoot, summary.productionExactView.screenshot)}`);
  if (summary.themePreview) console.log(`Screenshot theme preview: ${resolve(artifactRoot, summary.themePreview.screenshot)}`);
  for (const viewport of summary.viewports) console.log(`Screenshot ${viewport.width}x${viewport.height}: ${resolve(artifactRoot, viewport.screenshot)}`);
}

if (runError) throw runError;
