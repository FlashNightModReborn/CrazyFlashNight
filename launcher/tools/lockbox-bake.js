#!/usr/bin/env node
'use strict';

var fs = require('fs');
var path = require('path');
var core = require('../web/modules/lockbox-core.js');
var generator = require('../web/modules/lockbox-generator.js');

var args = process.argv.slice(2);
var seedCount = parseInt(readArg('--seeds', '10000'), 10);
var variantsPerFamily = parseInt(readArg('--variants', '3'), 10);
var profiles = readArg('--profiles', 'standard,elite6,elite7').split(',').filter(Boolean);
var outPath = path.resolve(__dirname, '../web/data/lockbox-variants.json');

function readArg(name, fallback) {
    var idx = args.indexOf(name);
    if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
    return fallback;
}

function percentile(values, pct) {
    if (!values.length) return 0;
    var sorted = values.slice().sort(function(a, b) { return a - b; });
    var index = Math.min(sorted.length - 1, Math.floor((pct / 100) * sorted.length));
    return sorted[index];
}

function runFuzz(profileId, count) {
    var attempts = [];
    var accepted = 0;
    var bonusShareSum = 0;
    var mainMinSum = 0;
    var entryStartSum = 0;

    for (var i = 0; i < count; i++) {
        var familySeed = core.mixSeed(0x5eed1234, i + profileId.length * 97);
        var variantIndex = i % 3;
        var generated = generator.generatePuzzle(profileId, familySeed, variantIndex, { maxAttempts: 320 });
        attempts.push(generated.puzzle.attemptCount || 0);
        if (generated.puzzle.accepted !== false) accepted++;
        bonusShareSum += generated.report.bonusShare || 0;
        mainMinSum += generated.report.mainSolutionCountMinLen || 0;
        entryStartSum += generated.report.entryStartCount || 0;
    }

    return {
        profile: profileId,
        seeds: count,
        accepted: accepted,
        acceptedRate: count ? accepted / count : 0,
        avgAttempts: mean(attempts),
        p95Attempts: percentile(attempts, 95),
        avgBonusShare: count ? bonusShareSum / count : 0,
        avgMainSolutionCountMinLen: count ? mainMinSum / count : 0,
        avgEntryStartCount: count ? entryStartSum / count : 0
    };
}

function mean(values) {
    if (!values.length) return 0;
    var total = 0;
    for (var i = 0; i < values.length; i++) total += values[i];
    return total / values.length;
}

function buildVariantPool(profileIds, perFamily) {
    var pool = [];
    for (var p = 0; p < profileIds.length; p++) {
        var familySeed = core.mixSeed(0x4c4f434b + p * 131, 1);
        for (var v = 0; v < perFamily; v++) {
            var generated = generator.generatePuzzle(profileIds[p], familySeed, v, { maxAttempts: 400 });
            pool.push({
                familySeed: familySeed >>> 0,
                variantIndex: v,
                tier: profileIds[p],
                config: generated.config,
                puzzle: generated.puzzle,
                report: generated.report
            });
        }
    }
    return pool;
}

function main() {
    console.log('[lockbox-bake] fuzz seeds per profile = ' + seedCount);
    var summaries = [];
    for (var i = 0; i < profiles.length; i++) {
        console.log('[lockbox-bake] fuzz -> ' + profiles[i]);
        var summary = runFuzz(profiles[i], seedCount);
        summaries.push(summary);
        console.log(JSON.stringify(summary));
    }

    var variantPool = buildVariantPool(profiles, variantsPerFamily);
    var payload = {
        PuzzleConfig: { note: 'Per-variant config object lives in variantPool[].config' },
        PuzzleInstance: { note: 'Per-variant puzzle instance lives in variantPool[].puzzle' },
        SolveReport: { note: 'Per-variant solver report lives in variantPool[].report' },
        variantPool: variantPool,
        fuzzSummary: summaries,
        generatedAt: new Date().toISOString()
    };

    fs.writeFileSync(outPath, JSON.stringify(payload, null, 2), 'utf8');
    console.log('[lockbox-bake] wrote ' + outPath);
}

main();
