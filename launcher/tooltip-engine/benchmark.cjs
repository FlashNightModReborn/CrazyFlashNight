#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const { performance } = require('node:perf_hooks');
const { createInputs, catalogText, repo } = require('./fixtures.cjs');
const hash = x => crypto.createHash('sha256').update(x).digest('hex');
const round = x => Math.round(x * 1e6) / 1e6;
function summarize(values) {
    const sorted = values.slice().sort((a, b) => a - b);
    const at = q => sorted[Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1)];
    return { count: sorted.length, mean: round(sorted.reduce((sum, x) => sum + x, 0) / sorted.length),
        p50: round(at(.5)), p95: round(at(.95)), p99: round(at(.99)), max: round(sorted[sorted.length - 1]) };
}
function collect() {
    if (global.gc) global.gc();
    const { heapUsed, heapTotal, rss, external } = process.memoryUsage();
    return { heapUsed, heapTotal, rss, external };
}
function delta(a, b) { return Object.fromEntries(Object.keys(a).map(key => [key, b[key] - a[key]])); }
function main() {
    const args = process.argv.slice(2);
    const evaluate = args[0] === '--evaluate';
    if (evaluate) args.shift();
    if (args[0] === '--bench') args.shift();
    if (args.length > 2 || (evaluate && args.length !== 1)) throw new Error('usage: benchmark.cjs [--bench] [inputs.jsonl] [rounds] | --evaluate inputs.jsonl');
    const rounds = args[1] == null ? 3 : Number(args[1]);
    if (!Number.isInteger(rounds) || rounds < 1 || rounds > 100) throw new Error('rounds must be 1..100');
    const catalogBytes = Buffer.from(catalogText(),'utf8');
    const bundleBytes = fs.readFileSync(path.join(repo, 'launcher/scripts/dist/tooltip-bundle.js'));
    const fixtureText = args[0] ? fs.readFileSync(args[0], 'utf8') :
        createInputs(JSON.parse(catalogBytes.toString('utf8'))).map(input => JSON.stringify(input)).join('\n') + '\n';
    const inputs = fixtureText.split(/\r?\n/).filter(x => x.trim());
    if (!inputs.length) throw new Error('empty input corpus');
    const memoryBefore = collect();
    const initStart = performance.now();
    const sandbox = vm.createContext({});
    vm.runInContext(bundleBytes.toString('utf8'), sandbox, { filename: 'tooltip-bundle.js' });
    const bundleEnd = performance.now();
    const E = sandbox.TooltipEngine;
    const contentVersion = E.initCatalog(catalogBytes.toString('utf8'));
    const catalogEnd = performance.now();
    const memoryInitialized = collect();
    if (evaluate) {
        for (const input of inputs) process.stdout.write(E.buildProjectionJson(input) + '\n');
        return;
    }
    let outputChars = 0;
    const firstStart = performance.now();
    outputChars += E.buildProjectionJson(inputs[0]).length;
    const firstCallMs = performance.now() - firstStart;
    const warmupCount = Math.min(1000, inputs.length * 2);
    for (let i = 0; i < warmupCount; i++) outputChars += E.buildProjectionJson(inputs[i % inputs.length]).length;
    const cpuStart = process.cpuUsage();
    const samples = [];
    const measuredStart = performance.now();
    for (let roundIndex = 0; roundIndex < rounds; roundIndex++) {
        for (const input of inputs) {
            const start = performance.now();
            outputChars += E.buildProjectionJson(input).length;
            samples.push(performance.now() - start);
        }
    }
    const measuredMs = performance.now() - measuredStart;
    const cpu = process.cpuUsage(cpuStart);
    const batchMs = {};
    for (const size of [25, 100]) {
        const samples = [];
        for (let run = 0; run < 20; run++) {
            const start = performance.now();
            for (let i = 0; i < size; i++) outputChars += E.buildProjectionJson(inputs[(run * size + i) % inputs.length]).length;
            samples.push(performance.now() - start);
        }
        batchMs[size] = summarize(samples);
    }
    const memoryAfter = collect();
    process.stdout.write(JSON.stringify({
        schema: 'cf7.tooltip-content-benchmark.v1',
        evidence: args[0] ? 'supplied-inputs; no AVM1 equivalence inferred' : 'synthetic-projections; not an AVM1 oracle',
        runtime: { node: process.version, v8: process.versions.v8, platform: process.platform, arch: process.arch },
        catalog: { contentVersion, sha256: hash(catalogBytes), bytes: catalogBytes.length },
        bundle: { sha256: hash(bundleBytes), bytes: bundleBytes.length },
        input: { file: args[0] ? path.resolve(args[0]) : null, sha256: hash(fixtureText), count: inputs.length },
        initializationMs: { vmAndBundle: round(bundleEnd - initStart), catalogParseValidateFreeze: round(catalogEnd - bundleEnd), total: round(catalogEnd - initStart) },
        firstCallMs: round(firstCallMs), warmupCount, rounds,
        perCallMs: summarize(samples), batchMs, measuredMs: round(measuredMs), cpuMs: { user: cpu.user / 1000, system: cpu.system / 1000 },
        memoryBytes: { gcRequested: !!global.gc, before: memoryBefore, initialized: memoryInitialized, after: memoryAfter,
            catalogAndBundleDelta: delta(memoryBefore, memoryInitialized), totalDelta: delta(memoryBefore, memoryAfter) },
        outputChars,
        limits: 'Node process measurements; includes JSON input parsing, document/HTML composition and JSON output. Does not include host scheduling, cache, IPC or Flash projection. Memory deltas include V8/JIT overhead and are not retained-object accounting.'
    }, null, 2) + '\n');
}
if (require.main === module) {
    try { main(); } catch (error) { process.stderr.write(String(error.stack || error) + '\n'); process.exitCode = 1; }
}
module.exports = { summarize };
