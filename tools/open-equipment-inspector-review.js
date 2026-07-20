#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const REVIEW_DATA = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'review-data.json');
const REVIEW_PROFILE = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'review-profile');
const REVIEW_DECISIONS = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'equipment-inspector-review-decisions.json');
const { startServer, stopServer } = require(path.join(ROOT, 'launcher', 'perf', 'lib', 'server'));
const reviewBuild = require(path.join(ROOT, 'tools', 'build-equipment-inspector-review.js'));

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
        throw new Error('review data missing; run: node tools/build-equipment-inspector-review.js');
    }
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const dataset = JSON.parse(fs.readFileSync(REVIEW_DATA, 'utf8'));
    if (dataset.partial) throw new Error('partial review data cannot be used for formal acceptance; rebuild without --limit');
    const loaded = reviewBuild.loadEquipmentDefinitions();
    const currentDigest = reviewBuild.sourceDigest(loaded.sourceFiles);
    if (dataset.sourceDigest !== currentDigest) {
        throw new Error('stale review data: actual=' + dataset.sourceDigest + ' current=' + currentDigest +
            '; rerun node tools/build-equipment-inspector-review.js');
    }
    const verifiedArtifactCount = reviewBuild.verifyReviewArtifacts(dataset.items || [], ROOT);
    const currentReviewDigest = reviewBuild.computeReviewDigest(dataset.sourceDigest, dataset.items || []);
    if (!dataset.reviewDigest || dataset.reviewDigest !== currentReviewDigest) {
        throw new Error('review data evidence digest mismatch: actual=' + dataset.reviewDigest +
            ' computed=' + currentReviewDigest + '; rerun the full builder');
    }
    if (process.argv.includes('--check')) {
        console.log('[equipment-inspector-review] data verified: sourceDigest=' + currentDigest +
            ' reviewDigest=' + currentReviewDigest + ' definitions=' + dataset.counts.definitionCount +
            ' required=' + dataset.counts.requiredBranchCount + ' artifactRefs=' + verifiedArtifactCount);
        return;
    }
    const { chromium } = require(PLAYWRIGHT);
    const server = await startServer(ROOT, 0);
    let context = null;
    try {
        fs.mkdirSync(REVIEW_PROFILE, { recursive: true });
        context = await chromium.launchPersistentContext(REVIEW_PROFILE, {
            executablePath: findEdge(),
            headless: false,
            viewport: { width: 1550, height: 940 },
            acceptDownloads: true
        });
        const page = context.pages()[0] || await context.newPage();
        page.on('download', async download => {
            await download.saveAs(REVIEW_DECISIONS);
            console.log('[equipment-inspector-review] decisions saved: ' + path.relative(ROOT, REVIEW_DECISIONS));
            await page.evaluate(savedPath => {
                window.dispatchEvent(new CustomEvent('review-export-saved', { detail:savedPath }));
            }, path.relative(ROOT, REVIEW_DECISIONS).replace(/\\/g, '/'));
        });
        const data = encodeURIComponent('/tmp/equipment-inspector-review/review-data.json');
        await page.goto(server.url + 'launcher/web/modules/equipment-inspector-review/dev/review.html?data=' + data, { waitUntil: 'load' });
        console.log('[equipment-inspector-review] formal full-definition review opened; close Edge to stop the local server.');
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
