#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const input = path.resolve(ROOT, process.argv[2] || 'tmp/tooltip-audit/tooltip-corpus.trace');
const output = path.resolve(ROOT, process.argv[3] || 'tmp/tooltip-audit/tooltip-corpus.json');

function fail(message) { throw new Error(message); }
function number(value, label) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) fail('Invalid numeric ' + label + ': ' + value);
    return parsed;
}
function html(value) {
    return String(value || '').replace(/¶/g, '\n').replace(/¤/g, '\r');
}
function plainLength(value) {
    return String(value || '').replace(/<[^>]*>/g, '').replace(/&[^;]+;/g, ' ').length;
}
function percentile(values, ratio) {
    if (!values.length) return 0;
    const sorted = values.slice().sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * ratio))];
}

if (!fs.existsSync(input)) fail('Tooltip corpus trace is missing: ' + input);
const text = fs.readFileSync(input, 'utf8');
const lines = text.split(/\r?\n/);
const records = [];
for (const line of lines) {
    if (!line.startsWith('TC_ITEM|')) continue;
    const parts = line.split('|');
    if (parts.length !== 16) fail('TC_ITEM column count must be 16, got ' + parts.length);
    const record = {
        id:number(parts[1], 'id'),
        variant:parts[2],
        name:parts[3],
        displayName:parts[4],
        type:parts[5],
        use:parts[6],
        tier:parts[7],
        mods:parts[8] ? parts[8].split(',') : [],
        icon:parts[9],
        modslot:parts[10] === '' ? null : number(parts[10], 'modslot'),
        tierOptions:number(parts[11], 'tierOptions'),
        authorChars:number(parts[12], 'authorChars'),
        split:parts[13] === '1',
        introHTML:html(parts[14]),
        descHTML:html(parts[15])
    };
    record.introChars = plainLength(record.introHTML);
    record.descChars = plainLength(record.descHTML);
    records.push(record);
}

const coverageMatch = text.match(/^TC_MOD_COVERAGE\|definitions=(\d+)\|covered=(\d+)\|records=(\d+)\|uncovered=(\d+)\|names=([^\r\n]*)\r?$/m);
if (!coverageMatch) fail('TC_MOD_COVERAGE summary missing');
const totalMatch = text.match(/^TC_TOTAL\|records=(\d+)\|base=(\d+)\|equipment=(\d+)\|tiers=(\d+)\|mods1=(\d+)\|mods3=(\d+)\|modCoverage=(\d+)\|modDefinitions=(\d+)\|modsCovered=(\d+)\|composeFailures=(\d+)\r?$/m);
if (!totalMatch) fail('TC_TOTAL summary missing');
const summary = {
    records:number(totalMatch[1], 'records'),
    base:number(totalMatch[2], 'base'),
    equipment:number(totalMatch[3], 'equipment'),
    tiers:number(totalMatch[4], 'tiers'),
    mods1:number(totalMatch[5], 'mods1'),
    mods3:number(totalMatch[6], 'mods3'),
    modCoverage:number(totalMatch[7], 'modCoverage'),
    modDefinitions:number(totalMatch[8], 'modDefinitions'),
    modsCovered:number(totalMatch[9], 'modsCovered'),
    composeFailures:number(totalMatch[10], 'composeFailures')
};
if (summary.records !== records.length) fail('TC_TOTAL record count mismatch');
if (summary.composeFailures !== 0) fail('Corpus contains composition failures');
const coverage = {
    definitions:number(coverageMatch[1], 'coverage definitions'),
    covered:number(coverageMatch[2], 'coverage covered'),
    records:number(coverageMatch[3], 'coverage records'),
    uncovered:number(coverageMatch[4], 'coverage uncovered'),
    names:coverageMatch[5] ? coverageMatch[5].split(',').filter(Boolean) : []
};
if (coverage.definitions <= 0 || coverage.covered !== coverage.definitions
        || coverage.uncovered !== 0 || coverage.names.length !== 0
        || coverage.records !== summary.modCoverage
        || coverage.definitions !== summary.modDefinitions
        || coverage.covered !== summary.modsCovered) {
    fail('Installed mod definition coverage is incomplete or inconsistent');
}
const variants = records.reduce((counts, record) => {
    counts[record.variant] = (counts[record.variant] || 0) + 1;
    return counts;
}, {});
if (variants.base !== summary.base || variants.tier !== summary.tiers
        || variants['mods-1'] !== summary.mods1 || variants['mods-3'] !== summary.mods3
        || variants['mods-cover'] !== summary.modCoverage) {
    fail('Variant counts do not match TC_TOTAL');
}
for (let index = 0; index < records.length; index += 1) {
    if (records[index].id !== index + 1) fail('Corpus ids are not contiguous at ' + (index + 1));
}

const descLengths = records.map(record => record.descChars);
const introLengths = records.map(record => record.introChars);
const stats = {
    variants,
    split:records.filter(record => record.split).length,
    descChars:{p50:percentile(descLengths, .5),p90:percentile(descLengths, .9),p99:percentile(descLengths, .99),max:Math.max(...descLengths)},
    introChars:{p50:percentile(introLengths, .5),p90:percentile(introLengths, .9),p99:percentile(introLengths, .99),max:Math.max(...introLengths)}
};

fs.mkdirSync(path.dirname(output), {recursive:true});
fs.writeFileSync(output, JSON.stringify({schema:'cf7.tooltip-corpus.v1',summary,coverage,stats,records}), 'utf8');
process.stdout.write(JSON.stringify({input,output,summary,coverage,stats}, null, 2) + '\n');
