// 用法：
//   node run-qa.js            → 跑全量
//   node run-qa.js map-ui26   → 只跑指定 caseId
//
// 依赖 launcher/perf/node_modules/playwright（perf harness 已声明），
// 通过 file:// 加载 harness.html 跑 MapPanelHarnessQA.runSuite。
// 退出码：所有 case 通过 = 0，任一 FAIL = 1。
const path = require('path');
const playwrightDir = path.resolve(__dirname, '..', '..', '..', '..', 'perf', 'node_modules', 'playwright');
const { chromium } = require(playwrightDir);

const harnessUrl = 'file:///' + path.resolve(__dirname, 'harness.html').replace(/\\/g, '/');
const caseId = process.argv[2] || '';

(async () => {
    const browser = await chromium.launch();
    const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', err => errors.push('[pageerror] ' + err.message));

    await page.goto(harnessUrl);
    await page.waitForSelector('.map-panel', { state: 'visible', timeout: 5000 });
    await page.waitForTimeout(400);

    const result = await page.evaluate(async (caseId) => {
        const host = window.MapHarnessHost;
        const qa = window.MapPanelHarnessQA;
        if (!host || !qa) return { error: 'host or qa missing' };

        const log = [];
        function assert(cond, msg) { if (!cond) { throw new Error(msg); } }
        function assertEqual(a, b, msg) {
            if (a !== b) throw new Error((msg || 'equal') + ': expected ' + JSON.stringify(b) + ', got ' + JSON.stringify(a));
        }
        function waitFor(predicate, timeoutMs, label) {
            return new Promise(function(resolve, reject) {
                var start = Date.now();
                (function tick() {
                    var r; try { r = predicate(); } catch (e) { r = null; }
                    if (r) return resolve(r);
                    if (Date.now() - start > (timeoutMs || 2000)) return reject(new Error('waitFor timeout: ' + (label || '')));
                    setTimeout(tick, 30);
                })();
            });
        }
        async function runCase(id, title, fn) {
            try { const r = await fn(); log.push('PASS ' + id + ' :: ' + String(r)); return { id: id, ok: true, detail: String(r) }; }
            catch (e) { log.push('FAIL ' + id + ' :: ' + e.message); return { id: id, ok: false, error: e.message }; }
        }
        const api = { assert, assertEqual, waitFor, runCase };

        const r = await qa.runSuite(api, host, caseId || undefined);
        return { log: log, summary: r };
    }, caseId);

    console.log((result.log || []).join('\n'));
    const lines = result.log || [];
    const fails = lines.filter(l => l.startsWith('FAIL'));
    console.log('=== ' + (lines.length - fails.length) + ' passed, ' + fails.length + ' failed ===');
    if (errors.length) console.log(errors.join('\n'));
    await browser.close();
    process.exit(fails.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
