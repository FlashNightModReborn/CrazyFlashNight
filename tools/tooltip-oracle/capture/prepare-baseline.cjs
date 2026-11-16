#!/usr/bin/env node
'use strict';

// Prepare sources only. This command never invokes CS6, starts Flash, or touches
// a production SWF. The target must be a separate, clean pinned-baseline checkout.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const repo = path.resolve(__dirname, '../../..');
const manifest = JSON.parse(fs.readFileSync(path.join(repo, 'tools/tooltip-oracle/baseline.json'), 'utf8'));
const projectionPath = 'scripts/类定义/org/flashNight/gesh/tooltip/TooltipInputProjection.as';
const corpusPath = 'scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipCorpusDump.as';
const capturePath = 'scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipPairedCapture.as';
const captureJsonPath = 'scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipCaptureJson.as';
const captureControlPath = 'scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipCaptureControl.as';
const templatePath = 'scripts/test-runners/tooltip-corpus/TestLoader.as.template';
const captureClass = 'org.flashNight.gesh.tooltip.test.TooltipPairedCapture';
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function replaceOne(source, anchor, replacement) {
    if (source.split(anchor).length !== 2) throw new Error('baseline capture anchor missing or repeated: ' + anchor);
    return source.replace(anchor, replacement);
}

function instrumentCorpus(source, identity) {
    if (source.includes(captureClass)) throw new Error('baseline capture anchor already instrumented');
    const begin = `if (!${captureClass}.begin(runId, ${JSON.stringify(identity.sourceCommit)}, ${JSON.stringify(identity.projectionSha256)}, ${JSON.stringify(identity.catalogContentVersion)})) { finishCorpusFailure(runId, "paired_capture_start_failed"); return; }`;
    let result = replaceOne(source, '        resetCorpusCounters();', '        resetCorpusCounters();\n        ' + begin);
    if (identity.captureControlUri) {
        result = replaceOne(result, '        resetCorpusCounters();',
            '        resetCorpusCounters();\n        org.flashNight.gesh.tooltip.test.TooltipCaptureControl.configure(' + JSON.stringify(identity.captureControlUri) + ');');
        result = replaceOne(result, '        if (state == null) return;\n        var started:Number = getTimer();',
            '        if (state == null) return;\n        if (org.flashNight.gesh.tooltip.test.TooltipCaptureControl.poll(state.runId, _recordSequence, ' + captureClass + '.captureCount())) return;\n        var started:Number = getTimer();');
    }
    result = replaceOne(result, '        trace("TOOLTIP_CORPUS_FAILED|"',
        `        ${captureClass}.failure(reason);\n        ${captureClass}.finish();\n        trace("TOOLTIP_CORPUS_FAILED|"`);
    result = replaceOne(result, '        trace("TOOLTIP_CORPUS_DONE|"',
        `        ${captureClass}.captureEnhancedInstances();\n        ${captureClass}.finish();\n        trace("TOOLTIP_CORPUS_DONE|"`);
    result = replaceOne(result, '        _recordSequence++;', `        _recordSequence++;
        // Offline paired capture: the same real instance and legal mod/tier path.
        ${captureClass}.captureInventory(
            "inventory:" + _recordSequence + ":" + variant + ":" + sourceItem.name,
            baseItem == null ? {name:sourceItem.name,value:1} : baseItem);
        if (variant == "base") ${captureClass}.captureWeb(
            "web:" + _recordSequence + ":" + sourceItem.name, sourceItem.name);`);
    return result;
}

function instrumentTemplate(source) {
    // This is the OLD frame source in the pinned target worktree. It installs
    // the real original Web producer; no expected content is copied into JS.
    return '\uFEFFimport org.flashNight.arki.item.*;\n' +
        'import org.flashNight.gesh.tooltip.*;\n' +
        '#include "展现/UI交互/UI交互_鸡蛋_fs_aka_物品图标注释.as"\n' + source.replace(/^\uFEFF/, '');
}

function prepareBaseline(target, dryRun) {
    target = fs.realpathSync(target);
    if (target === fs.realpathSync(repo)) throw new Error('refusing to install oracle into the candidate repository');
    if (!fs.lstatSync(path.join(target, '.git')).isFile()) throw new Error('use an isolated linked baseline worktree, not the primary checkout');
    const git = args => cp.execFileSync('git', ['-C', target, ...args], {encoding: 'utf8'}).trim();
    if (git(['rev-parse', '--show-toplevel']) !== target.replace(/\\/g, '/')) {
        // Git may preserve a Windows drive's case; compare canonical real paths.
        if (fs.realpathSync(git(['rev-parse', '--show-toplevel'])) !== target) throw new Error('target must be a repository root');
    }
    if (git(['rev-parse', 'HEAD']) !== manifest.sourceCommit) throw new Error('target HEAD differs from pinned baseline ' + manifest.sourceCommit);
    if (git(['status', '--porcelain']).length) throw new Error('target is not clean; use a fresh disposable baseline worktree');
    for (const [relative, entry] of Object.entries(manifest.files)) {
        if (sha256(fs.readFileSync(path.join(target, relative))) !== entry.sha256) throw new Error('oracle baseline source hash mismatch: ' + relative);
    }
    for (const required of ['scripts/run-tooltip-corpus-audit.ps1', 'scripts/compile_test.ps1',
        'scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as',
        'scripts/展现/UI交互/UI交互_鸡蛋_fs_aka_物品图标注释.as', templatePath]) {
        if (!fs.existsSync(path.join(target, required))) throw new Error('baseline file missing: ' + required);
    }
    const projection = fs.readFileSync(path.join(repo, projectionPath));
    const collector = fs.readFileSync(path.join(__dirname, 'as2/org/flashNight/gesh/tooltip/test/TooltipPairedCapture.as'));
    const captureJson = fs.readFileSync(path.join(__dirname, 'as2/org/flashNight/gesh/tooltip/test/TooltipCaptureJson.as'));
    const captureControl = fs.readFileSync(path.join(__dirname, 'as2/org/flashNight/gesh/tooltip/test/TooltipCaptureControl.as'));
    const catalog = JSON.parse(fs.readFileSync(path.join(repo, 'data/tooltip/tooltip-catalog.json'), 'utf8'));
    const captureControlUri = 'file:///' + target.replace(/\\/g, '/') + '/tmp/tooltip-paired-capture/output-control.xml';
    const identity = {sourceCommit: manifest.sourceCommit, projectionSha256: sha256(projection), catalogContentVersion: catalog.contentVersion, captureControlUri};
    const edits = [
        [projectionPath, projection], [capturePath, collector], [captureJsonPath, captureJson], [captureControlPath, captureControl],
        [corpusPath, Buffer.from(instrumentCorpus(fs.readFileSync(path.join(target, corpusPath), 'utf8'), identity))],
        [templatePath, Buffer.from(instrumentTemplate(fs.readFileSync(path.join(target, templatePath), 'utf8')))]
    ];
    for (const [relative, bytes] of edits) {
        if (!bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf]))) throw new Error('prepared AS2 source lacks BOM: ' + relative);
        if (!dryRun) { fs.mkdirSync(path.dirname(path.join(target, relative)), {recursive: true}); fs.writeFileSync(path.join(target, relative), bytes); }
    }
    const report = {schema: 'cf7.tooltip-capture-setup.v1', ...identity, candidateRoot: repo, target,
        status: dryRun ? 'validated-only' : 'sources-prepared-not-compiled',
        files: Object.fromEntries(edits.map(([relative, bytes]) => [relative, sha256(bytes)])),
        limitation: 'No CS6/AVM1 execution has occurred. Run the baseline focused runner, then convert its complete trace.'};
    if (!dryRun) {
        const destination = path.join(target, 'tmp/tooltip-paired-capture/setup.json');
        fs.mkdirSync(path.dirname(destination), {recursive: true});
        fs.writeFileSync(destination, JSON.stringify(report, null, 2) + '\n');
        fs.writeFileSync(path.join(target, 'tmp/tooltip-paired-capture/output-control.xml'), '<captureControl state="run"/>\n', {flag:'wx'});
    }
    return report;
}

function main(args) {
    let target, dryRun = false;
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--baseline') target = args[++i];
        else if (args[i] === '--dry-run') dryRun = true;
        else throw new Error('usage: prepare-baseline.cjs --baseline <clean baseline worktree> [--dry-run]');
    }
    if (!target) throw new Error('--baseline is required');
    process.stdout.write(JSON.stringify(prepareBaseline(target, dryRun), null, 2) + '\n');
}
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
module.exports = {instrumentCorpus, instrumentTemplate, prepareBaseline};
