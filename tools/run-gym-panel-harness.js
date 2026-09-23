#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const playwrightModule = path.join(projectRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const gymAssetPackage = process.env.CF7_GYM_MOTION_ASSET_ROOT
    ? path.resolve(process.env.CF7_GYM_MOTION_ASSET_ROOT) : null;
const visualOutputDir = path.resolve(process.env.CF7_GYM_VISUAL_OUTPUT_DIR
    || path.join(projectRoot, 'tmp', 'gym-panel-visual'));
const panelViewport = process.env.CF7_GYM_PANEL_VIEWPORT === '1600x900'
    ? { width:1600, height:900 } : { width:1024, height:576 };

async function installGymAssetRoute(page) {
    if (!gymAssetPackage) return;
    await page.route('**/assets/gym/**', async route => {
        const requestUrl = new URL(route.request().url());
        const prefix = '/assets/gym/';
        if (!requestUrl.pathname.startsWith(prefix)) return route.continue();
        let relativePath;
        try { relativePath = decodeURIComponent(requestUrl.pathname.slice(prefix.length)); }
        catch (_) { return route.fulfill({ status:400, body:'invalid asset path' }); }
        const assetPath = path.resolve(gymAssetPackage, ...relativePath.split('/'));
        const relativeCheck = path.relative(gymAssetPackage, assetPath);
        if (relativeCheck === '..' || relativeCheck.startsWith('..' + path.sep) || path.isAbsolute(relativeCheck)) {
            return route.fulfill({ status:400, body:'invalid asset path' });
        }
        if (!fs.existsSync(assetPath)) return route.fulfill({ status:404, body:'gym asset missing' });
        return route.fulfill({ path:assetPath });
    });
}

function findEdge() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    const executable = candidates.find(candidate => candidate && fs.existsSync(candidate));
    if (!executable) throw new Error('Cannot find Microsoft Edge.');
    return executable;
}

async function main() {
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const productionGymAssets = path.join(projectRoot, 'launcher', 'web', 'assets', 'gym');
    const selectedGymAssets = gymAssetPackage || productionGymAssets;
    if (!fs.existsSync(path.join(selectedGymAssets, 'manifest.json'))) {
        throw new Error('Missing gym motion package: ' + selectedGymAssets);
    }
    const { chromium } = require(playwrightModule);
    const executablePath = findEdge();
    const serverResult = await require('./lib/stage-select-dev-server')
        .startServer(path.join(projectRoot, 'launcher', 'web'));
    let browser = null;
    try {
        browser = await chromium.launch({ executablePath, headless:true, args:[] });
        const page = await browser.newPage({ viewport:panelViewport });
        await page.emulateMedia({ reducedMotion:'no-preference' });
        await page.addInitScript(() => {
            Object.defineProperty(Document.prototype, 'hasFocus', {
                configurable:true,
                value:function() { return false; }
            });
        });
        await installGymAssetRoute(page);
        const pageErrors = [];
        const failedRequests = [];
        page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
        page.on('requestfailed', request => {
            const failure = request.failure();
            const text = request.url() + ' :: ' + (failure && failure.errorText || 'failed');
            if (request.resourceType() === 'image' && failure && failure.errorText === 'net::ERR_ABORTED') return;
            failedRequests.push(text);
        });
        await page.route('https://cfn-fonts.local/**', route => route.fulfill({
            status:204,
            headers:{ 'access-control-allow-origin':'*' },
            body:''
        }));
        await page.goto(serverResult.origin + '/modules/gym/dev/harness.html', { waitUntil:'load' });
        await page.waitForFunction(() => window.__gymPanelReviewReady || window.__gymHarnessResult,
            null, { timeout:60000 });
        fs.mkdirSync(visualOutputDir, { recursive:true });
        const gymPanelScreenshot = path.join(visualOutputDir, 'gym-panel-sample.png');
        if (await page.evaluate(() => !!window.__gymPanelReviewReady)) {
            await page.screenshot({ path:gymPanelScreenshot, fullPage:true });
            await page.evaluate(() => {
                if (typeof window.__gymHarnessContinue === 'function') window.__gymHarnessContinue();
            });
        }
        await page.waitForFunction(() => !!window.__gymHarnessResult, null, { timeout:60000 });
        const qa = await page.evaluate(() => window.__gymHarnessResult);
        const equippedCanvasDataUrl = await page.evaluate(() => window.__gymEquippedCanvasDataUrl || '');
        const gymEquippedCurrentScreenshot = path.join(visualOutputDir, 'gym-equipped-current.png');
        if (equippedCanvasDataUrl.startsWith('data:image/png;base64,')) {
            fs.writeFileSync(gymEquippedCurrentScreenshot,
                Buffer.from(equippedCanvasDataUrl.slice('data:image/png;base64,'.length), 'base64'));
        }
        const reviewPage = await browser.newPage({ viewport:{ width:1024, height:576 } });
        const reviewPageErrors = [];
        const reviewFailedRequests = [];
        reviewPage.on('pageerror', error => reviewPageErrors.push(error && error.message ? error.message : String(error)));
        reviewPage.on('requestfailed', request => {
            const failure = request.failure();
            const text = request.url() + ' :: ' + (failure && failure.errorText || 'failed');
            if (request.resourceType() === 'image' && failure && failure.errorText === 'net::ERR_ABORTED') return;
            reviewFailedRequests.push(text);
        });
        await installGymAssetRoute(reviewPage);
        await reviewPage.route('https://cfn-fonts.local/**', route => route.fulfill({
            status:204,
            headers:{ 'access-control-allow-origin':'*' },
            body:''
        }));
        await reviewPage.goto(serverResult.origin + '/modules/gym/dev/appearance-review.html', { waitUntil:'load' });
        await reviewPage.waitForFunction(() => {
            const status = document.getElementById('gym-review-state');
            return status && status.textContent.indexOf('两套现有资源组合已加载') >= 0;
        }, null, { timeout:20000 });
        await reviewPage.waitForTimeout(750);
        const appearanceReview = await reviewPage.evaluate(() => {
            function visiblePixelCount(canvas) {
                const context = canvas.getContext('2d');
                const image = context.getImageData(0, 0, canvas.width, canvas.height).data;
                let visible = 0;
                for (let index = 3; index < image.length; index += 4) if (image[index] > 0) visible++;
                return visible;
            }
            return {
                malePixels:visiblePixelCount(document.getElementById('gym-review-male')),
                femalePixels:visiblePixelCount(document.getElementById('gym-review-female')),
                maleCanvasSize:[document.getElementById('gym-review-male').width, document.getElementById('gym-review-male').height],
                femaleCanvasSize:[document.getElementById('gym-review-female').width, document.getElementById('gym-review-female').height],
                maleMeta:window.__gymAppearanceMeta && window.__gymAppearanceMeta['gym-review-male'],
                femaleMeta:window.__gymAppearanceMeta && window.__gymAppearanceMeta['gym-review-female'],
                sampleLabels:Array.from(document.querySelectorAll('[data-sample]')).map(node => node.dataset.sample),
                notice:document.querySelector('.gym-review-header p').textContent
            };
        });
        const motionPage = await browser.newPage({ viewport:{ width:1024, height:576 } });
        await motionPage.emulateMedia({ reducedMotion:'no-preference' });
        const motionPageErrors = [];
        const motionFailedRequests = [];
        motionPage.on('pageerror', error => motionPageErrors.push(error && error.message ? error.message : String(error)));
        motionPage.on('requestfailed', request => {
            const failure = request.failure();
            const text = request.url() + ' :: ' + (failure && failure.errorText || 'failed');
            if (request.resourceType() === 'image' && failure && failure.errorText === 'net::ERR_ABORTED') return;
            motionFailedRequests.push(text);
        });
        await installGymAssetRoute(motionPage);
        await motionPage.bringToFront();
        await motionPage.goto(serverResult.origin + '/modules/gym/dev/motion-review.html', { waitUntil:'load' });
        await motionPage.waitForFunction(() => window.__gymMotionReviewResult
            && (window.__gymMotionReviewResult.passed || window.__gymMotionReviewResult.error), null, { timeout:60000 });
        const motionBefore = await motionPage.evaluate(() => {
            function visiblePixelCount(canvas) {
                const context = canvas.getContext('2d');
                const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
                let visible = 0;
                for (let index = 3; index < pixels.length; index += 4) if (pixels[index] > 0) visible++;
                return visible;
            }
            const canvases = Array.from(document.querySelectorAll('.gym-motion-canvas'));
            return {
                result:window.__gymMotionReviewResult,
                labels:Array.from(document.querySelectorAll('[data-motion-sample]')).map(node => node.dataset.motionSample),
                canvases:canvases.map(canvas => ({
                    width:canvas.width,
                    height:canvas.height,
                    pixels:visiblePixelCount(canvas)
                })),
                states:(window.__gymMotionReviewHandles || []).map(handle => handle.debugState())
            };
        });
        await motionPage.waitForTimeout(700);
        const motionAfter = await motionPage.evaluate(() =>
            (window.__gymMotionReviewHandles || []).map(handle => handle.debugState()));
        const motionReview = {
            before:motionBefore,
            after:motionAfter,
            bothFramesAdvanced:motionBefore.states.length === 2 && motionAfter.length === 2
                && motionBefore.states.every((state, index) => motionAfter[index].frameIndex !== state.frameIndex),
            notice:await motionPage.locator('#gym-motion-review-state').textContent()
        };
        const gymMotionReviewScreenshot = path.join(visualOutputDir, 'gym-motion-review.png');
        await motionPage.screenshot({ path:gymMotionReviewScreenshot, fullPage:true });
        const output = {
            browser:'edge',
            executablePath,
            viewport:panelViewport.width + 'x' + panelViewport.height,
            screenshots:{ gymPanelScreenshot, gymMotionReviewScreenshot, gymEquippedCurrentScreenshot },
            qa,
            appearanceReview,
            motionReview,
            pageErrors,
            failedRequests,
            reviewPageErrors,
            reviewFailedRequests,
            motionPageErrors,
            motionFailedRequests
        };
        process.stdout.write(JSON.stringify(output, null, 2) + '\n');
        if (!qa.passed || !equippedCanvasDataUrl.startsWith('data:image/png;base64,')
                || pageErrors.length || failedRequests.length || reviewPageErrors.length
                || reviewFailedRequests.length || motionPageErrors.length || motionFailedRequests.length
                || appearanceReview.malePixels < 1000 || appearanceReview.femalePixels < 1000
                || !motionReview.before.result.passed || motionReview.before.canvases.length !== 2
                || motionReview.before.canvases.some(canvas => canvas.pixels < 1000)
                || !motionReview.bothFramesAdvanced) process.exitCode = 1;
    } finally {
        if (browser) await browser.close();
        serverResult.server.close();
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exitCode = 1;
});
