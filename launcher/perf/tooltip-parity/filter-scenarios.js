#!/usr/bin/env node
'use strict';

/**
 * 场景过滤小工具：从 parity-corpus scenarios.json 按 phase/视口/id 子集化，
 * 供 P90-first 先行、boundary matrix 后补的分层跑法。
 *
 *   node filter-scenarios.js --in <scenarios.json> --out <f>
 *       [--phase p90-first|matrix] [--viewport 1024x576,1600x900] [--ids a,b,c]
 * 样本侧同理可用 --samples/--sample-ids（可选）直接过滤 samples.json。
 */

const fs = require('fs');
const path = require('path');

function fail(m) { console.error('FAIL: ' + m); process.exit(1); }

const args = {};
for (let i = 2; i < process.argv.length; i++) {
    const a = process.argv[i], next = () => process.argv[++i];
    if (a === '--in') args.in = next();
    else if (a === '--out') args.out = next();
    else if (a === '--phase') args.phase = next().split(',');
    else if (a === '--viewport') args.viewport = next().split(',').map(v => v.split('x').map(Number));
    else if (a === '--ids') args.ids = next().split(',');
    else if (a === '--dpi') args.dpi = next().split(',').map(Number);
    else if (a === '--placement') args.placement = next();   // 'auto' = placement 为 null/未设置
    else if (a === '--samples') args.samples = next();
    else if (a === '--sample-ids') args.sampleIds = next().split(',');
    else fail('unknown arg ' + a);
}
if (!args.in) fail('required: --in');

const doc = JSON.parse(fs.readFileSync(args.in, 'utf8'));
if (doc.schema !== 'cf7.tooltip-parity-scenarios.v1') fail('schema mismatch: ' + doc.schema);
let list = doc.scenarios;
if (args.phase) list = list.filter(s => args.phase.includes(s.phase || ''));
if (args.viewport) list = list.filter(s =>
    args.viewport.some(v => s.viewport && s.viewport.w === v[0] && s.viewport.h === v[1]));
if (args.ids) list = list.filter(s => args.ids.includes(s.id));
// dpi 缺省按 1 处理（与 web scale 公式同源）；非 1 dpi 未在 native 侧验证，须显式排除
if (args.dpi) list = list.filter(s => args.dpi.includes((s.viewport && s.viewport.dpi) || 1));
if (args.placement === 'auto') list = list.filter(s => s.placement == null);
else if (args.placement) list = list.filter(s => s.placement === args.placement);

const out = Object.assign({}, doc, { scenarios: list });
const dest = args.out || args.in.replace(/\.json$/, '.filtered.json');
fs.writeFileSync(dest, JSON.stringify(out, null, 1));
console.log('scenarios: ' + doc.scenarios.length + ' → ' + list.length + ' → ' + dest);

if (args.samples && args.sampleIds) {
    const sd = JSON.parse(fs.readFileSync(args.samples, 'utf8'));
    const keep = sd.samples.filter(s => args.sampleIds.includes(s.id));
    const sdest = args.samples.replace(/\.json$/, '.filtered.json');
    fs.writeFileSync(sdest, JSON.stringify(Object.assign({}, sd, { samples: keep }), null, 1));
    console.log('samples: ' + sd.samples.length + ' → ' + keep.length + ' → ' + sdest);
}
