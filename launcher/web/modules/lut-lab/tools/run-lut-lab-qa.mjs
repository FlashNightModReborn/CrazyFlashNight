/**
 * LUT 实验室 浏览器 QA runner（Edge headless + CDP，参考 warlord run-browser-qa.mjs）。
 *
 * 用法：node --experimental-websocket tools/run-lut-lab-qa.mjs   （Node 20 需要该 flag）
 * 流程：起 dev/server.mjs → Edge(swiftshader) 打开 harness?qa=1&bridge=mock&vhost=local →
 * 等页面内 QA 终态（含 GPU vs CPU 三线性逐像素对照与 identity 恒等断言）→
 * 截图（降级态 / 对比网格 / 放大检视）→ 报告落 tmp/lut-lab/qa/。
 * 证据边界：普通 Edge + 软件 WebGL，不代签 WebView2 / Launcher / 真实桥命令。
 */
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolsDir = dirname(fileURLToPath(import.meta.url));
const moduleDir = resolve(toolsDir, '..');
const repoRoot = resolve(moduleDir, '..', '..', '..', '..');
const artifactRoot = resolve(repoRoot, 'tmp', 'lut-lab', 'qa');
const profileDir = mkdtempSync(resolve(tmpdir(), 'cf7-lutlab-edge-'));

function delay(ms) { return new Promise((complete) => setTimeout(complete, ms)); }
function assert(condition, message) { if (!condition) throw new Error(message); }

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
      this.socket.addEventListener('open', () => { clearTimeout(timer); complete(); }, { once: true });
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

  close() { this.socket?.close(); }
}

async function terminate(child) {
  if (!child?.pid || child.exitCode !== null) return { pid: child?.pid ?? null, stopped: true, forced: false };
  child.kill('SIGTERM');
  await Promise.race([new Promise((complete) => child.once('exit', complete)), delay(2_000)]);
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
const harnessUrl = `${appOrigin}/modules/lut-lab/dev/harness.html?qa=1&bridge=mock&vhost=local`;
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
  explicitlyNot: ['WebView2', 'Launcher', 'lutlab.grabFrame/lutlab.bakeXml 真实 Host 实现', 'deployment', 'human_visual_acceptance'],
  runner: 'custom-edge-cdp',
  startedAt,
  edgePath,
  harnessUrl,
  qa: null,
  screenshots: {},
  network: { requests: [], failures: [], externalRequests: [] },
  consoleErrors: [],
  consoleErrorsWhitelisted: [],
  runtimeExceptions: [],
  cleanup: {},
  passed: false,
};

// 降级路径 QA 会故意探 404（/vhost-missing/*），Edge 会记 console 资源错误；只白名单这一类。
const EXPECTED_404 = /vhost-missing/;
function isExpectedResource404(text, url) {
  return EXPECTED_404.test(String(url || '')) || EXPECTED_404.test(String(text || ''));
}

async function capturePage(name) {
  const capture = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
    captureBeyondViewport: false,
  });
  writeFileSync(resolve(artifactRoot, name), Buffer.from(capture.data, 'base64'));
  summary.screenshots[name] = resolve(artifactRoot, name);
}

try {
  server = spawn(process.execPath, [resolve(moduleDir, 'dev/server.mjs'), String(appPort)], {
    cwd: moduleDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  server.stdout.on('data', (chunk) => serverOutput.push(String(chunk)));
  server.stderr.on('data', (chunk) => serverOutput.push(String(chunk)));
  await waitForHttp(`${appOrigin}/modules/lut-lab/dev/harness.html`);

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
    cwd: moduleDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  browser.stdout.on('data', (chunk) => browserOutput.push(String(chunk)));
  browser.stderr.on('data', (chunk) => browserOutput.push(String(chunk)));

  const versionResponse = await waitForHttp(`http://127.0.0.1:${debugPort}/json/version`);
  summary.browserVersion = (await versionResponse.json()).Browser;
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
    summary.network.requests.push(request.url);
    if (!request.url.startsWith(appOrigin) && !/^(data|blob|devtools):/.test(request.url)) {
      summary.network.externalRequests.push(request.url);
    }
  });
  cdp.on('Network.loadingFailed', ({ errorText, canceled, requestId }) => {
    summary.network.failures.push({ requestId, errorText, canceled: Boolean(canceled) });
  });
  cdp.on('Runtime.exceptionThrown', ({ exceptionDetails }) => {
    summary.runtimeExceptions.push({
      text: exceptionDetails?.text ?? 'Unknown runtime exception',
      description: exceptionDetails?.exception?.description ?? null,
      url: exceptionDetails?.url ?? null,
      lineNumber: exceptionDetails?.lineNumber ?? null,
    });
  });
  const recordConsoleError = (source, text, url) => {
    const entry = { source, text, url: url ?? null };
    if (isExpectedResource404(text, url)) summary.consoleErrorsWhitelisted.push(entry);
    else summary.consoleErrors.push(entry);
  };
  cdp.on('Log.entryAdded', ({ entry }) => {
    if (entry?.level === 'error') recordConsoleError(entry.source, entry.text, entry.url);
  });
  cdp.on('Runtime.consoleAPICalled', ({ type, args }) => {
    if (type !== 'error' && type !== 'assert') return;
    recordConsoleError(`console.${type}`,
      (args ?? []).map((argument) => argument.value ?? argument.description ?? '').join(' '), null);
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

  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1600,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await cdp.send('Page.navigate', { url: harnessUrl });

  // 页面内 QA：含集合/差值/peek/扫动/帮助/布局与两次面板重开，给软件渲染留足余量
  const qaDeadline = Date.now() + 120_000;
  let qaState = 'pending';
  while (Date.now() < qaDeadline) {
    qaState = await evaluate('document.documentElement.getAttribute("data-lutlab-qa") || "pending"');
    if (qaState === 'passed' || qaState === 'failed') break;
    await delay(120);
  }
  assert(qaState !== 'pending', 'Harness QA did not reach a terminal state.');
  summary.qa = await evaluate('window.__LUTLAB_QA_RESULTS__ || null');
  assert(Array.isArray(summary.qa), 'Harness did not expose QA results.');
  assert(summary.qa.length === 31 && summary.qa.every((check) => check.pass === true),
    `Harness QA contract drifted: ${JSON.stringify(summary.qa.filter((check) => !check.pass))}`);
  assert(qaState === 'passed', `Harness QA ended in ${qaState}.`);

  // 第二视口（1100×640）复跑全量页面内 QA：布局响应式断言必须在更小视口同样成立
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1100,
    height: 640,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await cdp.send('Page.navigate', { url: harnessUrl });
  qaState = 'pending';
  const smallDeadline = Date.now() + 120_000;
  while (Date.now() < smallDeadline) {
    qaState = await evaluate('document.documentElement.getAttribute("data-lutlab-qa") || "pending"');
    if (qaState === 'passed' || qaState === 'failed') break;
    await delay(120);
  }
  assert(qaState !== 'pending', 'Harness QA (small viewport) did not reach a terminal state.');
  summary.qaSmallViewport = await evaluate('window.__LUTLAB_QA_RESULTS__ || null');
  assert(Array.isArray(summary.qaSmallViewport)
    && summary.qaSmallViewport.length === 31
    && summary.qaSmallViewport.every((check) => check.pass === true),
    `Harness QA small-viewport drifted: ${JSON.stringify((summary.qaSmallViewport || []).filter((check) => !check.pass))}`);
  assert(qaState === 'passed', `Harness QA (small viewport) ended in ${qaState}.`);

  // 回到 1600×900 留截图证据
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1600,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });

  // QA 终态停留在降级视图，先留降级证据
  await capturePage('lut-lab-degraded.png');

  // 回到可用桥 + 可用 vhost 的 happy path，留集合胶片条证据
  await evaluate(`(async () => {
    window.__lutLabHarness.setBridgeMode('mock');
    window.__lutLabHarness.setVhostBase('/vhost');
    window.__lutLabHarness.reopen();
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const rootEl = document.getElementById('lut-lab-panel');
      if (rootEl && rootEl.getAttribute('data-vhost') === 'ok'
          && rootEl.querySelectorAll('.lut-lab-film-cell canvas').length >= 10) return true;
      await new Promise((complete) => setTimeout(complete, 50));
    }
    throw new Error('happy-path reopen timed out');
  })()`);
  await delay(300);
  await capturePage('lut-lab-grid.png');

  // 联动检视：点击主预览进 A|B 检视并滚轮放大两档，留 banding 检查视图证据
  await evaluate(`(async () => {
    const rootEl = document.getElementById('lut-lab-panel');
    const stage = rootEl.querySelector('.lut-lab-stage');
    const rect = stage.getBoundingClientRect();
    const x = rect.left + rect.width / 2, y = rect.top + rect.height / 2;
    stage.dispatchEvent(new MouseEvent('mousedown', { clientX: x, clientY: y, bubbles: true, cancelable: true }));
    stage.dispatchEvent(new MouseEvent('mouseup', { clientX: x, clientY: y, bubbles: true, cancelable: true }));
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const viewport = rootEl.querySelector('.lut-lab-inspect .lut-lab-inspect-viewport');
      if (viewport && rootEl.querySelector('.lut-lab-inspect').style.display !== 'none') {
        viewport.dispatchEvent(new WheelEvent('wheel', { deltaY: -120, clientX: x, clientY: y, bubbles: true, cancelable: true }));
        viewport.dispatchEvent(new WheelEvent('wheel', { deltaY: -120, clientX: x, clientY: y, bubbles: true, cancelable: true }));
        return true;
      }
      await new Promise((complete) => setTimeout(complete, 50));
    }
    throw new Error('inspection viewport did not open');
  })()`);
  await delay(200);
  await capturePage('lut-lab-inspection.png');
  await evaluate(`document.querySelector('.lut-lab-inspect')
    ?.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);

  assert(summary.consoleErrors.length === 0,
    `Browser console errors: ${JSON.stringify(summary.consoleErrors)}`);
  assert(summary.runtimeExceptions.length === 0,
    `Runtime exceptions: ${JSON.stringify(summary.runtimeExceptions)}`);
  assert(summary.network.failures.filter((failure) => !failure.canceled).length === 0,
    `Network failures: ${JSON.stringify(summary.network.failures)}`);
  assert(summary.network.externalRequests.length === 0,
    `Unexpected external requests: ${summary.network.externalRequests.join(', ')}`);
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
  console.log(`LUT-lab Edge/CDP QA: ${summary.passed ? 'PASS' : 'FAIL'}`);
  if (Array.isArray(summary.qa)) {
    for (const check of summary.qa) console.log(`  ${check.pass ? '✓' : '✗'} ${check.id}${check.detail ? ` — ${check.detail}` : ''}`);
  }
  console.log(`Summary: ${summaryPath}`);
  for (const [name, path] of Object.entries(summary.screenshots)) console.log(`Screenshot ${name}: ${path}`);
}

if (runError) throw runError;
