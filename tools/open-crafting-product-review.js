#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const REVIEW_DATA = path.join(ROOT, 'tmp', 'crafting-product-review', 'review-data.json');
const REVIEW_PROFILE = path.join(ROOT, 'tmp', 'crafting-product-review', 'review-profile');
const REVIEW_DECISIONS = path.join(ROOT, 'tmp', 'crafting-product-review', 'crafting-product-review-decisions.json');
const { startServer, stopServer } = require(path.join(ROOT, 'launcher', 'perf', 'lib', 'server'));

function findEdge() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : ''
    ];
    const found = candidates.find(candidate => candidate && fs.existsSync(candidate));
    if (!found) throw new Error('Microsoft Edge not found');
    return found;
}

async function main() {
    if (!fs.existsSync(REVIEW_DATA)) {
        throw new Error('review data missing; run: node tools/build-crafting-product-review.js');
    }
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const { chromium } = require(PLAYWRIGHT);
    const server = await startServer(ROOT, 0);
    let context = null;
    try {
        fs.mkdirSync(REVIEW_PROFILE, { recursive: true });
        context = await chromium.launchPersistentContext(REVIEW_PROFILE, {
            executablePath: findEdge(),
            headless: false,
            viewport: { width: 1500, height: 940 },
            acceptDownloads: true
        });
        const page = context.pages()[0] || await context.newPage();
        page.on('download', async download => {
            await download.saveAs(REVIEW_DECISIONS);
            console.log('[product-review] decisions saved: ' + path.relative(ROOT, REVIEW_DECISIONS));
            await page.evaluate(savedPath => {
                window.dispatchEvent(new CustomEvent('review-export-saved', { detail: savedPath }));
            }, path.relative(ROOT, REVIEW_DECISIONS).replace(/\\/g, '/'));
        });
        const data = encodeURIComponent('/tmp/crafting-product-review/review-data.json');
        await page.goto(server.url + 'launcher/web/modules/crafting-product-review/dev/review.html?data=' + data, { waitUntil: 'load' });
        console.log('[product-review] review window opened; close Edge to stop the local server.');
        const browser = context.browser();
        await new Promise(resolve => browser.on('disconnected', resolve));
        context = null;
    } finally {
        if (context) await context.close();
        await stopServer(server);
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
