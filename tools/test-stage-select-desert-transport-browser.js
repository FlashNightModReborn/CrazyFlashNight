'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const { startServer } = require('./lib/stage-select-dev-server');
const root = path.resolve(__dirname, '..');
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));
async function main() {
    const config = JSON.parse(fs.readFileSync(path.join(root, 'launcher/web/assets/stage-diorama/desert-region/config.json'), 'utf8'));
    assert.equal(config.sceneTransport.encoding, 'gzip');
    const { server, origin } = await startServer(path.join(root, 'launcher/web'));
    const browser = await chromium.launch({ executablePath: path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'), headless: true });
    const errors = [], report = { scope: 'Real Edge production gzip loader and existing fallback/cancellation flow with mock Host', checks: [] };
    const url = origin + '/modules/stage-select/dev/harness.html?viewport=1024x576&frame=' + encodeURIComponent('基地房顶') + '&fixture=allUnlocked&player=1&review=transport';
    const pattern = '**/stage-diorama/desert-region/scene.glb.gz*';
    const newPage = async () => {
        const page = await browser.newPage({ viewport: { width: 1024, height: 576 } }); page.setDefaultTimeout(60000);
        page.on('pageerror', error => errors.push(error.message));
        await page.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' })); return page;
    };
    const ready = page => page.waitForFunction(() => StageSelectDiorama.stats().state === 'ready' && !StageSelectDiorama.stats().pending && !StageSelectDiorama.stats().moving);
    const fallback = async page => {
        await page.waitForFunction(() => StageSelectDiorama.stats().state === 'fallback');
        assert.equal(await page.locator('.stage-select-stage-button').count(), 11);
        assert.equal(await page.locator('.stage-select-diorama-canvas').count(), 0);
    };
    try {
        const unavailable = await newPage(); let downloads = 0;
        unavailable.on('request', request => { if (new URL(request.url()).pathname.endsWith('/scene.glb.gz')) downloads++; });
        await unavailable.addInitScript(() => Object.defineProperty(globalThis, 'DecompressionStream', { value: undefined, configurable: true }));
        await unavailable.goto(url); await fallback(unavailable); assert.equal(downloads, 0); await unavailable.close();
        report.checks.push('Missing DecompressionStream retains all 11 fallback entries without downloading or creating a renderer');

        const broken = await newPage();
        await broken.route(pattern, route => route.fulfill({ contentType: 'application/gzip', body: Buffer.from('bad-gzip-package') }));
        await broken.goto(url); await fallback(broken); await broken.unroute(pattern);
        await broken.getByRole('button', { name: '重试', exact: true }).click(); await ready(broken);
        const state = await broken.evaluate(() => StageSelectDiorama.stats());
        assert.equal(state.loadedHashes['scene.glb'], config.assetHashes['scene.glb']);
        assert.equal(state.sceneTransport.sha256, config.sceneTransport.sha256); assert.equal(state.sceneTransport.encoding, 'gzip');
        assert.equal(state.sceneTransport.bytes, config.sceneTransport.bytes); assert.equal(state.sceneTransport.decodedBytes, config.sceneTransport.decodedBytes);
        report.transport = state.sceneTransport; await broken.close();
        report.checks.push('Bad gzip transport falls back; the visible retry loads the verified compressed and decoded identities');

        const closing = await newPage(); let seen, release;
        const requested = new Promise(resolve => { seen = resolve; }), held = new Promise(resolve => { release = resolve; });
        await closing.route(pattern, async route => { seen(); await held; await route.continue().catch(() => {}); });
        await closing.goto(url); await requested;
        await closing.evaluate(() => StageSelectHarnessHost.close());
        assert.equal(await closing.locator('.stage-select-diorama-canvas').count(), 0);
        assert.equal(await closing.evaluate(() => StageSelectDiorama.stats().active), false);
        release(); await closing.unroute(pattern);
        await closing.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地房顶' })); await ready(closing);
        assert.equal(await closing.locator('.stage-select-diorama-canvas').count(), 1);
        assert.equal(await closing.evaluate(() => StageSelectDiorama.stats().loadedHashes['scene.glb']), config.assetHashes['scene.glb']);
        assert.deepEqual(errors, []); await closing.close();
        report.checks.push('Closing while the gzip request is pending retires that load; reopening produces one verified canvas with no stale callback or page error');
        report.pass = true;
    } catch (error) { report.pass = false; report.error = error.stack; report.pageErrors = errors; process.exitCode = 1; }
    finally {
        await browser.close(); server.close();
        const out = path.join(root, 'tmp/stage-select-desert'); fs.mkdirSync(out, { recursive: true });
        fs.writeFileSync(path.join(out, 'transport-browser-report.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report));
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
