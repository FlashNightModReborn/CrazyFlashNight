#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const HARNESS = 'modules/character-build/dev/workbench-harness.html';
const shotArg = process.argv.find(argument => argument.startsWith('--shot-dir='));

function writeShots(shots, viewport) {
    if (!shotArg) return 0;
    const directory = path.resolve(shotArg.slice('--shot-dir='.length));
    fs.mkdirSync(directory, {recursive:true});
    let written = 0;
    Object.keys(shots || {}).forEach(name => {
        const match = /^data:image\/png;base64,(.+)$/.exec(shots[name]);
        if (!match) throw new Error('invalid Canvas screenshot payload: ' + name);
        fs.writeFileSync(path.join(directory,
            viewport.width + 'x' + viewport.height + '-' + name + '.png'),
        Buffer.from(match[1], 'base64'));
        written++;
    });
    return written;
}

function edgeExecutable() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
            'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files',
            'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB, pathname));
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
                const extension = path.extname(file);
                response.writeHead(200, {'Content-Type':extension === '.html'
                    ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                        : extension === '.js' ? 'text/javascript; charset=utf-8'
                            : 'application/octet-stream'});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function runStorageToBuildVisibilityProbe(browser, server, shotDirectory) {
    const viewport = {width:1024, height:576};
    const page = await browser.newPage({
        viewport,
        reducedMotion:'reduce',
        deviceScaleFactor:1
    });
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    await page.route('https://cfn-fonts.local/**', async route => {
        const fontName = path.basename(new URL(route.request().url()).pathname);
        const fontPath = path.join(process.env.LOCALAPPDATA || '',
            'CF7FlashNight', 'fonts', fontName);
        if (!fs.existsSync(fontPath)) return route.abort('failed');
        return route.fulfill({
            path:fontPath,
            headers:{'access-control-allow-origin':'*'}
        });
    });
    try {
        await page.goto('http://127.0.0.1:' + server.address().port + '/' + HARNESS
            + '?stats-probe=1',
        {waitUntil:'load'});
        await page.waitForFunction(() => window.__statsProbeReady === true, null,
            {timeout:30000});
        await page.evaluate(() => {
            const output = document.getElementById('qa-output');
            if (output) output.hidden = true;
        });

        await page.locator('[data-header-action="back-build"]').click();
        await page.waitForFunction(() => InventoryWorkbench.debugState().view === 'build');
        await page.locator('[data-header-action="storage"]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.view === 'storage' && state.storage && state.storage.active;
        });
        const storageMounted = await page.evaluate(() => {
            const body = document.querySelector('.workbench-shell > .workbench-body');
            const host = document.querySelector('.character-build-host');
            return {
                active:InventoryWorkbench.debugState().storage.active,
                view:InventoryWorkbench.debugState().view,
                bodyHidden:body.hidden,
                bodyDisplay:getComputedStyle(body).display,
                hostHidden:host.hidden,
                hostDisplay:getComputedStyle(host).display
            };
        });
        if (!storageMounted.active || storageMounted.view !== 'storage'
                || storageMounted.bodyHidden || storageMounted.bodyDisplay === 'none'
                || !storageMounted.hostHidden || storageMounted.hostDisplay !== 'none') {
            throw new Error('storage did not mount before build switch: '
                + JSON.stringify(storageMounted));
        }

        await page.locator('[data-header-action="return-build"]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.view === 'build' && state.build && state.build.mounted
                && state.build.rendererCount === 1
                && state.build.view && state.build.view.candidateCount === 1;
        }, null, {timeout:30000});
        const switched = await page.evaluate(() => {
            const body = document.querySelector('.workbench-shell > .workbench-body');
            const host = document.querySelector('.character-build-host');
            const action = document.querySelector('[data-doll-preview-open]');
            const bodyRect = body.getBoundingClientRect();
            const hostRect = host.getBoundingClientRect();
            const actionRect = action.getBoundingClientRect();
            const hit = document.elementFromPoint(
                actionRect.left + actionRect.width / 2,
                actionRect.top + actionRect.height / 2);
            return {
                bodyHidden:body.hidden,
                bodyDisplay:getComputedStyle(body).display,
                bodyClientRects:body.getClientRects().length,
                bodyWidth:bodyRect.width,
                bodyHeight:bodyRect.height,
                hostHidden:host.hidden,
                hostDisplay:getComputedStyle(host).display,
                hostVisibility:getComputedStyle(host).visibility,
                hostWidth:hostRect.width,
                hostHeight:hostRect.height,
                actionWidth:actionRect.width,
                actionHeight:actionRect.height,
                actionHit:!!hit && (hit === action || action.contains(hit))
            };
        });
        if (!switched.bodyHidden || switched.bodyDisplay !== 'none'
                || switched.bodyClientRects !== 0
                || switched.bodyWidth !== 0 || switched.bodyHeight !== 0) {
            throw new Error('hidden storage body still paints after build switch: '
                + JSON.stringify(switched));
        }
        if (switched.hostHidden || switched.hostDisplay === 'none'
                || switched.hostVisibility === 'hidden'
                || switched.hostWidth <= 0 || switched.hostHeight <= 0) {
            throw new Error('character host is not visible after storage switch: '
                + JSON.stringify(switched));
        }
        if (!switched.actionHit || switched.actionWidth < 44 || switched.actionHeight < 44) {
            throw new Error('character action is not the pointer hit target after storage switch: '
                + JSON.stringify(switched));
        }
        if (shotDirectory) {
            await page.screenshot({
                path:path.join(shotDirectory,
                    '1024x576-character-build-after-storage-switch.png')
            });
        }
        await page.locator('[data-doll-preview-open]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.build && state.build.view && state.build.view.dollPreviewOpen;
        });
        await page.locator('[data-doll-preview-close]').click();
        await page.waitForFunction(() => {
            const state = InventoryWorkbench.debugState();
            return state.build && state.build.view && !state.build.view.dollPreviewOpen;
        });

        const unexpectedFailedRequests = failedRequests.filter(request =>
            !request.includes('__qa_expected_asset_failure_'));
        if (pageErrors.length || unexpectedFailedRequests.length) {
            throw new Error('storage-to-build visibility probe diagnostics: '
                + JSON.stringify({pageErrors, failedRequests:unexpectedFailedRequests}));
        }
        console.log('1024x576 storage-to-build visibility: 4/4 checks'
            + (shotDirectory ? '; screenshot=1024x576-character-build-after-storage-switch.png'
                : ''));
        return 4;
    } finally {
        await page.close();
    }
}

(async function main() {
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const source = fs.readFileSync(path.join(WEB, HARNESS), 'utf8');
    [
        'modules/asset-timeline.js',
        'modules/icons.js',
        'modules/dressup/dev/character-build-combination-fixture.js',
        'modules/character-build/dev/stats-fixture.js',
        'modules/dressup-doll-renderer.js',
        'modules/panels.js',
        'modules/panel-scale.js',
        'modules/item-filter.js',
        'modules/inventory-ui.js',
        'modules/equipment-tuning-runtime.js',
        'modules/equipment-tuning-model.js',
        'modules/equipment-tuning-render.js',
        'modules/equipment-tuning-view.js',
        'modules/workbench-inspection-viewport.js',
        'modules/character-build/character-build-mutation.js',
        'modules/character-build-session.js',
        'modules/character-build/character-build-action-view.js',
        'modules/character-build/character-build-stats-view.js',
        'modules/character-build/character-build-doll-preview.js',
        'modules/character-build/character-build-tuning.js',
        'modules/character-build/character-build-pose.js',
        'modules/character-build.js',
        'modules/inventory-workbench.js'
    ].forEach(asset => {
        if (!source.includes(asset)) throw new Error('integration harness omits ' + asset);
    });
    if (source.includes('window.Icons =') || source.includes('window.DressupDollRenderer = {')) {
        throw new Error('integration harness replaces a production visual dependency');
    }

    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    try {
        const viewports = [
            {width:1024, height:576},
            {width:1366, height:768},
            {width:1920, height:1080}
        ];
        const shotDirectory = shotArg
            ? path.resolve(shotArg.slice('--shot-dir='.length)) : '';
        if (shotDirectory) fs.mkdirSync(shotDirectory, {recursive:true});
        const switchProbePassed = await runStorageToBuildVisibilityProbe(
            browser, server, shotDirectory);
        let passed = 0;
        for (const viewport of viewports) {
            const page = await browser.newPage({
                viewport,
                reducedMotion:'reduce',
                deviceScaleFactor:1
            });
            const pageErrors = [];
            const failedRequests = [];
            page.on('pageerror', error => pageErrors.push(error.message));
            page.on('requestfailed', request => failedRequests.push(request.url()));
            await page.route('https://cfn-fonts.local/**', async route => {
                const fontName = path.basename(new URL(route.request().url()).pathname);
                const fontPath = path.join(process.env.LOCALAPPDATA || '',
                    'CF7FlashNight', 'fonts', fontName);
                if (!fs.existsSync(fontPath)) return route.abort('failed');
                return route.fulfill({
                    path:fontPath,
                    headers:{'access-control-allow-origin':'*'}
                });
            });
            await page.goto('http://127.0.0.1:' + server.address().port + '/' + HARNESS
                + '?stats-probe=1',
                {waitUntil:'load'});
            try {
                await page.waitForFunction(() => window.__statsProbeReady === true, null,
                    {timeout:30000});
            } catch (error) {
                const diagnostic = await page.evaluate(() => ({
                    report:window.__qaReport || null,
                    output:(document.getElementById('qa-output') || {}).textContent || ''
                }));
                throw new Error(error.message + '\n' + JSON.stringify({
                    pageErrors, failedRequests, diagnostic
                }, null, 2));
            }
            await page.evaluate(() => {
                const output = document.getElementById('qa-output');
                if (output) output.hidden = true;
            });
            if (shotDirectory && viewport === viewports[0]) {
                await page.screenshot({
                    path:path.join(shotDirectory,
                        '1024x576-character-build-production-stats-top.png')
                });
            }
            await page.waitForFunction(() => document.activeElement
                === document.querySelector('[data-scroll-region="stats"]'));
            const inputProbe = await page.evaluate(async () => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                const before = scroll.scrollTop;
                return {
                    reducedMotion:matchMedia('(prefers-reduced-motion: reduce)').matches,
                    keyboardFocused:document.activeElement === scroll,
                    focusVisible:scroll.matches(':focus-visible'),
                    before,
                    maxScroll:scroll.scrollHeight - scroll.clientHeight
                };
            });
            await page.keyboard.press('PageDown');
            await page.waitForFunction(before => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                return scroll.scrollTop > before + 1;
            }, inputProbe.before);
            inputProbe.pageDownDelta = await page.evaluate(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop);
            await page.keyboard.press('End');
            await page.waitForFunction(() => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                return scroll.scrollTop >= scroll.scrollHeight - scroll.clientHeight - 1;
            });
            Object.assign(inputProbe, await page.evaluate(() => {
                const scroll = document.querySelector('[data-scroll-region="stats"]');
                const last = document.querySelector(
                    '[data-stats-detail-grid] > section:last-child');
                const scrollRect = scroll.getBoundingClientRect();
                const lastRect = last.getBoundingClientRect();
                return {
                    endReached:scroll.getAttribute('data-scroll-position') === 'end',
                    lastVisible:lastRect.top >= scrollRect.top - 1
                        && lastRect.bottom <= scrollRect.bottom + 1
                };
            }));
            if (shotDirectory && viewport === viewports[0]) {
                await page.screenshot({
                    path:path.join(shotDirectory,
                        '1024x576-character-build-production-stats-end.png')
                });
            }
            await page.keyboard.press('Home');
            await page.waitForFunction(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop <= 1);
            inputProbe.homeReached = true;
            const scrollRect = await page.locator('[data-scroll-region="stats"]').boundingBox();
            await page.mouse.move(scrollRect.x + scrollRect.width / 2,
                scrollRect.y + scrollRect.height / 2);
            await page.mouse.wheel(0, 360);
            await page.waitForFunction(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop > 1);
            inputProbe.wheelDelta = await page.evaluate(() =>
                document.querySelector('[data-scroll-region="stats"]').scrollTop);
            await page.evaluate(probe => {
                window.__routeHarness.statsInputProbe = probe;
                window.__continueStatsProbe();
            }, inputProbe);
            await page.waitForFunction(() => window.__qaReady === true, null, {timeout:30000});
            const report = await page.evaluate(() => window.__qaReport);
            const shots = shotArg && viewport === viewports[0]
                ? await page.evaluate(() => window.__routeHarness.shots) : {};
            if (pageErrors.length) throw new Error(viewport.width + 'x' + viewport.height
                + ' page errors: ' + pageErrors.join(' | '));
            const unexpectedFailedRequests = failedRequests.filter(request =>
                !request.includes('__qa_expected_asset_failure_'));
            if (unexpectedFailedRequests.length) {
                throw new Error(viewport.width + 'x' + viewport.height
                    + ' failed requests: ' + unexpectedFailedRequests.join(' | '));
            }
            const failures = report.checks.filter(check => !check.ok);
            if (failures.length) {
                throw new Error(viewport.width + 'x' + viewport.height + '\n'
                    + failures.map(check =>
                        check.name + (check.detail ? ': ' + check.detail : '')).join('\n'));
            }
            const loadout = report.sent.filter(message => message.domain === 'loadout');
            const whitelist = [
                'snapshot', 'candidates', 'flushLive', 'statsSnapshot', 'finalize',
                'equipEquipment', 'unequipEquipment', 'equipDrug', 'unequipDrug'
            ];
            if (!loadout.length || loadout.some(message => !whitelist.includes(message.cmd))) {
                throw new Error('production route escaped the nine-command whitelist');
            }
            if (report.renderer.maxActive !== 1 || report.renderer.active !== 0) {
                throw new Error('renderer ownership did not settle: '
                    + JSON.stringify(report.renderer));
            }
            ['initial', 'candidate', 'restored'].forEach(stage => {
                const visual = report.visual[stage];
                if (!visual || visual.alphaPixels <= 2500
                        || visual.bboxHeightRatio < 0.68 || visual.bboxHeightRatio > 0.92) {
                    throw new Error(stage + ' visual proof outside frozen bounds: '
                        + JSON.stringify(visual));
                }
            });
            if (report.renderer.expectedAssetFailures !== 2
                    || report.shotNames.length !== 34
                    || report.visual.poseMatrix.length !== 35
                    || !report.visual.stats || !report.visual.stats.input
                    || report.visual.stats.input.wheelDelta <= 1
                    || report.boundary.controller !== 'production'
                    || report.boundary.storage !== 'facade_stub'
                    || report.boundary.host !== 'fake_bridge') {
                throw new Error('production pose matrix evidence incomplete: '
                    + JSON.stringify({
                        failures:report.renderer.expectedAssetFailures,
                        shots:report.shotNames.length,
                        poses:report.visual.poseMatrix.length
                    }));
            }
            const written = writeShots(shots, viewport);
            console.log(viewport.width + 'x' + viewport.height + ': '
                + report.checks.length + '/' + report.checks.length
                + ' checks; initial alpha=' + report.visual.initial.alphaPixels
                + ', bbox=' + (report.visual.initial.bboxHeightRatio * 100).toFixed(1) + '%'
                + ', stats=' + report.visual.stats.top.clientHeight + '/'
                    + report.visual.stats.top.scrollHeight
                + ', wheel=' + Math.round(report.visual.stats.input.wheelDelta)
                + (written ? ', screenshots=' + written : ''));
            passed += report.checks.length;
            await page.close();
        }
        console.log('Character-build production controller integration'
            + ' (storage facade + fake Host bridge): ' + passed + '/' + passed
            + ' passed across ' + viewports.length + ' viewports');
        console.log('Storage-to-build hidden-body regression: ' + switchProbePassed + '/'
            + switchProbePassed + ' passed at 1024x576');
            if (shotArg) {
            console.log('Screenshots: ' + shotDirectory);
        }
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
