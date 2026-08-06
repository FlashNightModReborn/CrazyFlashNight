#!/usr/bin/env node
'use strict';

const assert = require('assert');
const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const BUILDER = path.join(ROOT, 'tools', 'build-crafting-product-review.js');
const REVIEW_TEST = path.join(ROOT, 'tools', 'test-crafting-product-review.js');
const GATE_ROOT = path.join(ROOT, 'tmp', 'identity-triple-gate');
const TOKEN = process.pid + '-' + Date.now().toString(36);

function relative(filePath) {
    return path.relative(ROOT, filePath);
}

function run(script, args) {
    return childProcess.spawnSync(process.execPath, [script].concat(args || []), {
        cwd: ROOT,
        encoding: 'utf8'
    });
}

function cleanupResult(target, extraArgs) {
    return run(BUILDER, ['--cleanup-output-root', relative(target)].concat(extraArgs || []));
}

function expectCleanupFailure(label, target, pattern, extraArgs) {
    const result = cleanupResult(target, extraArgs);
    assert.notStrictEqual(result.status, 0, label + ' unexpectedly succeeded');
    assert(pattern.test(String(result.stderr || '') + String(result.stdout || '')),
        label + ' failed for the wrong reason: ' + result.stderr);
}

function owned(name) {
    assert(name.startsWith('crafting-product-review-'));
    return path.join(GATE_ROOT, name);
}

function removeExact(target) {
    const resolved = path.resolve(target);
    const relativeToGate = path.relative(GATE_ROOT, resolved);
    if (!relativeToGate || relativeToGate.startsWith('..' + path.sep)
            || path.isAbsolute(relativeToGate)
            || !path.basename(resolved).startsWith('crafting-product-review-')) {
        throw new Error('unsafe test cleanup target: ' + resolved);
    }
    if (fs.existsSync(resolved)) {
        const stat = fs.lstatSync(resolved);
        if (stat.isSymbolicLink()) fs.unlinkSync(resolved);
        else fs.rmSync(path.toNamespacedPath(resolved), {recursive:true, force:true});
    }
}

function main() {
    fs.mkdirSync(GATE_ROOT, {recursive:true});
    const missing = owned('crafting-product-review-missing-' + TOKEN);
    const symlinkTarget = owned('crafting-product-review-symlink-target-' + TOKEN);
    const symlink = owned('crafting-product-review-symlink-' + TOKEN);
    const regularFile = owned('crafting-product-review-file-' + TOKEN);
    const longTree = owned('crafting-product-review-long-tree-' + TOKEN);
    const failedPipeline = owned('crafting-product-review-failed-pipeline-' + TOKEN);
    const cleanupTargets = [symlink, symlinkTarget, regularFile, longTree, failedPipeline];
    let passed = 0;
    try {
        expectCleanupFailure('default review root', path.join(ROOT, 'tmp', 'crafting-product-review'),
            /unique Crafting review child/); passed += 1;
        expectCleanupFailure('tmp root', path.join(ROOT, 'tmp'),
            /unique Crafting review child/); passed += 1;
        expectCleanupFailure('gate root', GATE_ROOT,
            /unique Crafting review child/); passed += 1;
        expectCleanupFailure('escaped root', path.join(ROOT, '..', 'crafting-product-review-escape'),
            /unique Crafting review child/); passed += 1;
        expectCleanupFailure('missing isolated root', missing,
            /target does not exist/); passed += 1;
        expectCleanupFailure('mixed cleanup and build mode', missing,
            /isolated mode/, ['--sample']); passed += 1;

        fs.mkdirSync(symlinkTarget);
        fs.symlinkSync(symlinkTarget, symlink, process.platform === 'win32' ? 'junction' : 'dir');
        expectCleanupFailure('symlink root', symlink,
            /refuses symlinks/); passed += 1;
        assert(fs.existsSync(symlink) && fs.existsSync(symlinkTarget));
        removeExact(symlink);
        removeExact(symlinkTarget);

        fs.writeFileSync(regularFile, 'not a directory');
        expectCleanupFailure('regular file root', regularFile,
            /non-directories/); passed += 1;
        fs.unlinkSync(regularFile);

        const longLeaf = 'CLIPACTIONRECORD onClipEvent(enterFrame)-' + 'x'.repeat(92) + '.as';
        const deep = path.join(longTree,
            'DefineSprite_562_刀-勇气灵剑', 'frame_1',
            'PlaceObject2_561_52-' + 'y'.repeat(92));
        fs.mkdirSync(path.toNamespacedPath(deep), {recursive:true});
        fs.writeFileSync(path.toNamespacedPath(path.join(deep, longLeaf)), 'probe');
        const longCleanup = cleanupResult(longTree);
        assert.strictEqual(longCleanup.status, 0, longCleanup.stderr);
        assert(!fs.existsSync(longTree)); passed += 1;

        fs.mkdirSync(failedPipeline);
        const failedReview = run(REVIEW_TEST, [
            '--review-data', relative(path.join(failedPipeline, 'missing-review-data.json'))
        ]);
        assert.notStrictEqual(failedReview.status, 0, 'synthetic failed review unexpectedly passed');
        assert(/missing review data/.test(String(failedReview.stderr || '') + String(failedReview.stdout || '')));
        const failureCleanup = cleanupResult(failedPipeline);
        assert.strictEqual(failureCleanup.status, 0, failureCleanup.stderr);
        assert(!fs.existsSync(failedPipeline)); passed += 1;

        console.log('Crafting product review isolated cleanup ' + passed + '/10 passed');
    } finally {
        cleanupTargets.forEach(removeExact);
    }
}

main();
