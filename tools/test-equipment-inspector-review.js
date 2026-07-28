#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const REVIEW_DATA = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'review-data.json');
const BUILD_REPORT = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'build-report.json');
const REVIEW_PAGE = path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector-review', 'dev', 'review.html');
const REVIEW_SCRIPT = path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector-review', 'dev', 'review.js');
const BUILDER = path.join(ROOT, 'tools', 'build-equipment-inspector-review.js');
const { startServer, stopServer } = require(path.join(ROOT, 'launcher', 'perf', 'lib', 'server'));
const build = require(BUILDER);

const EXPECTED_DUPLICATE_NAMES = ['TheGirl头-NPC', '三戈戟二型', '小F头部'].sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_ANIMATED_WEAPONS = [
    '激光剑', '绝地武士佩剑', '审判日夜闪', '重力操纵之剑', '应援棒', '3XF电棍', '炎魔斩alter', '绯红女皇',
    '异形毒刺', '异形女王毒刺', '怒海狂鲨', 'M4A1雷神', 'AK47火麒麟', '混凝土切割机', '生命收割者'
].sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_ANIMATED_ARMOR = [
    '黑铁死士围巾', '黑铁游侠围巾', 'A兵团精致战术背心', '兽王虎甲腿甲', '兽王虎甲',
    '兽王虎甲盔', '兽王战甲', '兽王战甲盔', '末日铁拳'
].sort((left, right) => left.localeCompare(right, 'zh-CN'));

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

function sameArray(left, right) {
    return left.length === right.length && left.every((value, index) => value === right[index]);
}

function argValue(name) {
    const index = process.argv.indexOf(name);
    return index >= 0 ? process.argv[index + 1] || '' : '';
}

function dataFile(uri) {
    const clean = String(uri || '').replace(/^\/+/, '');
    const resolved = path.resolve(ROOT, clean);
    const relative = path.relative(ROOT, resolved);
    if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('candidate escaped repository: ' + uri);
    return resolved;
}

function expectedCounts(items, duplicateGroups) {
    const branches = items.flatMap(item => item.requiredBranches);
    const branchPairs = items.flatMap(item => item.requiredBranches.map(branch => ({item, branch})));
    const specialized = branches.filter(branch => branch.candidateId !== 'icon-current');
    return {
        definitionCount: items.length,
        weaponDefinitionCount: items.filter(item => item.majorType === '武器').length,
        armorDefinitionCount: items.filter(item => item.majorType === '防具').length,
        requiredBranchCount: branches.length,
        baselineCandidateCount: items.length,
        specializedCandidateCount: specialized.length,
        candidateCount: items.length + specialized.length,
        duplicateNameGroupCount: duplicateGroups.length,
        weaponProductBranchCount: branches.filter(branch => branch.route === 'weapon-product').length,
        armorFocusBranchCount: branches.filter(branch => branch.route === 'armor-focus').length,
        armorFocusMaleBranchCount: branches.filter(branch => branch.id === 'armor-focus-male').length,
        armorFocusFemaleBranchCount: branches.filter(branch => branch.id === 'armor-focus-female').length,
        fallbackBranchCount: branches.filter(branch => branch.route === 'icon-fallback').length,
        weaponFallbackBranchCount: branchPairs.filter(pair => pair.item.majorType === '武器' && pair.branch.route === 'icon-fallback').length,
        armorFallbackBranchCount: branchPairs.filter(pair => pair.item.majorType === '防具' && pair.branch.route === 'icon-fallback').length,
        fallbackMissingIconCount: branches.filter(branch => branch.route === 'icon-fallback' &&
            branch.approval.blockingGates.includes('icon_missing')).length,
        dualBladeDefinitionCount: items.filter(item => item.actionType === '双刀').length,
        bladeSheathDefinitionCount: items.filter(item => item.actionType === '疾影').length,
        missingImageBranchCount: branches.filter(branch => branch.approval.blockingGates.some(gate =>
            gate === 'icon_missing' || gate === 'preview_missing' || gate === 'image_load_failed')).length,
        missingHolderBranchCount: branches.filter(branch => branch.approval.blockingGates.some(gate =>
            gate === 'holder_missing' || gate === 'holder_contract_failed')).length,
        animatedBranchCount: branches.filter(branch => branch.animation.sourceAnimated).length,
        liveReviewGateCount: branches.filter(branch => branch.approval.requiresLiveReview).length
    };
}

function validateDataset(dataset) {
    assert.strictEqual(dataset.schema, 'cf7-equipment-inspector-review-v1');
    assert.strictEqual(dataset.partial, false, 'formal test requires a full, non-partial build');
    assert.strictEqual(dataset.productionContract.defaultZoom, 1.85);
    assert.deepStrictEqual(dataset.productionContract.weapon, ['weapon-product']);
    assert.deepStrictEqual(dataset.productionContract.armor, ['armor-focus-male', 'armor-focus-female']);
    assert.strictEqual(dataset.productionContract.fallback, 'current-icon');
    assert.strictEqual(dataset.productionContract.animation, 'static-first-frame-non-signable-requires-live-review');

    const loaded = build.loadEquipmentDefinitions();
    assert.strictEqual(dataset.sourceDigest, build.sourceDigest(loaded.sourceFiles), 'review data is stale');
    assert(dataset.reviewDigest && /^[0-9a-f]{24}$/.test(dataset.reviewDigest));
    assert.strictEqual(dataset.reviewDigest, build.computeReviewDigest(dataset.sourceDigest, dataset.items),
        'rendered review evidence was modified after digest generation');
    assert.strictEqual(build.verifyReviewArtifacts(dataset.items, ROOT),
        dataset.counts.definitionCount + dataset.counts.requiredBranchCount);
    assert.strictEqual(dataset.counts.verifiedArtifactReferenceCount,
        dataset.counts.definitionCount + dataset.counts.requiredBranchCount);
    assert.strictEqual(dataset.items.length, loaded.definitions.length, 'raw equipment definition coverage changed');
    assert.strictEqual(dataset.counts.fullDefinitionCount, loaded.definitions.length);
    assert.strictEqual(dataset.counts.definitionCount, loaded.definitions.length);
    const sourceIds = loaded.definitions.map(item => item.id);
    const reviewIds = dataset.items.map(item => item.id);
    assert(sameArray(reviewIds, sourceIds), 'review order/identity must preserve every raw XML definition');
    assert.strictEqual(new Set(reviewIds).size, reviewIds.length, 'definition IDs must be unique');

    dataset.items.forEach((item, index) => {
        const source = loaded.definitions[index];
        assert.strictEqual(item.name, source.name);
        assert.strictEqual(item.sourceFile, source.sourceFile);
        assert.strictEqual(item.sourceOrdinal, source.sourceOrdinal);
        assert.strictEqual(item.id, item.sourceFile + '::' + (item.name || '(empty-name)') + '::' + item.sourceNameOccurrence,
            'stable id must contain source file + same-file same-name occurrence');
        assert.strictEqual(item.sourceRef, 'data/items/' + item.sourceFile + '#' +
            (item.name || '(empty-name)') + '[' + item.sourceNameOccurrence + ']');
        assert(item.domKey && /^[0-9a-f]{14}$/.test(item.domKey));
        assert(item.baseline && item.baseline.id === 'icon-current');
        const baselinePath = dataFile(item.baseline.uri);
        assert(fs.existsSync(baselinePath) && fs.statSync(baselinePath).size > 0);
        if (item.requiredBranches.length === 1 && item.requiredBranches[0].route === 'icon-fallback') {
            assert.strictEqual(item.requiredBranches[0].id, 'icon-fallback');
            assert.strictEqual(item.requiredBranches[0].candidateId, 'icon-current');
        } else {
            assert.strictEqual(item.requiredBranches.length, item.majorType === '武器' ? 1 : 2);
            const expectedIds = item.majorType === '武器'
                ? ['weapon-product'] : ['armor-focus-male', 'armor-focus-female'];
            assert.deepStrictEqual(item.requiredBranches.map(branch => branch.id), expectedIds);
        }
        item.requiredBranches.forEach(branch => {
            assert.strictEqual(branch.required, true);
            assert(!/256|f2|reference|full-body/i.test(branch.id), 'exploratory candidate leaked into fixed production review');
            assert(branch.uri.startsWith('/tmp/equipment-inspector-review/generated/'));
            const filePath = dataFile(branch.uri);
            assert(fs.existsSync(filePath) && fs.statSync(filePath).size > 0, 'preview asset missing: ' + branch.uri);
            assert.strictEqual(branch.specialization.displayZoom, 1.85);
            assert.strictEqual(branch.specialization.metric, 'max-bbox-at-default-zoom');
            assert.strictEqual(branch.specialization.contractPass,
                branch.specialization.gain !== null && branch.specialization.gain >= branch.specialization.minGain);
            if (!branch.specialization.contractPass) {
                assert(branch.approval.blockingGates.includes('specialization_gain_failed'));
            }
            if (branch.route === 'icon-fallback') {
                assert.strictEqual(branch.actualKind, 'icon');
                assert.strictEqual(branch.candidateId, 'icon-current');
                assert(branch.fallback && branch.fallback.intentionalProductionRoute);
                assert(!branch.approval.blockingGates.includes('fallback'));
            } else {
                assert.strictEqual(branch.actualKind, branch.expectedKind);
                assert.strictEqual(branch.candidateId, branch.id);
            }
            if (branch.approval.blockingGates.includes('icon_missing')) {
                if (branch.route === 'icon-fallback') {
                    assert(branch.approval.blockingGates.includes('preview_missing'));
                } else {
                    assert(branch.contentDigest, 'specialized preview should survive a missing comparison icon');
                }
            }
            if (branch.animation.sourceAnimated) {
                assert.strictEqual(branch.animation.previewMode, 'static-first-frame');
                assert.strictEqual(branch.animation.staticSignable, false);
                assert.strictEqual(branch.approval.staticSignable, false);
                assert.strictEqual(branch.approval.requiresLiveReview, true);
                assert(branch.approval.blockingGates.includes('live_animation'));
                assert(branch.warnings.some(value => value.indexOf('需 live 动效验收') >= 0));
                if (branch.route !== 'icon-fallback') {
                    assert(branch.animation.evidence && branch.animation.evidence.selectedEquipmentFieldsOnly);
                    assert(branch.animation.evidence.fields.some(field => field.animated),
                        'motion hard gate lacks selected field/skin evidence');
                }
            } else {
                assert.strictEqual(branch.approval.requiresLiveReview, false);
            }
            const nonLiveGates = branch.approval.blockingGates.filter(gate => gate !== 'live_animation');
            assert.strictEqual(branch.approval.liveSignable,
                branch.animation.sourceAnimated && nonLiveGates.length === 0);
            assert.strictEqual(branch.approval.staticSignable,
                !branch.animation.sourceAnimated && nonLiveGates.length === 0);
        });
    });

    const duplicateGroups = dataset.duplicateNameGroups.slice().sort((left, right) => left.name.localeCompare(right.name, 'zh-CN'));
    assert.deepStrictEqual(duplicateGroups.map(group => group.name), EXPECTED_DUPLICATE_NAMES,
        'the three known duplicate-name groups changed; audit identity mapping');
    duplicateGroups.forEach(group => {
        assert.strictEqual(group.definitionIds.length, 2);
        assert.strictEqual(new Set(group.definitionIds).size, 2);
        group.definitionIds.forEach(id => {
            const item = dataset.items.find(candidate => candidate.id === id);
            assert(item && item.duplicateName, 'duplicate definition warning missing: ' + id);
            assert(item.warnings.some(value => value.indexOf('独立保存') >= 0));
        });
    });

    const dualOrSheath = dataset.items.filter(item => item.majorType === '武器' &&
        (item.actionType === '双刀' || item.actionType === '疾影'));
    assert(dualOrSheath.length > 0, 'no dual-blade/sheath definitions were audited');
    let compositeRendered = 0;
    dualOrSheath.forEach(item => {
        const branch = item.requiredBranches[0];
        assert.strictEqual(branch.expectedHolders, 2);
        const expectedComposition = item.actionType === '双刀' ? 'dual-blade' : 'blade-sheath';
        assert.strictEqual(branch.source && branch.source.composition, expectedComposition);
        if (branch.route === 'weapon-product') {
            compositeRendered += 1;
            assert.strictEqual(branch.source.components.length, 2);
            assert.strictEqual(branch.render.holders, 2);
            assert.strictEqual(branch.render.missing, 0);
            assert.strictEqual(branch.render.failedImages, 0);
            assert.strictEqual(branch.state.components.length, 2);
        }
    });
    assert(compositeRendered > 0, 'no composite weapon rendered both holders');

    const expected = expectedCounts(dataset.items, dataset.duplicateNameGroups);
    Object.keys(expected).forEach(key => assert.strictEqual(dataset.counts[key], expected[key], 'count mismatch: ' + key));
    assert.strictEqual(dataset.counts.duplicateNameGroupCount, 3);
    assert.strictEqual(dataset.counts.definitionCount, 1197);
    assert.strictEqual(dataset.counts.weaponDefinitionCount, 546);
    assert.strictEqual(dataset.counts.armorDefinitionCount, 651);
    assert.strictEqual(dataset.counts.requiredBranchCount, 1749);
    assert.strictEqual(dataset.counts.baselineCandidateCount, 1197);
    assert.strictEqual(dataset.counts.weaponProductBranchCount, 543);
    assert.strictEqual(dataset.counts.armorFocusBranchCount, 1104);
    assert.strictEqual(dataset.counts.armorFocusMaleBranchCount, 552);
    assert.strictEqual(dataset.counts.armorFocusFemaleBranchCount, 552);
    assert.strictEqual(dataset.counts.fallbackBranchCount, 102);
    assert.strictEqual(dataset.counts.weaponFallbackBranchCount, 3);
    assert.strictEqual(dataset.counts.armorFallbackBranchCount, 99);
    assert.strictEqual(dataset.counts.fallbackMissingIconCount, 16);
    assert.strictEqual(dataset.counts.dualBladeDefinitionCount, 9);
    assert.strictEqual(dataset.counts.bladeSheathDefinitionCount, 9);
    assert.strictEqual(dataset.counts.specializedCandidateCount, 1647);
    assert.strictEqual(dataset.counts.candidateCount, 2844);
    assert.strictEqual(dataset.counts.animatedBranchCount, 33);
    assert.strictEqual(dataset.counts.liveReviewGateCount, 33);
    const animatedPairs = dataset.items.flatMap(item => item.requiredBranches
        .filter(branch => branch.animation.sourceAnimated).map(branch => ({item, branch})));
    assert.strictEqual(animatedPairs.length, 33);
    assert.strictEqual(new Set(animatedPairs.map(pair => pair.item.id)).size, 24);
    assert.strictEqual(animatedPairs.filter(pair => pair.branch.animation.renderReportedAnimated === false).length, 10,
        'direct-preview nested animation coverage changed');
    assert.deepStrictEqual(Array.from(new Set(animatedPairs.filter(pair => pair.item.majorType === '武器')
        .map(pair => pair.item.name))).sort((left, right) => left.localeCompare(right, 'zh-CN')), EXPECTED_ANIMATED_WEAPONS);
    assert.deepStrictEqual(Array.from(new Set(animatedPairs.filter(pair => pair.item.majorType === '防具')
        .map(pair => pair.item.name))).sort((left, right) => left.localeCompare(right, 'zh-CN')), EXPECTED_ANIMATED_ARMOR);
    EXPECTED_ANIMATED_ARMOR.forEach(name => {
        const genders = animatedPairs.filter(pair => pair.item.name === name).map(pair => pair.branch.gender).sort();
        assert.deepStrictEqual(genders, ['女', '男'].sort(), 'animated armor gender branches changed: ' + name);
    });
    assert.strictEqual(animatedPairs.filter(pair => pair.branch.route === 'icon-fallback').length, 0);
    animatedPairs.forEach(pair => {
        const evidence = pair.branch.animation.evidence;
        assert(evidence.selectedEquipmentFieldsOnly);
        const movingFields = evidence.fields.filter(field => field.animated);
        assert(movingFields.length > 0, 'missing moving selected skin evidence: ' + pair.item.name);
        movingFields.forEach(field => {
            assert(field.field && field.skinKey);
            assert(field.reasons.length > 0);
            assert(field.distinctStates > 1 || field.nestedLayers.some(layer => layer.distinctStates > 1));
        });
    });
    ['审判日夜闪', '怒海狂鲨'].forEach(name => {
        const pair = animatedPairs.find(candidate => candidate.item.name === name);
        assert(pair && pair.branch.animation.evidence.fields.some(field =>
            field.nestedLayers.some(layer => layer.depth >= 2 && layer.path.length >= 2)),
        'recursive nested animation evidence disappeared: ' + name);
    });
    assert(dataset.counts.staticSignableBranchCount > 0);
    return { loaded, expected, compositeRendered };
}

async function validateReviewPage(dataset) {
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('missing Playwright dependency');
    const { chromium } = require(PLAYWRIGHT);
    const server = await startServer(ROOT, 0);
    const browser = await chromium.launch({ executablePath: findEdge(), headless: true });
    const pageErrors = [];
    const failedRequests = [];
    try {
        const page = await browser.newPage({ viewport: { width: 1550, height: 940 } });
        page.on('pageerror', error => pageErrors.push(error.message || String(error)));
        page.on('requestfailed', request => failedRequests.push(request.url()));
        const staleItem = dataset.items[0];
        await page.addInitScript(seed => {
            const value = {};
            value[seed.itemId] = {branches:{}};
            value[seed.itemId].branches[seed.branchId] = {status:'pass', note:'must-not-migrate'};
            localStorage.setItem('cf7-equipment-inspector-review:stale-review-digest', JSON.stringify(value));
        }, { itemId:staleItem.id, branchId:staleItem.requiredBranches[0].id });
        const data = encodeURIComponent('/tmp/equipment-inspector-review/review-data.json');
        await page.goto(server.url + 'launcher/web/modules/equipment-inspector-review/dev/review.html?data=' + data, { waitUntil:'load' });
        await page.waitForFunction(expected => document.querySelectorAll('.review-row').length === expected,
            dataset.items.length, {timeout:30000});
        assert.strictEqual(await page.locator('.review-row').count(), dataset.items.length);
        assert.strictEqual(await page.locator('.review-branch').count(), dataset.counts.requiredBranchCount);
        assert((await page.locator('#summary').textContent()).includes('3 组重名'));
        const staleRow = page.locator('.review-row[data-dom-key="' + staleItem.domKey + '"]');
        assert.strictEqual(await staleRow.locator('[data-branch-status]').first().inputValue(), '',
            'different reviewDigest storage leaked into current review');

        // 同 sourceDigest 但不同 reviewDigest 的导入必须 fail-closed。
        const mismatchedReviewPath = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'mismatched-review-digest.json');
        const mismatchDecisions = {};
        mismatchDecisions[staleItem.id] = {branches:{}};
        mismatchDecisions[staleItem.id].branches[staleItem.requiredBranches[0].id] = {status:'adjustment'};
        fs.writeFileSync(mismatchedReviewPath, JSON.stringify({
            schema:'cf7-equipment-inspector-review-decisions-v1',
            sourceDigest:dataset.sourceDigest,
            reviewDigest:'000000000000000000000000',
            decisions:mismatchDecisions
        }, null, 2));
        const mismatchDialogPromise = page.waitForEvent('dialog');
        await page.locator('#import-file').setInputFiles(mismatchedReviewPath);
        const mismatchDialog = await mismatchDialogPromise;
        assert((mismatchDialog.message() || '').includes('reviewDigest 不一致'));
        await mismatchDialog.accept();
        assert.strictEqual(await staleRow.locator('[data-branch-status]').first().inputValue(), '',
            'same-source different-render import leaked a decision');

        const animatedItem = dataset.items.find(item => item.requiredBranches.some(branch =>
            branch.animation.sourceAnimated && branch.approval.liveSignable));
        assert(animatedItem, 'need one live-signable animated branch');
        const animatedBranch = animatedItem.requiredBranches.find(branch =>
            branch.animation.sourceAnimated && branch.approval.liveSignable);
        let animatedRow = page.locator('.review-row[data-dom-key="' + animatedItem.domKey + '"]');
        let animatedCard = animatedRow.locator('.review-branch[data-branch-id="' + animatedBranch.id + '"]');
        assert.notStrictEqual(await animatedCard.locator('option[value="pass"]').getAttribute('disabled'), null,
            'animated static first frame remained signable');
        assert.notStrictEqual(await animatedCard.locator('option[value="live-pass"]').getAttribute('disabled'), null,
            'live-pass was enabled before explicit motion review');
        assert((await animatedCard.locator('.live-preview').textContent()).includes('必验'));

        // 即便篡改 DOM 去掉 disabled，change handler 也必须拒绝直接 live-pass。
        await animatedCard.locator('[data-branch-status]').evaluate(select => {
            select.querySelector('option[value="live-pass"]').disabled = false;
            select.value = 'live-pass';
            select.dispatchEvent(new Event('change', {bubbles:true}));
        });
        animatedRow = page.locator('.review-row[data-dom-key="' + animatedItem.domKey + '"]');
        assert.strictEqual(await animatedRow.locator('.review-branch[data-branch-id="' + animatedBranch.id + '"] [data-branch-status]').inputValue(), '');

        // 同 digest 导入若伪造 live-pass 却缺 motionReviewed，也必须降级。
        const fakeImportPath = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'fake-live-pass.json');
        const fakeDecisions = {};
        fakeDecisions[animatedItem.id] = {branches:{}};
        fakeDecisions[animatedItem.id].branches[animatedBranch.id] = {status:'live-pass', note:'forged-without-motion'};
        fs.writeFileSync(fakeImportPath, JSON.stringify({
            schema:'cf7-equipment-inspector-review-decisions-v1',
            sourceDigest:dataset.sourceDigest,
            reviewDigest:dataset.reviewDigest,
            decisions:fakeDecisions
        }, null, 2));
        await page.locator('#import-file').setInputFiles(fakeImportPath);
        await page.waitForFunction(keys => {
            const row = document.querySelector('.review-row[data-dom-key="' + keys.item + '"]');
            return row && row.querySelector('.review-branch[data-branch-id="' + keys.branch + '"] [data-branch-status]').value === '';
        }, {item:animatedItem.domKey, branch:animatedBranch.id});

        const forgedDownloadPromise = page.waitForEvent('download');
        await page.locator('#export-button').click();
        const forgedDownload = await forgedDownloadPromise;
        const forgedExportPath = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'test-forged-export.json');
        await forgedDownload.saveAs(forgedExportPath);
        const forgedExport = JSON.parse(fs.readFileSync(forgedExportPath, 'utf8'));
        const forgedBranch = forgedExport.decisions[animatedItem.id] &&
            forgedExport.decisions[animatedItem.id].branches[animatedBranch.id];
        assert(!forgedBranch || forgedBranch.status !== 'live-pass', 'export preserved live-pass without motionReviewed');

        // 只打开真实 inspector 并关闭仍不算验收。
        animatedRow = page.locator('.review-row[data-dom-key="' + animatedItem.domKey + '"]');
        await animatedRow.locator('.review-branch[data-branch-id="' + animatedBranch.id + '"] .live-preview').click();
        let inspector = page.locator('.review-live-layer .equipment-inspector');
        await inspector.waitFor({state:'visible', timeout:10000});
        await page.locator('.review-live-layer .workbench-modal-action').filter({hasText:'返回全量验收'}).click();
        animatedRow = page.locator('.review-row[data-dom-key="' + animatedItem.domKey + '"]');
        assert.notStrictEqual(await animatedRow.locator('.review-branch[data-branch-id="' + animatedBranch.id + '"] option[value="live-pass"]').getAttribute('disabled'), null,
            'opening live inspector alone incorrectly satisfied motion gate');

        // 第二次打开后，等待 production renderer 确认 live，再由人类显式确认。
        await animatedRow.locator('.review-branch[data-branch-id="' + animatedBranch.id + '"] .live-preview').click();
        inspector = page.locator('.review-live-layer .equipment-inspector');
        await inspector.waitFor({state:'visible', timeout:10000});
        assert.strictEqual(await inspector.getAttribute('data-zoom'), '185');
        const motionConfirm = page.locator('.review-live-layer [data-motion-review-confirm]');
        await motionConfirm.waitFor({state:'visible', timeout:10000});
        await page.waitForFunction(() => {
            const button = document.querySelector('.review-live-layer [data-motion-review-confirm]');
            return button && !button.disabled;
        }, null, {timeout:15000});
        await motionConfirm.click();
        await page.locator('.review-live-layer .workbench-modal-action').filter({hasText:'返回全量验收'}).click();
        animatedRow = page.locator('.review-row[data-dom-key="' + animatedItem.domKey + '"]');
        animatedCard = animatedRow.locator('.review-branch[data-branch-id="' + animatedBranch.id + '"]');
        assert.strictEqual(await animatedCard.locator('option[value="live-pass"]').getAttribute('disabled'), null);
        await animatedCard.locator('[data-branch-status]').selectOption('live-pass');
        animatedRow = page.locator('.review-row[data-dom-key="' + animatedItem.domKey + '"]');
        assert.strictEqual(await animatedRow.locator('[data-branch-status]').first().inputValue(), 'live-pass');

        // 遍历全部 33 个真实 motion required 分支，尤其覆盖 render harness
        // 静态 direct-preview 未报告 animated、但 production live renderer 会递归
        // 播放 selected skin.export.nestedAnimation 的 10 个分支。
        const allAnimatedPairs = dataset.items.flatMap(item => item.requiredBranches
            .filter(branch => branch.animation.sourceAnimated).map(branch => ({item:item, branch:branch})));
        let unlockedLiveCount = 1;
        let unlockedDirectPreviewCount = animatedBranch.animation && animatedBranch.animation.renderReportedAnimated === false ? 1 : 0;
        for (const pair of allAnimatedPairs) {
            if (pair.item.id === animatedItem.id && pair.branch.id === animatedBranch.id) continue;
            const row = page.locator('.review-row[data-dom-key="' + pair.item.domKey + '"]');
            await row.locator('.review-branch[data-branch-id="' + pair.branch.id + '"] .live-preview').click();
            const liveInspector = page.locator('.review-live-layer .equipment-inspector');
            await liveInspector.waitFor({state:'visible', timeout:10000});
            const confirmButton = page.locator('.review-live-layer [data-motion-review-confirm]');
            await confirmButton.waitFor({state:'visible', timeout:10000});
            await page.waitForFunction(() => {
                const button = document.querySelector('.review-live-layer [data-motion-review-confirm]');
                return button && !button.disabled;
            }, null, {timeout:15000});
            assert.strictEqual(await liveInspector.getAttribute('data-zoom'), '185');
            unlockedLiveCount += 1;
            if (pair.branch.animation.renderReportedAnimated === false) unlockedDirectPreviewCount += 1;
            await page.locator('.review-live-layer .workbench-modal-action').filter({hasText:'返回全量验收'}).click();
        }
        assert.strictEqual(unlockedLiveCount, 33);
        assert.strictEqual(unlockedDirectPreviewCount, 10);

        const armor = dataset.items.find(item => item.majorType === '防具' && item.requiredBranches.length === 2 &&
            item.requiredBranches.every(branch => branch.approval.staticSignable));
        assert(armor, 'need one fully static-signable armor row for independent branch test');
        let armorRow = page.locator('.review-row[data-dom-key="' + armor.domKey + '"]');
        let male = armorRow.locator('.review-branch[data-branch-id="armor-focus-male"] [data-branch-status]');
        let female = armorRow.locator('.review-branch[data-branch-id="armor-focus-female"] [data-branch-status]');
        await male.selectOption('pass');
        armorRow = page.locator('.review-row[data-dom-key="' + armor.domKey + '"]');
        female = armorRow.locator('.review-branch[data-branch-id="armor-focus-female"] [data-branch-status]');
        assert.strictEqual(await female.inputValue(), '', 'male branch decision incorrectly signed female branch');
        assert.strictEqual(await armorRow.getAttribute('data-reviewed'), 'false');
        await armorRow.locator('[data-pass-row]').click();
        armorRow = page.locator('.review-row[data-dom-key="' + armor.domKey + '"]');
        assert.strictEqual(await armorRow.locator('.review-branch[data-branch-id="armor-focus-male"] [data-branch-status]').inputValue(), 'pass');
        assert.strictEqual(await armorRow.locator('.review-branch[data-branch-id="armor-focus-female"] [data-branch-status]').inputValue(), 'pass');
        assert.strictEqual(await armorRow.getAttribute('data-reviewed'), 'true');

        await page.reload({waitUntil:'load'});
        await page.waitForFunction(expected => document.querySelectorAll('.review-row').length === expected,
            dataset.items.length, {timeout:30000});
        armorRow = page.locator('.review-row[data-dom-key="' + armor.domKey + '"]');
        assert.strictEqual(await armorRow.locator('.review-branch[data-branch-id="armor-focus-male"] [data-branch-status]').inputValue(), 'pass');
        assert.strictEqual(await armorRow.locator('.review-branch[data-branch-id="armor-focus-female"] [data-branch-status]').inputValue(), 'pass');

        const duplicateGroup = dataset.duplicateNameGroups[0];
        const firstDuplicate = dataset.items.find(item => item.id === duplicateGroup.definitionIds[0]);
        const secondDuplicate = dataset.items.find(item => item.id === duplicateGroup.definitionIds[1]);
        let firstRow = page.locator('.review-row[data-dom-key="' + firstDuplicate.domKey + '"]');
        let secondRow = page.locator('.review-row[data-dom-key="' + secondDuplicate.domKey + '"]');
        await firstRow.locator('[data-branch-status]').first().selectOption('adjustment');
        secondRow = page.locator('.review-row[data-dom-key="' + secondDuplicate.domKey + '"]');
        assert.strictEqual(await secondRow.locator('[data-branch-status]').first().inputValue(), '',
            'duplicate names shared a decision key');
        firstRow = page.locator('.review-row[data-dom-key="' + firstDuplicate.domKey + '"]');
        assert(await firstRow.locator('.tag.bad').first().textContent());
        assert(await secondRow.locator('.tag.bad').first().textContent());

        const liveItem = dataset.items.find(item => item.requiredBranches.some(branch => branch.approval.staticSignable));
        const liveBranch = liveItem.requiredBranches.find(branch => branch.approval.staticSignable);
        const liveRow = page.locator('.review-row[data-dom-key="' + liveItem.domKey + '"]');
        await liveRow.locator('.review-branch[data-branch-id="' + liveBranch.id + '"] .live-preview').click();
        const staticInspector = page.locator('.review-live-layer .equipment-inspector');
        await staticInspector.waitFor({state:'visible', timeout:10000});
        assert.strictEqual(await staticInspector.getAttribute('data-zoom'), '185');
        await page.waitForFunction(() => {
            const node = document.querySelector('.review-live-layer .equipment-inspector');
            return node && node.getAttribute('data-source') && node.getAttribute('data-source') !== 'loading';
        }, null, {timeout:15000});
        await page.locator('.review-live-layer .workbench-modal-action').click();
        assert.strictEqual(await page.locator('.review-live-layer').count(), 0);

        const downloadPromise = page.waitForEvent('download');
        await page.locator('#export-button').click();
        const download = await downloadPromise;
        const exportPath = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'test-export.json');
        await download.saveAs(exportPath);
        const exported = JSON.parse(fs.readFileSync(exportPath, 'utf8'));
        assert.strictEqual(exported.schema, 'cf7-equipment-inspector-review-decisions-v1');
        assert.strictEqual(exported.sourceDigest, dataset.sourceDigest);
        assert.strictEqual(exported.reviewDigest, dataset.reviewDigest);
        assert.strictEqual(exported.decisions[animatedItem.id].branches[animatedBranch.id].status, 'live-pass');
        assert.strictEqual(exported.decisions[animatedItem.id].branches[animatedBranch.id].motionReviewed, true);
        assert(exported.decisions[armor.id]);
        assert(exported.decisions[firstDuplicate.id]);
        assert(!exported.decisions[secondDuplicate.id], 'untouched duplicate unexpectedly exported a decision');

        const shot = argValue('--shot');
        if (shot) {
            const shotPath = path.resolve(ROOT, shot);
            fs.mkdirSync(path.dirname(shotPath), {recursive:true});
            await page.screenshot({path:shotPath, fullPage:true});
        }
        assert.deepStrictEqual(pageErrors, []);
        assert.deepStrictEqual(failedRequests, []);
    } finally {
        await browser.close();
        await stopServer(server);
    }
}

async function main() {
    assert(fs.existsSync(REVIEW_DATA), 'missing full review data; run node tools/build-equipment-inspector-review.js');
    assert(fs.existsSync(BUILD_REPORT), 'missing build report');
    assert(fs.existsSync(REVIEW_PAGE));
    const builderSource = fs.readFileSync(BUILDER, 'utf8');
    const reviewSource = fs.readFileSync(REVIEW_SCRIPT, 'utf8');
    const openerSource = fs.readFileSync(path.join(ROOT, 'tools', 'open-equipment-inspector-review.js'), 'utf8');
    assert(builderSource.includes('EquipmentInspector.resolveItemSource'));
    assert(builderSource.includes("fileName + '::' + (name || '(empty-name)') + '::' + occurrence"));
    assert(!builderSource.includes('bake-icons-offline'));
    assert(!builderSource.includes('icon-256'));
    assert(!builderSource.includes('icon-f2'));
    assert(!builderSource.includes('dressup-armor-male'));
    assert(builderSource.includes("recursiveFiles(path.join(ROOT, 'launcher', 'web', 'icons'))"));
    assert(builderSource.includes("recursiveFiles(path.join(ROOT, 'launcher', 'web', 'assets', 'dressup'))"));
    assert(builderSource.includes("'workbench-inspection-viewport.js'"));
    assert(builderSource.includes('if (pageErrors.length || failedRequests.length)'));
    assert(builderSource.includes('nestedMotionLayers(childNested'));
    assert(reviewSource.includes("'cf7-equipment-inspector-review:' + dataset.reviewDigest"));
    assert(reviewSource.includes('decisions[item.id]'));
    assert(reviewSource.includes('sourceDigest 不一致'));
    assert(reviewSource.includes('motionReviewed'));
    assert(reviewSource.includes('data-motion-review-confirm'));
    assert(openerSource.includes('reviewBuild.sourceDigest(loaded.sourceFiles)'));
    assert(openerSource.includes('reviewBuild.computeReviewDigest'));
    assert(openerSource.includes('reviewBuild.verifyReviewArtifacts'));
    assert(openerSource.includes('stale review data'));
    const dataset = JSON.parse(fs.readFileSync(REVIEW_DATA, 'utf8'));
    const buildReport = JSON.parse(fs.readFileSync(BUILD_REPORT, 'utf8'));
    assert.strictEqual(buildReport.sourceDigest, dataset.sourceDigest);
    assert.strictEqual(buildReport.reviewDigest, dataset.reviewDigest);
    assert.deepStrictEqual(buildReport.pageErrors, []);
    assert.deepStrictEqual(buildReport.failedRequests, []);
    const artifactProbe = path.join(ROOT, 'tmp', 'equipment-inspector-review', 'artifact-digest-probe.bin');
    fs.writeFileSync(artifactProbe, 'tampered-preview-bytes');
    try {
        assert.throws(() => build.verifyReviewArtifacts([{
            id:'artifact-probe',
            baseline:{
                uri:'/tmp/equipment-inspector-review/artifact-digest-probe.bin',
                contentDigest:'000000000000'
            },
            requiredBranches:[]
        }], ROOT), /digest mismatch/);
        assert.throws(() => build.verifyReviewArtifacts([{
            id:'empty-digest-probe',
            baseline:{
                uri:'/tmp/equipment-inspector-review/artifact-digest-probe.bin',
                contentDigest:''
            },
            requiredBranches:[]
        }], ROOT), /only valid for the exact missing placeholder/);
    } finally {
        fs.unlinkSync(artifactProbe);
    }
    const audit = validateDataset(dataset);
    await validateReviewPage(dataset);
    console.log('Equipment inspector review passed: definitions=' + dataset.counts.definitionCount +
        ' branches=' + dataset.counts.requiredBranchCount +
        ' duplicateGroups=' + dataset.counts.duplicateNameGroupCount +
        ' fallback=' + dataset.counts.fallbackBranchCount +
        ' missingImages=' + dataset.counts.missingImageBranchCount +
        ' missingHolders=' + dataset.counts.missingHolderBranchCount +
        ' animatedLiveGates=' + dataset.counts.liveReviewGateCount +
        ' compositeRendered=' + audit.compositeRendered);
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
