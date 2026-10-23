#!/usr/bin/env node
'use strict';

const path = require('node:path');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {createSource, eraseTypes} = require('./source');
const fixtures = require('./fixtures.json');
const args = process.argv.slice(2);
function option(name, fallback) { const i = args.indexOf(name); return i < 0 ? fallback : args[i + 1]; }
const root = path.resolve(option('--source', path.join(__dirname,'../..')));
const mode = option('--mode', 'fixed');
assert(['baseline','fixed','diagnostic'].includes(mode), 'Invalid --mode');
assert.equal(eraseTypes('function(x:Number):Object {var y:Number = x ? Number(x) : Number(2); return {success:true,value:y};}'),
    'function(x) {var y = x ? Number(x) : Number(2); return {success:true,value:y};}');
const source = createSource(root), results = [];
function report(name, actual, target, knownCurrentFailure) {
    const equal = JSON.stringify(actual) === JSON.stringify(target);
    const known = arguments.length > 3;
    let status = equal ? 'passed' : 'failed';
    if (mode === 'baseline' && known) {
        assert.deepEqual(actual, knownCurrentFailure, name + ': baseline drift requires review');
        status = 'known-current-failure';
    } else if (mode !== 'diagnostic') assert.deepEqual(actual,target,name);
    results.push({name,status,actual:actual === undefined ? null : actual,target});
}
const selected = option('--probe', 'all');
for (const name of ['skill','runtime','morph','meridian','persistent']) {
    if (selected === 'all' || selected === name) require('./' + name + '-source-probe')(source,report,fixtures);
}
assert(results.length > 0, 'Unknown or empty --probe');
const evidence=Array.from(new Map(source.evidence.map(e=>[JSON.stringify(e),e])).values());
const output={schema:'cf7.player-stat-refresh-source-probes.v1',mode,
    evidenceTier:'node-source-extraction',repaired:mode === 'fixed' && results.every(r => r.status === 'passed'),
    boundaryPorts:'Explicit memory ports for coordinator and managed arithmetic; real AVM1/BuffManager/lifecycle/Host require separate native evidence.',
    scope:'Current persistent APIs and domain projection boundary ports; other entry and runtime gates are separate.',
    results,sourceEvidence:evidence};
const destination=option('--output','');
if(destination) {
    fs.writeFileSync(path.resolve(destination),JSON.stringify(output,null,2)+'\n','utf8');
    console.log(JSON.stringify({mode,evidenceTier:output.evidenceTier,cases:results.length,
        passed:results.filter(r=>r.status==='passed').length,sources:evidence.length,output:path.resolve(destination)}));
} else console.log(JSON.stringify(output,null,2));
