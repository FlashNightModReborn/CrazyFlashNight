#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-data.js');

function parseArgs(argv) {
    return {
        json: argv.indexOf('--json') >= 0
    };
}

function loadData() {
    const source = fs.readFileSync(dataFile, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: dataFile });
    if (!sandbox.StageSelectData) {
        throw new Error('StageSelectData not found in ' + dataFile);
    }
    return sandbox.StageSelectData.exportManifest();
}

function assetExists(assetUrl) {
    if (!assetUrl) return false;
    return fs.existsSync(path.join(projectRoot, 'launcher', 'web', assetUrl.replace(/\//g, path.sep)));
}

function audit(manifest) {
    const frames = manifest.frames || [];
    const stageButtons = [];
    const navButtons = [];
    const missingBackgroundAssets = [];
    const missingPreviewAssets = [];
    const outOfBoundsButtons = [];

    frames.forEach(function(frame) {
        if (!frame.background || !assetExists(frame.background.assetUrl)) {
            missingBackgroundAssets.push(frame.frameLabel);
        }
        (frame.stageButtons || []).forEach(function(button) {
            stageButtons.push(button);
            if (!assetExists(button.previewUrl)) missingPreviewAssets.push(button.stageName);
            if (button.x < -320 || button.x > 1024 || button.y < -90 || button.y > 576) {
                outOfBoundsButtons.push(button.id);
            }
        });
        (frame.navButtons || []).forEach(function(button) {
            navButtons.push(button);
        });
    });

    const result = {
        ok: true,
        labels: frames.length,
        stageButtonInstances: stageButtons.length,
        sourceStageButtonInstances: manifest.assetReport && manifest.assetReport.sourceStageButtonInstances,
        navButtons: navButtons.length,
        uniqueStageNames: (manifest.stageNames || []).length,
        backgroundMissing: (manifest.assetReport && manifest.assetReport.backgroundMissing || []).length,
        backgroundAssetMissing: missingBackgroundAssets,
        backgroundFallbacks: manifest.assetReport && manifest.assetReport.backgroundFallbacks || [],
        derivedBackgrounds: manifest.assetReport && manifest.assetReport.derivedBackgrounds || [],
        previewAssetMissing: missingPreviewAssets,
        previewSources: manifest.assetReport && manifest.assetReport.previewSources || {},
        previewFallbacks: manifest.assetReport && manifest.assetReport.previewFallbacks || 0,
        outOfBoundsButtons: outOfBoundsButtons
    };

    const failures = [];
    if (result.labels !== 16) failures.push('expected 16 labels, got ' + result.labels);
    if (result.sourceStageButtonInstances !== 167) failures.push('expected 167 source stage button instances, got ' + result.sourceStageButtonInstances);
    if (result.stageButtonInstances !== 152) failures.push('expected 152 active rendered stage button instances, got ' + result.stageButtonInstances);
    if (result.backgroundMissing !== 0) failures.push('manifest has unmapped backgrounds');
    if (result.backgroundAssetMissing.length) failures.push('missing background assets: ' + result.backgroundAssetMissing.join(', '));
    if (result.previewAssetMissing.length) failures.push('missing preview assets: ' + result.previewAssetMissing.join(', '));
    if (result.outOfBoundsButtons.length) failures.push('button anchors outside expected guard band: ' + result.outOfBoundsButtons.join(', '));
    result.failures = failures;
    result.ok = failures.length === 0;
    return result;
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const result = audit(loadData());
    if (args.json) {
        process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    } else {
        console.log('[stage-select-audit] labels=' + result.labels + ' stageButtons=' + result.stageButtonInstances + ' uniqueStages=' + result.uniqueStageNames);
        console.log('[stage-select-audit] backgroundFallbacks=' + result.backgroundFallbacks.length + ' derivedBackgrounds=' + result.derivedBackgrounds.length + ' previewFallbacks=' + result.previewFallbacks + ' previewSources=' + JSON.stringify(result.previewSources));
        if (result.failures.length) result.failures.forEach(function(failure) { console.error('[stage-select-audit] FAIL ' + failure); });
    }
    if (!result.ok) process.exit(1);
}

main();
