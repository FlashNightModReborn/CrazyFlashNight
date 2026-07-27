#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const REVIEW_DATA = path.join(ROOT, 'tmp', 'crafting-product-review', 'review-data.json');
const { startServer, stopServer } = require(path.join(ROOT, 'launcher', 'perf', 'lib', 'server'));
const EXPECTED_CRAFTING_DUAL_BLADES = ['輪舞', '黑煞', '炎寒对剑']
    .sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_CRAFTING_BLADE_SHEATHS = ['虎彻配鞘版', '血刀配鞘版', '黑铁剑配鞘', '血能源刃配鞘版']
    .sort((left, right) => left.localeCompare(right, 'zh-CN'));

function sameSet(actual, expected) {
    return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function slash(value) {
    return String(value).replace(/\\/g, '/');
}

function currentSourceDigest() {
    const hash = crypto.createHash('sha256');
    const craftingRoot = path.join(ROOT, 'data', 'crafting');
    const files = fs.readdirSync(craftingRoot)
        .filter(name => name.toLowerCase().endsWith('.json')).sort()
        .map(name => path.join(craftingRoot, name))
        .concat([
            path.join(ROOT, 'launcher', 'web', 'icons', 'manifest.json'),
            path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json'),
            path.join(ROOT, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js'),
            path.join(ROOT, 'launcher', 'web', 'modules', 'workbench-inspection-viewport.js'),
            path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector.js'),
            path.join(ROOT, 'launcher', 'web', 'modules', 'crafting-inspector.js'),
            path.join(ROOT, 'launcher', 'web', 'modules', 'crafting-product-review', 'dev', 'render-harness.html'),
            path.join(ROOT, 'tools', 'build-crafting-product-review.js')
        ]);
    fs.readdirSync(path.join(ROOT, 'data', 'items'))
        .filter(name => name.toLowerCase().endsWith('.xml')).sort()
        .forEach(name => files.push(path.join(ROOT, 'data', 'items', name)));
    files.forEach(filePath => {
        hash.update(slash(path.relative(ROOT, filePath)));
        hash.update(fs.readFileSync(filePath));
    });
    return hash.digest('hex').slice(0, 20);
}

function edge() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(candidate => fs.existsSync(candidate));
}

function argValue(name) {
    const index = process.argv.indexOf(name);
    return index >= 0 ? process.argv[index + 1] || '' : '';
}

async function main() {
    if (!fs.existsSync(REVIEW_DATA)) throw new Error('missing review data; run node tools/build-crafting-product-review.js --sample first');
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('missing Playwright dependency');
    const executablePath = edge();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const dataset = JSON.parse(fs.readFileSync(REVIEW_DATA, 'utf8'));
    const expectedSourceDigest = currentSourceDigest();
    if (dataset.sourceDigest !== expectedSourceDigest) {
        throw new Error('stale review data: actual=' + dataset.sourceDigest + ' current=' + expectedSourceDigest +
            '; rerun node tools/build-crafting-product-review.js');
    }
    const allowedFocusContext = {
        '头部装备': ['脸型'],
        '上装装备': [],
        '下装装备': [],
        '手部装备': [],
        '脚部装备': [],
        '颈部装备': []
    };
    let armorFocusCount = 0;
    let specializationContractCount = 0;
    let weaponContractCount = 0;
    const compositeNames = { 'dual-blade': [], 'blade-sheath': [] };
    dataset.items.forEach(item => item.candidates.forEach(candidate => {
        if (!candidate.uri || candidate.uri.indexOf('/') !== 0) throw new Error('candidate URI must be repo-root-relative: ' + item.name + ' ' + candidate.id);
        const filePath = path.resolve(ROOT, candidate.uri.replace(/^\/+/, ''));
        const relative = path.relative(ROOT, filePath);
        if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('candidate escaped project root: ' + candidate.uri);
        if (!fs.existsSync(filePath) || fs.statSync(filePath).size <= 0) {
            throw new Error('candidate asset missing: ' + item.name + ' ' + candidate.id + ' ' + candidate.uri);
        }
    }));
    dataset.items.filter(item => item.kind === 'armor').forEach(item => {
        ['male', 'female'].forEach(gender => {
            const focus = item.candidates.find(candidate => candidate.id === 'dressup-armor-focus-' + gender);
            const referenceId = gender === 'male' ? 'dressup-armor-male' : 'dressup-armor-female';
            const reference = item.candidates.find(candidate => candidate.id === referenceId);
            if (!reference && !focus) return;
            if (!focus) throw new Error('armor focus candidate missing: ' + item.name + ' ' + gender);
            armorFocusCount += 1;
            if (focus.metrics.width !== 256 || focus.metrics.height !== 256) {
                throw new Error('armor focus output must be 256x256: ' + item.name + ' ' + gender);
            }
            if (!focus.pipeline || focus.pipeline.composition !== 'armor-focus' ||
                focus.pipeline.sourceWidth !== 512 || focus.pipeline.sourceHeight !== 512 ||
                focus.pipeline.resampleCount !== 1) {
                throw new Error('armor focus supersample pipeline mismatch: ' + item.name + ' ' + gender);
            }
            if (!focus.state || !focus.state.fitFields.length || !focus.state.drawFields.length) {
                throw new Error('armor focus fields missing: ' + item.name + ' ' + gender);
            }
            if (focus.state.fitFields.some(field => focus.state.drawFields.indexOf(field) < 0)) {
                throw new Error('armor focus draw fields do not cover fit fields: ' + item.name + ' ' + gender);
            }
            const allowedContext = allowedFocusContext[item.use] || [];
            const unrelatedFields = focus.state.drawFields.filter(field =>
                focus.state.fitFields.indexOf(field) < 0 && allowedContext.indexOf(field) < 0);
            if (unrelatedFields.length) {
                throw new Error('armor focus contains unrelated fields: ' + item.name + ' ' + gender + ' ' + unrelatedFields.join(','));
            }
            if (reference && focus.render && reference.render && focus.render.holders > reference.render.holders) {
                throw new Error('armor focus added holders over reference: ' + item.name + ' ' + gender);
            }
            if (focus.warnings.indexOf('触边') >= 0) {
                throw new Error('expected context clipping was reported as an error: ' + item.name + ' ' + gender);
            }
            const baseline = item.candidates.find(candidate => candidate.id === 'icon-current');
            if (baseline) {
                specializationContractCount += 1;
                const expectedGain = Math.sqrt(focus.metrics.alphaPixels / baseline.metrics.alphaPixels);
                if (!focus.specialization || focus.specialization.metric !== 'sqrt-alpha-pixels' ||
                    Math.abs(focus.specialization.gain - Math.round(expectedGain * 1000) / 1000) > 0.0001) {
                    throw new Error('armor specialization gain mismatch: ' + item.name + ' ' + gender);
                }
                if (focus.specialization.contractPass !== (expectedGain >= focus.specialization.minGain)) {
                    throw new Error('armor specialization pass mismatch: ' + item.name + ' ' + gender);
                }
                if (!focus.specialization.contractPass && focus.reviewRole !== 'nonqualifying') {
                    throw new Error('nonqualifying armor focus was still recommended: ' + item.name + ' ' + gender);
                }
            }
        });
    });
    dataset.items.filter(item => item.kind === 'weapon').forEach(item => {
        const candidate = item.candidates.find(entry => entry.id === 'dressup-weapon');
        if (!candidate) return;
        const baseline = item.candidates.find(entry => entry.id === 'icon-current');
        if (baseline) {
            weaponContractCount += 1;
            const baselineEdge = Math.max(baseline.metrics.bbox.width, baseline.metrics.bbox.height);
            const candidateEdge = Math.max(candidate.metrics.bbox.width, candidate.metrics.bbox.height);
            const expectedGain = candidateEdge * 1.85 / baselineEdge;
            if (!candidate.specialization || candidate.specialization.metric !== 'max-bbox-at-default-zoom' ||
                candidate.specialization.displayZoom !== 1.85 ||
                Math.abs(candidate.specialization.gain - Math.round(expectedGain * 1000) / 1000) > 0.0001) {
                throw new Error('weapon specialization gain mismatch: ' + item.name);
            }
            if (candidate.specialization.contractPass !== (expectedGain >= candidate.specialization.minGain)) {
                throw new Error('weapon specialization pass mismatch: ' + item.name);
            }
        }
        const expectedComposition = item.actionType === '双刀' ? 'dual-blade' :
            (item.actionType === '疾影' ? 'blade-sheath' : '');
        if (!expectedComposition) return;
        compositeNames[expectedComposition].push(item.name);
        const expectedFields = expectedComposition === 'dual-blade'
            ? ['刀_装扮', '刀2_装扮'] : ['刀_装扮', '刀3_装扮'];
        if (!candidate.state || candidate.state.composition !== expectedComposition ||
            !sameSet(candidate.state.fitFields, expectedFields) || !sameSet(candidate.state.drawFields, expectedFields) ||
            !candidate.state.components || candidate.state.components.length !== 2) {
            throw new Error('composite weapon state mismatch: ' + item.name);
        }
        if (!candidate.render || candidate.render.holders !== 2 || candidate.render.missing !== 0 ||
            candidate.render.failedImages !== 0) {
            throw new Error('composite weapon did not render both holders: ' + item.name);
        }
        if (!candidate.pipeline || candidate.pipeline.composition !== expectedComposition ||
            candidate.pipeline.componentCount !== 2 || candidate.pipeline.resampleCount !== 1) {
            throw new Error('composite weapon pipeline mismatch: ' + item.name);
        }
        const expectedLabel = expectedComposition === 'dual-blade' ? '完整双刀商品图' : '刀身+刀鞘商品图';
        if (candidate.label !== expectedLabel) throw new Error('composite weapon label mismatch: ' + item.name);
    });
    Object.keys(compositeNames).forEach(key => {
        compositeNames[key].sort((left, right) => left.localeCompare(right, 'zh-CN'));
    });
    if (dataset.counts.uniqueItemCount === 280) {
        if (!sameSet(compositeNames['dual-blade'], EXPECTED_CRAFTING_DUAL_BLADES)) {
            throw new Error('full review dual-blade exact-set changed: ' + JSON.stringify(compositeNames['dual-blade']));
        }
        if (!sameSet(compositeNames['blade-sheath'], EXPECTED_CRAFTING_BLADE_SHEATHS)) {
            throw new Error('full review blade-sheath exact-set changed: ' + JSON.stringify(compositeNames['blade-sheath']));
        }
    }
    const judgment = dataset.items.find(item => item.name === '烬灭裁决');
    if (judgment) {
        const candidate = judgment.candidates.find(entry => entry.id === 'dressup-weapon');
        if (judgment.actionType !== '长柄' || !candidate || !candidate.state ||
            candidate.state.composition !== 'single' || candidate.render.holders !== 1) {
            throw new Error('烬灭裁决 must remain the single long-handle product form');
        }
    }
    if (!armorFocusCount) throw new Error('review data has no armor focus candidates');
    if (!specializationContractCount) throw new Error('review data has no comparable specialization contracts');
    if (!weaponContractCount) throw new Error('review data has no comparable weapon specialization contracts');
    const garo = dataset.items.find(item => item.name === '黄金骑士牙狼头盔');
    if (garo && (garo.iconName !== '牙狼铠头盔' || !garo.candidates.some(candidate => candidate.id === 'icon-current'))) {
        throw new Error('item icon key alias was not resolved for 黄金骑士牙狼头盔');
    }
    const animatedCandidates = dataset.items.flatMap(item => item.candidates).filter(candidate => candidate.render && candidate.render.animated);
    if (!animatedCandidates.length) throw new Error('sample/full review data has no animated source audit candidate');
    animatedCandidates.forEach(candidate => {
        if (!candidate.animation || candidate.animation.previewMode !== 'static-first-frame' ||
            candidate.animation.contractPass !== false || candidate.reviewRole !== 'nonqualifying' ||
            candidate.warnings.indexOf('动画仅首帧') < 0) {
            throw new Error('animated candidate was not blocked as static-first-frame: ' + candidate.id);
        }
    });
    const { chromium } = require(PLAYWRIGHT);
    const server = await startServer(ROOT, 0);
    const browser = await chromium.launch({ executablePath, headless: true });
    const errors = [];
    const failed = [];
    try {
        const page = await browser.newPage({ viewport: { width: 1500, height: 940 } });
        page.on('pageerror', error => errors.push(error.message || String(error)));
        page.on('requestfailed', request => failed.push(request.url()));
        const migrationItem = dataset.items.find(item => item.candidates.length);
        const migrationCandidate = migrationItem && migrationItem.candidates[0];
        await page.addInitScript(seed => {
            const decisions = {};
            decisions[seed.itemName] = {
                candidateId: seed.candidateId,
                needsAdjustment: true,
                note: 'migration-probe'
            };
            localStorage.setItem('cf7-crafting-product-review:legacy-test', JSON.stringify(decisions));
        }, { itemName: migrationItem.name, candidateId: migrationCandidate.id });
        const data = encodeURIComponent('/tmp/crafting-product-review/review-data.json');
        await page.goto(server.url + 'launcher/web/modules/crafting-product-review/dev/review.html?data=' + data, { waitUntil: 'load' });
        await page.waitForFunction(expected => document.querySelectorAll('.review-row').length === expected, dataset.items.length, { timeout: 20000 });
        const migrated = page.locator('[data-item-id="' + migrationItem.id + '"] input[value="' + migrationCandidate.id + '"]');
        if (await migrated.isChecked()) throw new Error('cross-digest candidate approval was unsafely migrated');
        const migrationRow = page.locator('[data-item-id="' + migrationItem.id + '"]');
        if (!await migrationRow.locator('[data-decision="needsAdjustment"]').isChecked() ||
            await migrationRow.locator('[data-decision="note"]').inputValue() !== 'migration-probe') {
            throw new Error('cross-digest issue flag/note was not migrated');
        }
        if ((await page.locator('#summary').textContent()).indexOf('未迁移通过决定') < 0) {
            throw new Error('safe legacy issue/note migration was not reported');
        }
        const candidateCount = await page.locator('.candidate').count();
        if (candidateCount !== dataset.counts.candidateCount) {
            throw new Error('candidate count mismatch: DOM=' + candidateCount + ' data=' + dataset.counts.candidateCount);
        }
        for (const item of dataset.items) {
            for (const candidate of item.candidates.filter(entry => entry.reviewRole === 'nonqualifying')) {
                const radio = page.locator('[data-item-id="' + item.id + '"] input[value="' + candidate.id + '"]');
                if (!await radio.isDisabled()) throw new Error('nonqualifying candidate remained signable: ' + item.name + ' ' + candidate.id);
            }
        }
        const firstRadio = page.locator('.review-row input[type="radio"]:not(:disabled)').first();
        await firstRadio.check();
        const progress = await page.locator('#progress').getAttribute('value');
        if (Number(progress) < 1) throw new Error('review decision did not update progress');
        const selectedId = await firstRadio.getAttribute('id');
        await page.reload({ waitUntil: 'load' });
        await page.waitForFunction(expected => document.querySelectorAll('.review-row').length === expected, dataset.items.length, { timeout: 20000 });
        if (!await page.locator('#' + selectedId).isChecked()) throw new Error('same-digest candidate decision did not persist');
        await page.locator('.candidate-image-button').first().click();
        if (!await page.locator('#preview-dialog').evaluate(node => node.open)) throw new Error('preview dialog did not open');
        await page.locator('.dialog-close').click();

        const shot = argValue('--shot');
        if (shot) {
            const shotPath = path.resolve(ROOT, shot);
            fs.mkdirSync(path.dirname(shotPath), { recursive: true });
            await page.screenshot({ path: shotPath, fullPage: true });
        }
        if (errors.length || failed.length) throw new Error(JSON.stringify({ errors, failed }));
        console.log('Crafting product review harness passed: items=' + dataset.items.length + ' candidates=' + candidateCount +
            ' armorFocus=' + armorFocusCount + ' specializationContracts=' + specializationContractCount +
            ' weaponContracts=' + weaponContractCount +
            ' compositeWeapons=' + (compositeNames['dual-blade'].length + compositeNames['blade-sheath'].length) +
            ' animatedStaticBlocked=' + animatedCandidates.length);
    } finally {
        await browser.close();
        await stopServer(server);
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
