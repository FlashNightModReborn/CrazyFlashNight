#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
const { chromium } = require(path.join(root, 'launcher', 'perf', 'node_modules', 'playwright'));
const { startServer } = require(path.join(root, 'tools', 'lib', 'stage-select-dev-server'));

const portraits = [
    { gender:'male', hair:'发型-男式-黑中分头', face:'男变装-基本脸型',
        equipment:{ '上装装备':'浅灰背心', '下装装备':'破牛仔裤', '脚部装备':'黑色条纹运动鞋' } },
    { gender:'male', hair:'发型-男式-黑中分头', face:'男变装-基本脸型',
        equipment:{ '上装装备':'黑色立领校服', '下装装备':'黑色校服裤子', '脚部装备':'蓝白相间校鞋' } }
];
const currentPortrait = {
    gender:'male', hair:'发型-男式-黑暴走头', face:'男变装-基本脸型',
    equipment:{
        '颈部装备':'新手军牌', '脚部装备':'新手皮鞋', '手部装备':'黑色皮手套',
        '头部装备':'新手面具', '刀':'锤子',
        '下装装备':'咖啡色多包裤', '上装装备':'新手衣服'
    }
};
const stations = [
    { id:'dummy', label:'木人桩', frames:127 },
    { id:'dumbbell', label:'哑铃', frames:77 },
    { id:'squat', label:'深蹲', frames:75 }
];

function edgePath() {
    const paths = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    const found = paths.find(fs.existsSync);
    if (!found) throw new Error('Edge executable unavailable');
    return found;
}

async function main() {
    const output = path.resolve(process.env.CF7_GYM_MOTION_OUTPUT
        || path.join(root, 'tmp', 'gym-motion-full'));
    fs.mkdirSync(output, { recursive:true });
    const server = await startServer(path.join(root, 'launcher', 'web'));
    const browser = await chromium.launch({ executablePath:edgePath(), headless:true });
    const results = [];
    try {
        const page = await browser.newPage({ viewport:{ width:1024, height:576 } });
        await page.emulateMedia({ reducedMotion:'no-preference' });
        const errors = [];
        page.on('pageerror', error => errors.push(String(error && error.message || error)));
        await page.goto(server.origin + '/modules/gym/dev/motion-review.html', { waitUntil:'load' });
        await page.waitForFunction(() => window.__gymMotionReviewResult
            && (window.__gymMotionReviewResult.passed || window.__gymMotionReviewResult.error),
        null, { timeout:60000 });
        for (const station of stations) {
            const before = await page.evaluate(async input => {
                (window.__gymMotionReviewHandles || []).forEach(handle => handle.destroy());
                window.__gymMotionReviewHandles = [];
                const hosts = Array.from(document.querySelectorAll('.motion-canvas-host'));
                const statuses = document.querySelectorAll('.motion-status');
                statuses.forEach(status => status.remove());
                const prepared = await Promise.all(input.portraits.map(portrait =>
                    GymMotionRenderer.preparePortrait(portrait, input.station.id)));
                if (prepared.some(value => value !== true)) throw new Error('portrait not prepared');
                const handles = hosts.map((host, index) => GymMotionRenderer.create(host, {
                    stationId:input.station.id, portrait:input.portraits[index]
                }));
                window.__gymMotionReviewHandles = handles;
                document.querySelector('h1').textContent = input.station.label + '动作与角色分层样例';
                document.getElementById('gym-motion-review-state').textContent =
                    input.station.frames + ' 帧循环 · 两套装备';
                function visiblePixels(canvas) {
                    const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
                    let count = 0;
                    for (let index = 3; index < pixels.length; index += 4) if (pixels[index] > 0) count++;
                    return count;
                }
                return {
                    prepared,
                    states:handles.map(handle => handle.debugState()),
                    pixels:hosts.map(host => visiblePixels(host.querySelector('canvas')))
                };
            }, { station, portraits });
            await page.waitForTimeout(500);
            const after = await page.evaluate(() =>
                window.__gymMotionReviewHandles.map(handle => handle.debugState()));
            const screenshot = path.join(output, station.id + '.png');
            await page.screenshot({ path:screenshot, fullPage:true });
            const current = await page.evaluate(async input => {
                const prepared = await GymMotionRenderer.preparePortrait(input.portrait, input.station.id);
                if (!prepared || !GymMotionRenderer.canRenderPortrait(input.portrait, input.station.id)) {
                    return { prepared:false, pixels:0 };
                }
                const host = document.createElement('div');
                host.id = 'gym-current-outfit-host';
                host.style.cssText = 'position:fixed;top:166px;left:23px;width:472px;height:300px;z-index:100;background:#131d27';
                document.body.appendChild(host);
                const handle = GymMotionRenderer.create(host, {
                    stationId:input.station.id, portrait:input.portrait
                });
                window.__gymCurrentOutfitHandle = handle;
                const canvas = host.querySelector('canvas');
                const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
                let visible = 0;
                for (let index = 3; index < pixels.length; index += 4) if (pixels[index] > 0) visible++;
                return { prepared:true, pixels:visible, state:handle.debugState() };
            }, { station, portrait:currentPortrait });
            const currentScreenshot = path.join(output, station.id + '-current-outfit.png');
            if (current.prepared) {
                await page.locator('#gym-current-outfit-host canvas').screenshot({ path:currentScreenshot });
            }
            await page.evaluate(() => {
                if (window.__gymCurrentOutfitHandle) window.__gymCurrentOutfitHandle.destroy();
                window.__gymCurrentOutfitHandle = null;
                const host = document.getElementById('gym-current-outfit-host');
                if (host) host.remove();
            });
            const passed = before.prepared.every(Boolean)
                && before.pixels.every(value => value > 1000)
                && before.states.every(value => value.frameCount === station.frames && value.frameRate === 30)
                && after.every((value, index) => value.frameIndex !== before.states[index].frameIndex)
                && current.prepared && current.pixels > 1000
                && current.state.frameCount === station.frames
                && errors.length === 0;
            results.push({ station:station.id, passed, pixels:before.pixels,
                currentOutfitPixels:current.pixels,
                before:before.states.map(value => value.frameIndex),
                after:after.map(value => value.frameIndex), screenshot, currentScreenshot });
        }
        const activeBeforeClose = await page.evaluate(() => GymMotionRenderer.getDebugStats().activeInstances);
        const activeAfterClose = await page.evaluate(() => {
            window.__gymMotionReviewHandles.forEach(handle => handle.destroy());
            return GymMotionRenderer.getDebugStats().activeInstances;
        });
        const report = { passed:results.every(result => result.passed)
            && activeBeforeClose === 2 && activeAfterClose === 0,
            results, activeBeforeClose, activeAfterClose, errors };
        process.stdout.write(JSON.stringify(report, null, 2) + '\n');
        if (!report.passed) process.exitCode = 1;
    } finally {
        await browser.close();
        server.server.close();
    }
}

main().catch(error => {
    console.error(error && error.stack || String(error));
    process.exitCode = 1;
});
