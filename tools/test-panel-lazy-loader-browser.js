'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { URL } = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const HARNESS_PATH = '/__panel-lazy-loader-recovery.html';
const FAULT_PATH = '/modules/arena/arena-preview-authority.js';
const FACADE_PATH = '/modules/arena-panel.js';

function edgePath() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA
            ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe')
            : null
    ];
    return candidates.find(candidate => candidate && fs.existsSync(candidate)) || null;
}

function contentType(file) {
    const ext = path.extname(file).toLowerCase();
    if (ext === '.js') return 'text/javascript; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.svg') return 'image/svg+xml';
    if (ext === '.png') return 'image/png';
    return 'application/octet-stream';
}

function harnessHtml() {
    return `<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>Panel LazyLoader recovery</title></head>
<body>
  <div id="panel-container" style="display:none">
    <div id="panel-backdrop"></div><div id="panel-content"></div>
  </div>
  <script>
    window.__lazyDefinitions = {};
    window.__registrations = [];
    window.chrome = { webview: {
      listeners: [],
      addEventListener: function(type, handler) {
        if (type === 'message') this.listeners.push(handler);
      },
      postMessage: function() {}
    } };
  </script>
  <script src="/modules/bridge.js"></script>
  <script src="/modules/panels.js"></script>
  <script src="/modules/lazy-loader.js"></script>
  <script>
    (function() {
      var originalRegisterLazy = Panels.registerLazy;
      var originalRegister = Panels.register;
      Panels.registerLazy = function(id, deps, registerFn) {
        window.__lazyDefinitions[id] = { deps: deps.slice(), registerFn: registerFn };
        return originalRegisterLazy.call(Panels, id, deps, registerFn);
      };
      Panels.register = function(id, definition) {
        window.__registrations.push(id);
        return originalRegister.call(Panels, id, definition);
      };
    })();
  </script>
  <script src="/modules/panels-lazy-registry.js"></script>
</body>
</html>`;
}

function createServer(ledger) {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
            ledger.requests.push(pathname);

            if (pathname === HARNESS_PATH) {
                response.writeHead(200, {'Content-Type':'text/html; charset=utf-8'});
                response.end(harnessHtml());
                return;
            }

            if (pathname === FAULT_PATH && ledger.faultsRemaining > 0) {
                ledger.faultsRemaining -= 1;
                ledger.injectedFailures += 1;
                response.writeHead(503, {'Content-Type':'text/javascript; charset=utf-8'});
                response.end('// intentional one-shot transport failure');
                return;
            }

            const file = path.normalize(path.join(WEB, pathname.replace(/^\/+/, '')));
            const relative = path.relative(WEB, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403);
                response.end();
                return;
            }
            fs.readFile(file, (error, data) => {
                if (error) {
                    response.writeHead(404);
                    response.end();
                    return;
                }
                response.writeHead(200, {'Content-Type':contentType(file)});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

function countRequests(requests, pathname) {
    return requests.filter(item => item === pathname).length;
}

async function main() {
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge executable not found');

    const ledger = { requests:[], faultsRemaining:1, injectedFailures:0 };
    const server = await createServer(ledger);
    const { chromium } = require(PLAYWRIGHT);
    const browser = await chromium.launch({ executablePath, headless:true });
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));

    try {
        await page.goto(`http://127.0.0.1:${server.address().port}${HARNESS_PATH}`, {waitUntil:'load'});
        const captured = await page.evaluate(() => {
            const definition = window.__lazyDefinitions.arena;
            return definition ? definition.deps.slice() : null;
        });
        assert(Array.isArray(captured), 'arena lazy definition must be captured from the production registry');
        assert(captured.includes(FAULT_PATH.slice(1)), 'arena closure must contain the injected middle dependency');
        assert.strictEqual(captured[captured.length - 1], FACADE_PATH.slice(1), 'arena facade must remain the final dependency');

        const first = await page.evaluate(async ({faultUrl, facadeUrl}) => {
            const definition = window.__lazyDefinitions.arena;
            let error = null;
            try {
                await LazyLoader.load(definition.deps);
            } catch (caught) {
                error = caught && caught.message ? caught.message : String(caught);
            }
            await new Promise(resolve => setTimeout(resolve, 100));
            return {
                error,
                faultCached:LazyLoader.isLoaded(faultUrl),
                facadeCached:LazyLoader.isLoaded(facadeUrl),
                registrations:window.__registrations.slice()
            };
        }, {faultUrl:FAULT_PATH.slice(1), facadeUrl:FACADE_PATH.slice(1)});

        const requestsAfterFirst = ledger.requests.slice();
        assert(first.error && first.error.includes(FAULT_PATH.slice(1)), 'first load must reject at the injected dependency');
        assert.strictEqual(first.faultCached, false, 'failed dependency must be evicted from the URL cache');
        assert.strictEqual(first.facadeCached, false, 'facade after the failed dependency must not be injected or cached');
        assert.strictEqual(first.registrations.filter(id => id === 'arena').length, 0, 'failed closure must not register arena');
        assert.strictEqual(countRequests(requestsAfterFirst, FACADE_PATH), 0, 'first failed chain must not request the facade');
        assert.deepStrictEqual(pageErrors, [], 'transport failure must not execute a dependency-broken facade');

        const second = await page.evaluate(async ({faultUrl, facadeUrl}) => {
            const definition = window.__lazyDefinitions.arena;
            await LazyLoader.load(definition.deps);
            definition.registerFn();
            return {
                faultCached:LazyLoader.isLoaded(faultUrl),
                facadeCached:LazyLoader.isLoaded(facadeUrl),
                registrations:window.__registrations.slice(),
                coreReady:!!window.ArenaCore,
                facadeReady:!!window.ArenaPanel
            };
        }, {faultUrl:FAULT_PATH.slice(1), facadeUrl:FACADE_PATH.slice(1)});

        assert.strictEqual(ledger.injectedFailures, 1, 'exactly one transport failure must be injected');
        assert.strictEqual(countRequests(ledger.requests, FAULT_PATH), 2, 'failed dependency must be requested exactly once again');
        assert.strictEqual(countRequests(ledger.requests, FACADE_PATH), 1, 'facade must execute exactly once after recovery');
        assert.strictEqual(second.faultCached, true, 'recovered dependency must enter the URL cache');
        assert.strictEqual(second.facadeCached, true, 'facade must be cached only after the recovered chain reaches it');
        assert.strictEqual(second.registrations.filter(id => id === 'arena').length, 1, 'retry must register arena exactly once');
        assert(second.coreReady && second.facadeReady, 'retry must expose the complete Arena module closure');
        assert.deepStrictEqual(pageErrors, [], 'recovered chain must finish without page execution errors');

        process.stdout.write('panel lazy loader browser recovery: 17/17 passed\n');
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : error);
    process.exitCode = 1;
});
