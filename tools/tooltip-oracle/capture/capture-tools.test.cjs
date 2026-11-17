#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {instrumentCorpus, instrumentTemplate} = require('./prepare-baseline.cjs');
const {convertTrace} = require('./trace-to-oracle.cjs');
const {comparisonValues} = require('../../../launcher/tooltip-engine/parity.cjs');
const oracleRoot = path.resolve(__dirname, '..');
const identity = {sourceCommit:'a'.repeat(40), projectionSha256:'b'.repeat(64), catalogContentVersion:'fixture-only'};
const original = fs.readFileSync(path.join(oracleRoot, 'as2/org/flashNight/gesh/tooltip/test/TooltipCorpusDump.as'), 'utf8');
const patched = instrumentCorpus(original, identity);
assert(patched.includes('TooltipPairedCapture.captureInventory('));
assert(patched.includes('TooltipPairedCapture.captureWeb('));
assert(patched.includes('if (!org.flashNight.gesh.tooltip.test.TooltipPairedCapture.begin('));
assert(patched.includes('finishCorpusFailure(runId, "paired_capture_start_failed"); return;'));
assert.equal((patched.match(/TooltipPairedCapture\.finish\(\)/g) || []).length, 2);
assert.throws(() => instrumentCorpus(patched, identity), /anchor/);
const coordinated = instrumentCorpus(original,{...identity,captureControlUri:'file:///C|/fixture/output-control.xml'});
assert(coordinated.includes('TooltipCaptureControl.configure("file:///C|/fixture/output-control.xml")'));
assert(coordinated.includes('TooltipCaptureControl.poll(state.runId, _recordSequence,'));
const template = instrumentTemplate(fs.readFileSync(path.join(oracleRoot, 'runners/tooltip-corpus-TestLoader.as.template'), 'utf8'));
assert.equal((template.match(/__FOCUSED_RUN_ID__/g) || []).length, 2);
assert(template.includes('#include "展现/UI交互/UI交互_鸡蛋_fs_aka_物品图标注释.as"'));

// These are fake protocol rows, never saved as an AVM1 truth file.
const header = {runId:'fixture-run',provenance:{kind:'avm1-capture',sourceCommit:identity.sourceCommit,
    inputProjectionSha256:identity.projectionSha256,catalogContentVersion:identity.catalogContentVersion,
    capturedAt:'2026-11-15T00:00:00.000Z'}};
const row = {id:'fixture',input:{version:1,kind:'body',html:'<B>literal</B>'},
    expectedDocument:{version:1,profile:'simple',sections:[]},expectedIntroHTML:'',expectedDescHTML:'<B>literal</B>'};
const begin = 'TC_INPUT_BEGIN|' + JSON.stringify(header);
const record = 'TC_INPUT|fixture-run|' + JSON.stringify(row);
const end = 'TC_INPUT_END|' + JSON.stringify({runId:'fixture-run',records:1,failures:0});
const trace = [begin,record,end].join('\n');
const corpus = convertTrace(trace);
assert.equal(corpus.schema,'cf7.tooltip-content-oracle.v1');
assert.deepEqual(corpus.records,[row]);
assert.throws(() => convertTrace([begin,record].join('\n')),/incomplete/);
assert.throws(() => convertTrace([begin,record,record,end].join('\n')),/duplicate/);
assert.throws(() => convertTrace([begin,record,'TC_INPUT_ERROR|fixture-run|{"reason":"source_drift"}',end].join('\n')),/errors/);
assert.throws(() => convertTrace(trace.replace('"records":1','"records":2')),/count/);
assert.throws(() => convertTrace(trace.replace('"kind":"avm1-capture"','"kind":"synthetic"')),/provenance/);
assert.throws(() => convertTrace(trace + '\n' + record),/outside/);

// Old Web compatibility HTML can repeat a potion buff. ChoiceReward's original
// full-inline details do not. Neither independent captured value is discarded.
const presentationResult = {document:{version:1},introHTML:'intro',descHTML:'web-buff',details:'reward-buff'};
const presentationEngine = {plainText: html => { assert.equal(html,'introweb-buff'); return 'legacy-web-buff-buff'; }};
const webValues = comparisonValues({input:{kind:'item',presentation:'web'}},presentationResult,presentationEngine);
assert.equal(webValues.details,'legacy-web-buff-buff');
assert.equal(webValues.descHTML,'web-buff');
assert.equal(comparisonValues({input:{kind:'item',presentation:'inventory'}},presentationResult,presentationEngine).details,'reward-buff');
assert.equal(comparisonValues({input:{kind:'item',presentation:'web',output:'details'}},presentationResult,presentationEngine).details,'reward-buff');
assert.notEqual(webValues.details,'wrong-web-content');
assert.notEqual(presentationResult.details,webValues.details);
// Execute the real offline serializer bodies after syntax-only AS2 adaptation.
// Runtime startup independently compares them to baseline LiteJSON in AVM1.
const vm = require('node:vm');
const collectorFile = path.join(__dirname, 'as2/org/flashNight/gesh/tooltip/test/TooltipCaptureJson.as');
const literals = [];
let collectorSource = fs.readFileSync(collectorFile, 'utf8').replace(/^\uFEFF/, '').replace(
    /\/\*[\s\S]*?\*\/|\/\/[^\r\n]*|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'/g,
    token => token.startsWith('/') ? '' : '__LITERAL_' + (literals.push(token) - 1) + '__');
collectorSource = collectorSource.replace(/^\s*import\s+[^;]+;/gm, '')
    .replace(/class\s+[\w.]+\s*\{/, '(function () {')
    .replace(/\b(?:public|private)\s+static\s+/g, '')
    .replace(/\b(var\s+[\w$]+)\s*:\s*[\w.]+/g, '$1')
    .replace(/\bfunction\s*([\w$]+)?\s*\(([^)]*)\)\s*(?::\s*[\w.]+)?/g,
        (_, name, args) => 'function ' + (name || '') + '(' + args.replace(/:\s*[\w.]+/g, '') + ')')
    .replace(/}\s*$/, 'return {stringify,quote}; })()')
    .replace(/__LITERAL_(\d+)__/g, (_, index) => literals[Number(index)]);
const serializer = vm.runInNewContext(collectorSource, {Array,Object,Number,String,Boolean,Math,isFinite,Date});
const values = [null, undefined, true, false, 0, -1.25, NaN, Infinity,
    '', '中文 "引号" \\ 路径\n换行\r\t', [], {text:'<B>旧内容</B>',missing:undefined}];
const holes = new Array(3); holes[1] = 'middle'; values.push(holes);
for (let code = 0; code < 32; code++) values.push(String.fromCharCode(code));
values.push({nested:[values.slice(0,10)],controls:values.slice(13).join('')});
values.push('中文 <FONT COLOR="red">长文本</FONT>\n'.repeat(1000));
for (const value of values) {
    const expected = value === undefined ? 'null' : JSON.stringify(value);
    assert.equal(serializer.stringify(value), expected);
}
assert(template.includes('import org.flashNight.arki.item.*;'));
console.log('paired capture protocol, presentation contracts and ' + values.length + ' serializer cases passed; no CS6 or AVM1 evidence');
