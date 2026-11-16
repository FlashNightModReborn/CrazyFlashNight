#!/usr/bin/env node
'use strict';
// This runner only consumes independent AVM1 expected results. It never writes
// expected output and never turns synthetic/source-defined fixtures into truth.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const crypto = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
const { repo, defaultCatalog } = require('./fixtures.cjs');
function comparisonValues(record, actual, engine) {
    const values = { document: actual.document, introHTML: actual.introHTML,
        descHTML: actual.descHTML, details: actual.details };
    // captureWeb's expectedDetails is the old Web HTML converted to plain text.
    // Reward details have a separate, unchanged full-inline content contract.
    // Compare both contracts without changing or dropping any captured value.
    if (record.input.kind === 'item' && record.input.presentation === 'web' && record.input.output !== 'details') {
        values.details = engine.plainText(actual.introHTML + actual.descHTML).substr(0, 4096);
    }
    return values;
}
function main(args) {
    let filename, current, catalogPath = defaultCatalog;
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--current') current = args[++i];
        else if (args[i] === '--catalog') catalogPath = args[++i];
        else if (!filename && !args[i].startsWith('--')) filename = args[i];
        else throw new Error('usage: parity.cjs oracle.json [--current <40-char-source-commit>] [--catalog catalog.json]');
    }
    if (!filename || !fs.existsSync(filename)) {
        process.stdout.write(JSON.stringify({ status: 'oracle-unavailable', compared: 0,
            reason: 'Provide an independent AVM1 capture containing TooltipInput and expectedDocument. No fresh parity is claimed.' }) + '\n');
        return 2;
    }
    const raw = fs.readFileSync(filename);
    const corpus = JSON.parse(raw.toString('utf8'));
    const p = corpus.provenance;
    if (corpus.schema !== 'cf7.tooltip-content-oracle.v1' || !p ||
        !['avm1-capture', 'historical-avm1'].includes(p.kind) ||
        !/^[a-f0-9]{40}$/i.test(p.sourceCommit || '') ||
        typeof p.capturedAt !== 'string' || !Number.isFinite(Date.parse(p.capturedAt))) {
        throw new Error('invalid independent-oracle provenance/schema');
    }
    if (current != null && !/^[a-f0-9]{40}$/i.test(current)) throw new Error('invalid --current source commit');
    if (!Array.isArray(corpus.records) || corpus.records.length === 0) throw new Error('oracle records must be nonempty');
    const catalogText = fs.readFileSync(catalogPath, 'utf8');
    const catalog = JSON.parse(catalogText);
    if (p.catalogContentVersion && p.catalogContentVersion !== catalog.contentVersion) throw new Error('oracle catalogContentVersion differs from supplied catalog');
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(repo, 'launcher/scripts/dist/tooltip-bundle.js'), 'utf8'), context);
    context.TooltipEngine.initCatalog(catalogText);
    const failures = [];
    const ids = new Set();
    let compared = 0;
    for (const record of corpus.records) {
        if (!record || typeof record.id !== 'string' || !record.id || ids.has(record.id) ||
            !record.input || !record.expectedDocument || typeof record.expectedDocument !== 'object') {
            throw new Error('every oracle record needs a unique id, input and independent expectedDocument');
        }
        ids.add(record.id);
        let actual;
        try {
            // Compare a complete build even for a details consumer; output is a
            // transport selector and does not change the content rules.
            const input = { ...record.input }; delete input.output;
            actual = JSON.parse(context.TooltipEngine.buildProjectionJson(JSON.stringify(input)));
        } catch (error) {
            failures.push({ id: record.id, field: 'build', error: String(error.message || error) });
            compared++;
            continue;
        }
        const values = comparisonValues(record, actual, context.TooltipEngine);
        for (const [expectedKey, actualKey] of [['expectedDocument', 'document'], ['expectedIntroHTML', 'introHTML'], ['expectedDescHTML', 'descHTML'], ['expectedDetails', 'details']]) {
            if (Object.prototype.hasOwnProperty.call(record, expectedKey) && !isDeepStrictEqual(record[expectedKey], values[actualKey])) {
                failures.push({ id: record.id, field: actualKey });
            }
        }
        compared++;
    }
    const fresh = p.kind === 'avm1-capture' && current != null && p.sourceCommit.toLowerCase() === current.toLowerCase();
    const provenanceMismatch = current != null && p.sourceCommit.toLowerCase() !== current.toLowerCase();
    process.stdout.write(JSON.stringify({
        status: failures.length ? 'different' : provenanceMismatch ? 'source-commit-mismatch' : fresh ? 'fresh-avm1-match' : 'historical-avm1-match',
        compared, failures: failures.slice(0, 100), failureCount: failures.length,
        provenance: p, requestedCurrent: current || null,
        corpusSha256: crypto.createHash('sha256').update(raw).digest('hex'),
        catalogContentVersion: catalog.contentVersion,
        detailsComparison: 'Web capture plaintext uses legacy Web HTML; inventory/details consumers use full-inline reward details.',
        limitation: fresh ? 'Result is limited to the supplied independent capture records.' : 'A matching current source commit was not verified; this result does not establish fresh AS2 parity.'
    }, null, 2) + '\n');
    return failures.length || provenanceMismatch ? 1 : 0;
}
if (require.main === module) {
    try { process.exitCode = main(process.argv.slice(2)); }
    catch (error) { process.stderr.write(String(error.stack || error) + '\n'); process.exitCode = 1; }
}
module.exports = { main, comparisonValues };
