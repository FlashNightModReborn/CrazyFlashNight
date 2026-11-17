#!/usr/bin/env node
'use strict';

// Protocol conversion only: the trace supplies every expected value. Incomplete,
// failed, duplicate or mismatched runs cannot be promoted to an oracle artifact.
const fs = require('node:fs');
const crypto = require('node:crypto');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function convertTrace(trace, requestedRunId) {
    const runs = new Map();
    for (const line of trace.replace(/^\uFEFF/, '').split(/\r?\n/)) {
        if (line.startsWith('TC_INPUT_BEGIN|')) {
            const header = JSON.parse(line.slice('TC_INPUT_BEGIN|'.length));
            if (!header || typeof header.runId !== 'string' || !header.runId || runs.has(header.runId)) throw new Error('missing/duplicate capture begin');
            const p = header.provenance;
            if (!p || p.kind !== 'avm1-capture' || !/^[a-f0-9]{40}$/i.test(p.sourceCommit || '') ||
                typeof p.capturedAt !== 'string' || !Number.isFinite(Date.parse(p.capturedAt)) ||
                !/^[a-f0-9]{64}$/i.test(p.inputProjectionSha256 || '') || typeof p.catalogContentVersion !== 'string' || !p.catalogContentVersion) {
                throw new Error('invalid runtime capture provenance');
            }
            runs.set(header.runId, {header, records: [], ids: new Set(), errors: [], end: null});
        } else if (line.startsWith('TC_INPUT|') || line.startsWith('TC_INPUT_ERROR|')) {
            const prefix = line.startsWith('TC_INPUT|') ? 'TC_INPUT|' : 'TC_INPUT_ERROR|';
            const separator = line.indexOf('|', prefix.length);
            if (separator < 0) throw new Error('malformed capture row');
            const run = runs.get(line.slice(prefix.length, separator));
            if (!run || run.end) throw new Error('capture row outside a live run');
            const data = JSON.parse(line.slice(separator + 1));
            if (prefix === 'TC_INPUT_ERROR|') { run.errors.push(data); continue; }
            if (!data || typeof data.id !== 'string' || !data.id || run.ids.has(data.id) ||
                !data.input || typeof data.input !== 'object' || Array.isArray(data.input) || data.input.version !== 1 ||
                !data.expectedDocument || typeof data.expectedDocument !== 'object' || Array.isArray(data.expectedDocument) || data.expectedDocument.version !== 1) {
                throw new Error('invalid/duplicate paired record');
            }
            for (const key of ['expectedIntroHTML', 'expectedDescHTML', 'expectedDetails']) {
                if (Object.hasOwn(data, key) && typeof data[key] !== 'string') throw new Error('non-string expected content: ' + key);
            }
            run.ids.add(data.id); run.records.push(data);
        } else if (line.startsWith('TC_INPUT_END|')) {
            const end = JSON.parse(line.slice('TC_INPUT_END|'.length));
            const run = runs.get(end.runId);
            if (!run || run.end) throw new Error('capture end without one live begin');
            run.end = end;
        }
    }
    if (requestedRunId == null && runs.size !== 1) throw new Error('trace needs exactly one run, or select one with --run-id');
    const run = requestedRunId == null ? runs.values().next().value : runs.get(requestedRunId);
    if (!run || !run.end) throw new Error('requested capture is absent or incomplete');
    if (run.errors.length || run.end.failures !== 0) throw new Error('AVM1 capture reported errors: ' + JSON.stringify(run.errors));
    if (!run.records.length || run.end.records !== run.records.length) throw new Error('capture record count does not match footer');
    return {schema: 'cf7.tooltip-content-oracle.v1', provenance: {...run.header.provenance,
        runId: run.header.runId, traceSha256: hash(Buffer.from(trace))}, records: run.records};
}

function main(args) {
    let input, output, runId;
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--run-id') runId = args[++i];
        else if (args[i] === '--output') output = args[++i];
        else if (!input && !args[i].startsWith('--')) input = args[i];
        else throw new Error('usage: trace-to-oracle.cjs capture.trace --output oracle.json [--run-id id]');
    }
    if (!input || !output) throw new Error('input trace and --output are required');
    const corpus = convertTrace(fs.readFileSync(input, 'utf8'), runId);
    // Refuse accidental replacement of an independent captured artifact.
    fs.writeFileSync(output, JSON.stringify(corpus, null, 2) + '\n', {flag: 'wx'});
    process.stdout.write(JSON.stringify({status: 'converted-runtime-trace', records: corpus.records.length,
        sourceCommit: corpus.provenance.sourceCommit, runId: corpus.provenance.runId, output}) + '\n');
}
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
module.exports = {convertTrace};
