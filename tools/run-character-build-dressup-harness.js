#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const HARNESS_PATH = 'launcher/web/modules/dressup/dev/character-build-combination-harness.html';
const FIXTURE_PATH = 'launcher/web/modules/dressup/dev/character-build-combination-fixture.js';
const MANIFEST_PATH = 'launcher/web/assets/dressup/manifest.json';
const shotArg = process.argv.find(arg => arg.startsWith('--shot-dir='));
const checks = [];

function check(ok, title, detail) {
    const result = {ok: Boolean(ok), title, detail: detail == null ? '' : String(detail)};
    checks.push(result);
    if (!result.ok) throw new Error(title + (result.detail ? ': ' + result.detail : ''));
}

function read(rel) {
    return fs.readFileSync(path.join(ROOT, rel), 'utf8').replace(/^\uFEFF/, '');
}

function loadManifest() {
    return JSON.parse(read(MANIFEST_PATH));
}

function selectedFixtureNames(source) {
    const match = source.match(/var equipment = \{([\s\S]*?)\n    \};/);
    if (!match) return [];
    return Array.from(match[1].matchAll(/:\s*'([^']+)'/g), item => item[1]);
}

function staticAudit() {
    const manifest = loadManifest();
    const fixture = read(FIXTURE_PATH);
    const harness = read(HARNESS_PATH);
    const renderer = read('launcher/web/modules/dressup-doll-renderer.js');
    const pose = read('launcher/web/modules/character-build/character-build-pose.js');
    const controller = read('launcher/web/modules/character-build.js');
    const registry = read('launcher/web/modules/panels-lazy-registry.js');
    const selected = selectedFixtureNames(fixture);
    const neck = Object.values(manifest.items).filter(item => item.use === '颈部装备');
    const emptyNeck = neck.filter(item => !item.dressup
        && Object.keys(item.fieldsByGender || {}).length === 0);
    const battle = manifest.rigs && manifest.rigs.battle;
    let grenadeHolders = 0;
    Object.values(battle && battle.genders || {}).forEach(gender => {
        Object.values(gender.states || {}).forEach(state => {
            grenadeHolders += (state.holders || []).filter(holder => holder.field === '手雷_装扮').length;
        });
    });

    check((harness.match(/<canvas\b/g) || []).length === 1,
        'combination harness declares exactly one Canvas');
    check(harness.includes('DressupDollRenderer.create(canvas')
        && harness.includes('DressupDollRenderer.buildStateFromEquipment')
        && harness.includes('CharacterBuildPose.select')
        && harness.includes('fitFields: BODY_FIT_FIELDS')
        && harness.includes('drawFields: CHARACTER_DRAW_FIELDS'),
        'harness consumes the shared pose selector and renderer camera contract');
    check(pose.includes("case '手枪2':")
        && pose.includes("pose('双枪站立', '双枪')")
        && controller.includes('Pose.select(equipment, this._selectedTarget)'),
        'production controller delegates pose choice to the narrow pure selector');
    check(!registry.includes('character-build-combination-harness')
        && !registry.includes('character-build-combination-fixture'),
        'B0 dressup spike remains outside every production lazy route');
    check(renderer.includes('setPixelRatio: function')
        && renderer.includes('setAnimationEnabled: function')
        && renderer.includes('destroy: function'),
        'current renderer exposes pixel ratio, motion, and destroy lifecycle controls');
    check(neck.length === 99 && emptyNeck.length === 99,
        'all 99 neck entries have no current visual projection',
        JSON.stringify({neck: neck.length, emptyNeck: emptyNeck.length}));
    check(grenadeHolders === 2,
        'battle rig exposes one grenade holder per gender',
        grenadeHolders);
    ['男','女'].forEach(gender => {
        const states = battle.genders[gender].states;
        ['空手站立','长枪站立','手枪站立','手枪2站立','双枪站立','兵器站立','手雷站立']
            .forEach(stateLabel => check(Boolean(states[stateLabel]),
                gender + ' battle rig exposes current state ' + stateLabel));
    });
    check(selected.length === 11 && selected.every(name => manifest.items[name]),
        'fixture references eleven real manifest items', selected.join(' | '));

    selected.filter(name => name !== 'A兵团精致项链' && name !== '米色高腰背心').forEach(name => {
        const item = manifest.items[name];
        const branches = Object.values(item.fieldsByGender || {});
        const keys = branches.flatMap(fields => Object.values(fields || {}));
        check(keys.length > 0 && keys.every(key => manifest.skinKeys[key] && manifest.skinKeys[key].export),
            name + ' has renderable baked projection entries');
    });
    const grenade = manifest.items['战术核弹手雷'];
    check(grenade.fieldsByGender['男']['手雷_装扮']
        && grenade.fieldsByGender['女']['手雷_装扮'],
        'grenade asset and gender branches exist for the battle holder');
    const vest = manifest.items['米色高腰背心'];
    ['上臂','左下臂','右下臂'].forEach(field => {
        const key = vest.fieldsByGender['女'][field];
        const skin = manifest.skinKeys[key];
        check(skin && skin.covered === false && !skin.export && !skin.compatAlias,
            'female beige-vest ' + field + ' remains uncovered for same-gender holder basic fallback',
            JSON.stringify({key, skin}));
    });
}

function edgeExecutable() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
            'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files',
            'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(candidate => candidate && fs.existsSync(candidate));
}

function mimeType(file) {
    const extension = path.extname(file).toLowerCase();
    if (extension === '.html') return 'text/html; charset=utf-8';
    if (extension === '.js') return 'text/javascript; charset=utf-8';
    if (extension === '.json') return 'application/json; charset=utf-8';
    if (extension === '.png') return 'image/png';
    if (extension === '.webp') return 'image/webp';
    return 'application/octet-stream';
}

function createServer() {
    return new Promise((resolve, reject) => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB_ROOT, pathname));
            const relative = path.relative(WEB_ROOT, file);
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
                response.writeHead(200, {'Content-Type': mimeType(file)});
                response.end(data);
            });
        });
        server.on('error', reject);
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function state(page) {
    return page.evaluate(() => CharacterBuildDressupHarness.debugState());
}

async function settle(page, options) {
    const expectedFailure = options && options.expectedFailure;
    await page.waitForFunction(expectFailure => {
        const value = CharacterBuildDressupHarness.debugState();
        if (!value || !value.meta || value.meta.pendingImages !== 0) return false;
        return expectFailure ? value.meta.failedImages > 0 : true;
    }, Boolean(expectedFailure), {timeout: 20000});
    await page.waitForTimeout(80);
    return state(page);
}

async function renderScenario(page, scenario, gender) {
    await page.evaluate(({nextScenario, nextGender}) => {
        CharacterBuildDressupHarness.renderScenario(nextScenario, nextGender);
    }, {nextScenario: scenario, nextGender: gender});
    return settle(page);
}

async function canvasProbe(page) {
    return page.evaluate(() => {
        const canvas = document.getElementById('doll-canvas');
        const context = canvas.getContext('2d');
        const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
        let alphaPixels = 0;
        let hash = 2166136261;
        for (let index = 0; index < pixels.length; index += 4) {
            const alpha = pixels[index + 3] || 0;
            if (alpha > 8) alphaPixels++;
            hash ^= pixels[index] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= pixels[index + 1] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= pixels[index + 2] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= alpha;
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return {width: canvas.width, height: canvas.height, alphaPixels, hash};
    });
}

function assertArmorProjection(value, excludedSlot) {
    ['head', 'upper', 'hands', 'lower', 'feet'].forEach(slot => {
        if (slot === excludedSlot) return;
        check(value.evidence.armor[slot].projected && value.evidence.armor[slot].drawn,
            slot + ' projection remains drawn' + (excludedSlot ? ' while ' + excludedSlot + ' is missing' : ''),
            JSON.stringify(value.evidence.armor[slot]));
    });
    check(!value.evidence.armor.neck.projected && !value.evidence.armor.neck.drawn,
        'neck remains a truthful zero-projection slot');
}

function assertCharacterCamera(value, label) {
    const camera = value.camera || {};
    const state = value.state || {};
    const fitFields = state.fitFields || [];
    const drawFields = state.drawFields || [];
    check(fitFields.includes('身体') && fitFields.includes('脚')
        && !fitFields.some(field => /装扮$/.test(field)),
        label + ' camera fit is owned by body and armor fields', JSON.stringify(fitFields));
    check(drawFields.includes('身体') && drawFields.includes('长枪_装扮')
        && drawFields.includes('手枪2_装扮') && drawFields.includes('刀_装扮')
        && drawFields.includes('手雷_装扮'),
        label + ' camera still draws body and weapon fields', JSON.stringify(drawFields));
    check(camera.fitHeightRatio >= 0.6
        && camera.centerXRatio >= 0.42 && camera.centerXRatio <= 0.58,
        label + ' person remains the centered visual subject',
        JSON.stringify(camera));
}

async function saveShot(page, name) {
    if (!shotArg) return;
    const directory = path.resolve(shotArg.slice('--shot-dir='.length));
    fs.mkdirSync(directory, {recursive: true});
    await page.screenshot({path: path.join(directory, name), fullPage: true});
}

async function runBrowserAudit(browser, port) {
    const page = await browser.newPage({
        viewport: {width: 1024, height: 576},
        reducedMotion: 'reduce',
        deviceScaleFactor: 1
    });
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    try {
        await page.goto('http://127.0.0.1:' + port
            + '/modules/dressup/dev/character-build-combination-harness.html',
        {waitUntil: 'load'});
        await page.waitForFunction(() => window.__qaReady === true || window.__qaError, null,
            {timeout: 20000});
        check(!await page.evaluate(() => window.__qaError || ''),
            'combination harness loads without bootstrap error',
            await page.evaluate(() => window.__qaError || ''));

        const male = await settle(page);
        const maleProbe = await canvasProbe(page);
        check(male.canvasCount === 1 && male.active,
            'male full combination uses one live Canvas', JSON.stringify(male.canvas));
        check(male.gender === '男' && male.state.rig === 'battle'
            && male.state.stateLabel === '长枪站立' && male.state.attackMode === '长枪',
            'male fixture resolves the long-gun battle pose', JSON.stringify(male.state));
        check(male.meta.holders > 15 && male.meta.failedImages === 0,
            'male pose renders its complete holder set without failed assets',
            JSON.stringify(male.meta));
        check(male.reducedMotion && !male.animationEnabled
            && male.listenerCounts.resize === 1 && male.listenerCounts.motion === 1,
            'initial reduced-motion and lifecycle listeners are explicit',
            JSON.stringify(male));
        check(male.facts.neckItems === 99
            && male.facts.neckItemsWithoutProjection === 99
            && male.facts.grenadeBattleHolders === 2,
            'browser harness exposes the neck and grenade manifest facts',
            JSON.stringify(male.facts));
        assertArmorProjection(male);
        assertCharacterCamera(male, 'male');
        check(male.evidence.longGun.drawn,
            'male long-gun projection is present in the combined draw');
        check(male.state.keyMap['手雷_装扮']
            && male.holderFields.indexOf('手雷_装扮') < 0
            && !male.evidence.grenade.drawn,
            'inactive long-gun pose keeps grenade data without drawing the grenade holder');
        check(maleProbe.alphaPixels > 2000,
            'male combined Canvas contains visible projected pixels', JSON.stringify(maleProbe));
        await saveShot(page, 'character-build-dressup-male-1024x576.png');

        const female = await renderScenario(page, 'longGun', '女');
        const femaleProbe = await canvasProbe(page);
        check(female.canvasCount === 1 && female.gender === '女',
            'female full combination reuses the same single Canvas');
        assertArmorProjection(female);
        assertCharacterCamera(female, 'female');
        check(female.evidence.longGun.drawn && female.meta.failedImages === 0,
            'female long-gun pose resolves all selected projections');
        check(femaleProbe.alphaPixels > 2000 && femaleProbe.hash !== maleProbe.hash,
            'female projection is visible and differs from male projection',
            JSON.stringify({male: maleProbe, female: femaleProbe}));
        await saveShot(page, 'character-build-dressup-female-1024x576.png');

        const poseCases = [
            ['longGun','长枪站立','长枪'],
            ['dualPistol','双枪站立','双枪'],
            ['pistol','手枪站立','手枪'],
            ['pistol2','手枪2站立','手枪2'],
            ['blade','兵器站立','兵器'],
            ['empty','空手站立','空手'],
            ['grenadeCombined','手雷站立','手雷']
        ];
        for (const gender of ['男','女']) {
            for (const poseCase of poseCases) {
                const rendered = await renderScenario(page, poseCase[0], gender);
                const probe = await canvasProbe(page);
                check(rendered.canvasCount === 1
                    && rendered.gender === gender
                    && rendered.state.stateLabel === poseCase[1]
                    && rendered.state.attackMode === poseCase[2],
                    gender + '/' + poseCase[0] + ' resolves the shared selector state',
                    JSON.stringify(rendered.state));
                check(rendered.meta.pendingImages === 0
                    && rendered.meta.failedImages === 0
                    && probe.alphaPixels > 2000,
                    gender + '/' + poseCase[0] + ' renders visible pixels without asset failure',
                    JSON.stringify({meta:rendered.meta, probe}));
                if (poseCase[0] === 'dualPistol') {
                    check(rendered.holderFields.includes('手枪_装扮')
                        && rendered.holderFields.includes('手枪2_装扮'),
                        gender + ' dual-pistol state exposes both current holders',
                        rendered.holderFields.join('|'));
                }
                if (poseCase[0] === 'grenadeCombined') {
                    check(rendered.holderFields.includes('手雷_装扮')
                        && rendered.evidence.grenade.drawn,
                        gender + ' grenade-ready state exposes and draws the grenade holder',
                        JSON.stringify(rendered.evidence.grenade));
                }
                await saveShot(page, 'character-build-dressup-'
                    + (gender === '女' ? 'female-' : 'male-')
                    + poseCase[0] + '-1024x576.png');
            }
        }

        const pistol = await renderScenario(page, 'pistol2', '男');
        check(pistol.state.stateLabel === '手枪2站立'
            && pistol.state.attackMode === '手枪2'
            && pistol.state.keyMap['手枪2_装扮']
            && pistol.evidence.pistol.drawn,
            'pistol-2 pose draws the mapped secondary-pistol holder',
            JSON.stringify(pistol.state));

        const blade = await renderScenario(page, 'blade', '男');
        check(blade.state.stateLabel === '兵器站立'
            && blade.state.attackMode === '兵器'
            && blade.state.keyMap['刀_装扮']
            && blade.evidence.blade.drawn,
            'blade pose draws the mapped blade holder',
            JSON.stringify(blade.state));

        const grenadeReady = await renderScenario(page, 'grenadeCombined', '男');
        check(grenadeReady.state.keyMap['手雷_装扮']
            && grenadeReady.holderFields.includes('手雷_装扮')
            && grenadeReady.evidence.grenade.drawn,
            'combined grenade path uses the real battle holder rather than a product-direct placeholder');
        assertArmorProjection(grenadeReady);

        await page.evaluate(() => CharacterBuildDressupHarness.renderGrenadeProduct('男'));
        const grenadeProduct = await settle(page);
        check(grenadeProduct.meta.rig === 'product-direct'
            && grenadeProduct.meta.holders === 1
            && grenadeProduct.evidence.grenade.drawn,
            'the grenade baked asset itself renders through product-direct on the same Canvas',
            JSON.stringify(grenadeProduct.meta));

        const femaleFallback = await renderScenario(page, 'femaleArmFallback', '女');
        check(femaleFallback.state.stateLabel === '空手站立'
            && femaleFallback.meta.missing === 0
            && femaleFallback.meta.failedImages === 0
            && femaleFallback.evidence.femaleFallbackUpper.drawn,
            'female beige vest renders its body while uncovered arm skins resolve without missing parts',
            JSON.stringify(femaleFallback));
        ['上臂','左下臂','右下臂'].forEach(field => {
            const evidence = femaleFallback.evidence.armBasics[field];
            check(evidence.linkageIds.length > 0
                && evidence.linkageIds.every(key => key.startsWith('女变装-裸体'))
                && evidence.expectedUris.length > 0
                && evidence.drawnUris.length === evidence.expectedUris.length,
                'female beige-vest ' + field + ' draws the female naked holder basic',
                JSON.stringify(evidence));
        });
        await saveShot(page, 'character-build-dressup-female-arm-fallback-1024x576.png');

        const candidate = await renderScenario(page, 'candidate', '男');
        check(candidate.canvasCount === 1
            && candidate.state.keyMap['长枪_装扮']
            && candidate.evidence.candidate.drawn
            && !candidate.evidence.longGun.drawn,
            'candidate keyMap replaces the long-gun projection on the existing Canvas',
            JSON.stringify(candidate.evidence));
        const restored = await renderScenario(page, 'longGun', '男');
        check(restored.evidence.longGun.drawn && !restored.evidence.candidate.drawn,
            'candidate preview is reversible without creating another Canvas');
        const baselineHolders = restored.meta.holders;
        const baselineProbe = await canvasProbe(page);

        const armorSlots = ['head', 'upper', 'hands', 'lower', 'feet', 'neck'];
        for (const slot of armorSlots) {
            await page.evaluate(({slotId}) => {
                CharacterBuildDressupHarness.faultArmor(slotId, 'mapping-missing', '男');
            }, {slotId: slot});
            const fault = await settle(page);
            const probe = await canvasProbe(page);
            check(fault.canvasCount === 1 && fault.meta.holders === baselineHolders,
                slot + ' mapping fault preserves the single Canvas and holder capacity',
                JSON.stringify(fault.meta));
            check(await page.locator('.qa-slot').count() === 6,
                slot + ' mapping fault preserves all six armor slot affordances');
            if (slot === 'neck') {
                check(fault.fault.projectedFields.length === 0
                    && fault.meta.missing === 0
                    && !fault.evidence.armor.neck.projected,
                    'neck fault has no renderer field to degrade; static icon fallback is an expected UI-layer gap');
                assertArmorProjection(fault);
            } else {
                check(fault.fault.projectedFields.length > 0
                    && !fault.evidence.armor[slot].drawn,
                    slot + ' missing mapping removes only the selected projected asset',
                    JSON.stringify(fault.fault));
                assertArmorProjection(fault, slot);
            }
            check(probe.alphaPixels > Math.max(1200, baselineProbe.alphaPixels * 0.25),
                slot + ' missing mapping does not blank the remaining doll',
                JSON.stringify({baseline: baselineProbe.alphaPixels, fault: probe.alphaPixels}));
            check(await page.locator('img').count() === 0,
                slot + ' proves renderer has no built-in static-icon fallback (expected gap)');
        }

        for (const slot of ['head', 'upper', 'hands', 'lower', 'feet']) {
            await page.evaluate(({slotId}) => {
                CharacterBuildDressupHarness.faultArmor(slotId, 'asset-load', '女');
            }, {slotId: slot});
            const failed = await settle(page, {expectedFailure: true});
            check(failed.canvasCount === 1
                && failed.meta.holders === baselineHolders
                && failed.meta.failedImages > 0,
                slot + ' asset-load failure is reported and locally isolated',
                JSON.stringify(failed.meta));
            check(!failed.evidence.armor[slot].drawn,
                slot + ' failed asset is absent from the final draw');
            assertArmorProjection(failed, slot);
            check(await page.locator('img').count() === 0,
                slot + ' asset-load failure confirms per-slot icon fallback is not renderer-owned');
        }

        await renderScenario(page, 'longGun', '男');
        await page.evaluate(() => CharacterBuildDressupHarness.setPixelRatio(1));
        const beforeResize = await settle(page);
        await page.setViewportSize({width: 900, height: 640});
        await page.waitForFunction(sequence => {
            return CharacterBuildDressupHarness.debugState().renderSequence > sequence;
        }, beforeResize.renderSequence, {timeout: 5000});
        const resized = await settle(page);
        check(resized.canvasCount === 1
            && resized.canvas.width === Math.round(resized.canvas.clientWidth)
            && resized.canvas.height === Math.round(resized.canvas.clientHeight),
            'resize rerenders the same Canvas at pixel ratio 1',
            JSON.stringify(resized.canvas));

        await page.evaluate(() => CharacterBuildDressupHarness.setPixelRatio(2));
        const highDpi = await settle(page);
        check(highDpi.canvas.width === Math.round(highDpi.canvas.clientWidth * 2)
            && highDpi.canvas.height === Math.round(highDpi.canvas.clientHeight * 2),
            'setPixelRatio rebuilds backing dimensions without adding a Canvas',
            JSON.stringify(highDpi.canvas));

        await page.emulateMedia({reducedMotion: 'no-preference'});
        await page.waitForFunction(() => {
            const value = CharacterBuildDressupHarness.debugState();
            return !value.reducedMotion && value.animationEnabled && value.activeAnimationFrames > 0;
        }, null, {timeout: 5000});
        const motion = await state(page);
        check(motion.meta.animated && motion.activeAnimationFrames > 0,
            'normal motion schedules animation on the current renderer');

        await page.emulateMedia({reducedMotion: 'reduce'});
        await page.waitForFunction(() => {
            const value = CharacterBuildDressupHarness.debugState();
            return value.reducedMotion && !value.animationEnabled && value.activeAnimationFrames === 0;
        }, null, {timeout: 5000});
        const reduced = await state(page);
        check(reduced.activeAnimationFrames === 0,
            'reduced-motion cancels the renderer animation request');

        const beforeDestroy = reduced.renderSequence;
        await page.evaluate(() => CharacterBuildDressupHarness.destroy());
        const destroyed = await state(page);
        check(!destroyed.active
            && destroyed.canvasCount === 1
            && destroyed.listenerCounts.resize === 0
            && destroyed.listenerCounts.motion === 0
            && destroyed.activeAnimationFrames === 0,
            'destroy leaves one inert Canvas and releases every harness listener/RAF',
            JSON.stringify(destroyed));
        await page.setViewportSize({width: 1024, height: 576});
        await page.waitForTimeout(120);
        const afterDestroy = await state(page);
        check(afterDestroy.renderSequence === beforeDestroy,
            'resize after destroy cannot trigger another Canvas render',
            JSON.stringify({beforeDestroy, afterDestroy: afterDestroy.renderSequence}));

        check(pageErrors.length === 0,
            'browser run has no page errors', pageErrors.join(' | '));
        check(failedRequests.length === 0,
            'browser run has no failed network requests', failedRequests.join(' | '));
    } finally {
        await page.close();
    }
}

(async function main() {
    staticAudit();
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless: true});
    try {
        await runBrowserAudit(browser, server.address().port);
        const passed = checks.filter(result => result.ok).length;
        console.log('Character build dressup harness: ' + passed + '/' + checks.length + ' passed');
        if (shotArg) {
            console.log('Screenshots: ' + path.resolve(shotArg.slice('--shot-dir='.length)));
        }
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
