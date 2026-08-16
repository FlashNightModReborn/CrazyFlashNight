#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-data.js');
// 计数基线单一真值；新增 / 删除 / 重分类条目时改 golden 文件，不要在本文件手改数字。
const goldenFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select', 'dev', 'stage-select-golden.js');

function parseArgs(argv) {
    return {
        json: argv.indexOf('--json') >= 0
    };
}

function runModule(file, globalName) {
    const source = fs.readFileSync(file, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: file });
    if (!sandbox[globalName]) {
        throw new Error(globalName + ' not found in ' + file);
    }
    return sandbox[globalName];
}

function loadData() {
    return runModule(dataFile, 'StageSelectData').exportManifest();
}

function loadGolden() {
    return runModule(goldenFile, 'StageSelectGolden');
}

function assetExists(assetUrl) {
    if (!assetUrl) return false;
    return fs.existsSync(path.join(projectRoot, 'launcher', 'web', assetUrl.replace(/\//g, path.sep)));
}

function audit(manifest, golden) {
    const frames = manifest.frames || [];
    const stageButtons = [];
    const navButtons = [];
    const directButtons = [];
    const mapButtons = [];
    const taskButtons = [];
    const decorations = [];
    const missingBackgroundAssets = [];
    const missingPreviewAssets = [];
    const missingDecorationAssets = [];
    const outOfBoundsButtons = [];

    // .fla 退役后 stage-select-data.js 成为唯一权威 SOT、可手改，导出器不再保证 id 唯一，
    // 故审计在此自检 stageButton.id 全局唯一（catch 手改/复制条目漏改 id 的类错误）。
    const stageButtonIdCounts = {};
    const duplicateStageButtonIds = [];

    // stageNames 是 inventory 声明（运行时 snapshot 由面板按按钮动态收集，不读本数组），
    // 但它必须覆盖全部按钮 stageName，否则 inventory 计数与真实条目静默漂移。
    const declaredStageNames = {};
    (manifest.stageNames || []).forEach(function(name) { declaredStageNames[name] = true; });
    const stageNamesMissingFromManifest = [];
    const missingLookup = {};

    frames.forEach(function(frame) {
        if (!frame.background || !assetExists(frame.background.assetUrl)) {
            missingBackgroundAssets.push(frame.frameLabel);
        }
        (frame.stageButtons || []).forEach(function(button) {
            stageButtons.push(button);
            if (button.id) {
                stageButtonIdCounts[button.id] = (stageButtonIdCounts[button.id] || 0) + 1;
                if (stageButtonIdCounts[button.id] === 2) duplicateStageButtonIds.push(button.id);
            }
            if (button.entryKind && button.entryKind !== 'difficulty') directButtons.push(button);
            if (button.entryKind === 'map') mapButtons.push(button);
            if (button.entryKind === 'task') taskButtons.push(button);
            if (button.stageName && !declaredStageNames[button.stageName] && !missingLookup[button.stageName]) {
                missingLookup[button.stageName] = true;
                stageNamesMissingFromManifest.push(button.stageName);
            }
            if (!assetExists(button.previewUrl)) missingPreviewAssets.push(button.stageName);
            if (button.x < -320 || button.x > 1024 || button.y < -90 || button.y > 576) {
                outOfBoundsButtons.push(button.id);
            }
        });
        (frame.navButtons || []).forEach(function(button) {
            navButtons.push(button);
        });
        (frame.decorations || []).forEach(function(item) {
            decorations.push(item);
            if (!assetExists(item.assetUrl)) missingDecorationAssets.push(item.id || item.kind || frame.frameLabel);
        });
    });

    const result = {
        ok: true,
        labels: frames.length,
        stageButtonInstances: stageButtons.length,
        duplicateStageButtonIds: duplicateStageButtonIds,
        sourceStageButtonInstances: manifest.assetReport && manifest.assetReport.sourceStageButtonInstances,
        directStageButtonInstances: directButtons.length,
        mapStageButtonInstances: mapButtons.length,
        taskStageButtonInstances: taskButtons.length,
        mapDirectLayoutMissing: mapButtons.filter(function(button) {
            return !button.directLayout || !button.directLayout.marker || !button.directLayout.text;
        }).map(function(button) { return button.stageName; }),
        decorationInstances: decorations.length,
        unmappedStageLikeInstances: manifest.assetReport && manifest.assetReport.unmappedStageLikeInstances || [],
        ignoredStageButtonInstances: manifest.assetReport && manifest.assetReport.ignoredStageButtonInstances || [],
        navButtons: navButtons.length,
        uniqueStageNames: (manifest.stageNames || []).length,
        stageNamesMissingFromManifest: stageNamesMissingFromManifest,
        backgroundMissing: (manifest.assetReport && manifest.assetReport.backgroundMissing || []).length,
        backgroundAssetMissing: missingBackgroundAssets,
        decorationAssetMissing: missingDecorationAssets,
        backgroundFallbacks: manifest.assetReport && manifest.assetReport.backgroundFallbacks || [],
        derivedBackgrounds: manifest.assetReport && manifest.assetReport.derivedBackgrounds || [],
        previewAssetMissing: missingPreviewAssets,
        previewSources: manifest.assetReport && manifest.assetReport.previewSources || {},
        previewFallbacks: manifest.assetReport && manifest.assetReport.previewFallbacks || 0,
        outOfBoundsButtons: outOfBoundsButtons
    };

    const failures = [];
    if (result.duplicateStageButtonIds.length) failures.push('duplicate stage button ids: ' + result.duplicateStageButtonIds.join(', '));
    if (result.stageNamesMissingFromManifest.length) failures.push('stageNames inventory missing button entries: ' + result.stageNamesMissingFromManifest.join(', '));
    if (result.mapDirectLayoutMissing.length) failures.push('missing direct map layout: ' + result.mapDirectLayoutMissing.join(', '));
    if (result.unmappedStageLikeInstances.length) failures.push('unmapped source stage-like instances: ' + result.unmappedStageLikeInstances.map(function(item) {
        return item.frameLabel + ':' + item.libraryItemName + '@' + item.x + ',' + item.y;
    }).join(', '));
    if (result.backgroundMissing !== 0) failures.push('manifest has unmapped backgrounds');
    if (result.backgroundAssetMissing.length) failures.push('missing background assets: ' + result.backgroundAssetMissing.join(', '));
    if (result.decorationAssetMissing.length) failures.push('missing decoration assets: ' + result.decorationAssetMissing.join(', '));
    if (result.previewAssetMissing.length) failures.push('missing preview assets: ' + result.previewAssetMissing.join(', '));
    if (result.outOfBoundsButtons.length) failures.push('button anchors outside expected guard band: ' + result.outOfBoundsButtons.join(', '));

    // 计数基线全部来自 golden 单一真值；golden 中的键必须在 result 有同名指标且数值相等。
    const exp = (golden && golden.expected) || {};
    Object.keys(exp).forEach(function(key) {
        if (typeof exp[key] !== 'number') return;
        if (typeof result[key] !== 'number') {
            failures.push('golden expected key "' + key + '" has no matching audit metric');
            return;
        }
        if (result[key] !== exp[key]) {
            failures.push('expected ' + exp[key] + ' ' + key + ', got ' + result[key]);
        }
    });
    result.failures = failures;
    result.ok = failures.length === 0;
    return result;
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const result = audit(loadData(), loadGolden());
    if (args.json) {
        process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    } else {
        console.log('[stage-select-audit] labels=' + result.labels + ' stageButtons=' + result.stageButtonInstances + ' directButtons=' + result.directStageButtonInstances + ' decorations=' + result.decorationInstances + ' uniqueStages=' + result.uniqueStageNames);
        console.log('[stage-select-audit] backgroundFallbacks=' + result.backgroundFallbacks.length + ' derivedBackgrounds=' + result.derivedBackgrounds.length + ' previewFallbacks=' + result.previewFallbacks + ' previewSources=' + JSON.stringify(result.previewSources));
        console.log('[stage-select-audit] sourceStageButtons=' + result.sourceStageButtonInstances + ' ignoredStageButtons=' + result.ignoredStageButtonInstances.length + ' unmappedStageLike=' + result.unmappedStageLikeInstances.length);
        if (result.failures.length) result.failures.forEach(function(failure) { console.error('[stage-select-audit] FAIL ' + failure); });
    }
    if (!result.ok) process.exit(1);
}

main();
