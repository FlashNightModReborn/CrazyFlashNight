'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const { startServer } = require('./lib/stage-select-dev-server');
const perfRoot = path.resolve(__dirname, '../launcher/perf');
const { chromium } = require(require.resolve('playwright', { paths: [perfRoot, __dirname] }));

async function iconBox(icon, size) {
    await icon.waitFor();
    const box = await icon.boundingBox();
    assert.ok(box, 'icon is visible');
    assert.equal(box.width, size);
    assert.equal(box.height, size);
}

async function main() {
    const webRoot = path.resolve(__dirname, '../launcher/web');
    const { server, origin } = await startServer(webRoot);
    let browser;
    try {
        browser = await chromium.launch({ channel: 'chrome' });
        const page = await browser.newPage({ viewport: { width: 1050, height: 610 } });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.goto(origin + '/modules/armory/dev/harness.html');
        const rifle = page.locator('.arm-item').filter({ hasText: 'AK47火麒麟' });
        const sword = page.locator('.arm-item').filter({ hasText: '秋月' });
        const layered = rifle.locator('.arm-iconwrap.loaded > .cfn-layered-icon');
        await iconBox(sword.locator('.arm-iconwrap.loaded > img'), 44);
        await iconBox(layered, 44);
        const phases = await layered.evaluate(async node => {
            const entry = Icons.entry(node.dataset.iconLayeredName);
            const layer = node.querySelector('[data-icon-layer-index]');
            const seen = new Set();
            const deadline = performance.now() + 3000;
            while (seen.size < entry.nestedAnimation.layers[0].frames.length && performance.now() < deadline) {
                await new Promise(requestAnimationFrame);
                if (layer.complete && layer.naturalWidth) seen.add(layer.currentSrc);
            }
            return { seen: seen.size, frameCount: entry.nestedAnimation.layers[0].frames.length,
                border: getComputedStyle(layer).borderTopWidth, background: getComputedStyle(layer).backgroundColor };
        });
        assert.ok(phases.frameCount > 1);
        assert.equal(phases.seen, phases.frameCount);
        assert.equal(phases.border, '0px');
        assert.equal(phases.background, 'rgba(0, 0, 0, 0)');

        // Exercise the material slot with the same production layered representation.
        await page.evaluate(() => { MATS[0].icon = RECIPES['武器合成'][1].output.icon; });
        await rifle.click();
        await iconBox(page.locator('.arm-bp-fg .arm-iconwrap.loaded > .cfn-layered-icon'), 88);
        await page.waitForFunction(() => {
            const drawing = document.querySelector('.arm-bp-art');
            return drawing && drawing.complete && drawing.naturalWidth > 0;
        });
        await iconBox(page.locator('.arm-req-icon .arm-iconwrap.loaded > .cfn-layered-icon'), 24);
        await iconBox(page.locator('.arm-req-icon .arm-iconwrap.loaded > img').first(), 24);
        await sword.click();
        await iconBox(page.locator('.arm-bp-fg .arm-iconwrap.loaded > img'), 88);
        assert.deepEqual(errors, []);
        console.log('Armory icons passed: 44/88/24 px, ' + phases.seen + ' animation frames.');
    } finally {
        try { if (browser) await browser.close(); }
        finally { server.close(); }
    }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
