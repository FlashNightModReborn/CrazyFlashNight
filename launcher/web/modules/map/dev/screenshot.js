#!/usr/bin/env node
'use strict';

// 一次性 UI 评估 + 红点回归视觉：枚举几种 page + lock + taskNpc 组合，输出 PNG。
// 输出目录放在 repo/tmp 下，避免把调试截图落进源码目录。

const path = require('path');
const fs = require('fs');

const repoRoot = path.resolve(__dirname, '..', '..', '..', '..', '..');
const playwrightModule = path.join(repoRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const { startServer, stopServer } = require(path.join(repoRoot, 'launcher', 'perf', 'lib', 'server'));
const { chromium } = require(playwrightModule);

const outDir = path.join(repoRoot, 'tmp', 'map-red-dot-shots');
const scenarios = [
    { name: 'base-default', query: 'page=base' },
    { name: 'faction-all-unlocked', query: 'page=faction' },
    { name: 'base-with-quests', query: 'page=base&taskNpcs=base_lobby,merc_bar,firing_range' },
    { name: 'faction-with-quests', query: 'page=faction&taskNpcs=firing_range,fallen_bar' },
    { name: 'faction-locked-spoiler', query: 'page=base&taskNpcs=firing_range,warlord_base&lockedGroups=warlord,rock,blackiron,fallen' },
    { name: 'task-stage-select', query: 'page=faction&currentHotspotId=rock_park&taskNpcs=rock_park' }
];

(async () => {
    fs.mkdirSync(outDir, { recursive: true });
    const serverHandle = await startServer(repoRoot, 0);
    const browser = await chromium.launch();
    const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();

    page.on('pageerror', err => console.error('[pageerror]', err.message));
    page.on('console', msg => {
        if (msg.type() === 'error') console.error('[console.error]', msg.text());
    });
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({
        status: 204,
        headers: { 'access-control-allow-origin': '*' },
        body: ''
    }));

    try {
        for (const sc of scenarios) {
            const url = serverHandle.url + 'launcher/web/modules/map/dev/harness.html?' + sc.query;
            await page.goto(url, { waitUntil: 'load' });
            await page.waitForSelector('.map-panel', { state: 'visible', timeout: 5000 });
            await page.waitForTimeout(900);
            const outPath = path.join(outDir, 'shot-' + sc.name + '.png');
            await page.screenshot({ path: outPath, fullPage: false });
            console.log('saved:', outPath);
        }
    } finally {
        await browser.close();
        await stopServer(serverHandle);
    }
})().catch(e => {
    console.error(e && e.stack ? e.stack : String(e));
    process.exit(1);
});
