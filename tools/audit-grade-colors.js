#!/usr/bin/env node
'use strict';

// 档级色彩契约审计（礼包配给 UI 精修 2026-10-07 施工，2026-10-08 canonical 收敛）：
//   1. canonical 词典 data/items/equipment_mods/ui_presentation.xml
//      ↔ launcher/web/modules/grade-presentation.js（唯一 JS 来源）两方钉死；
//   2. inventory-ui.js 不得再持有第二份 canonical 副本，必须引用 GradePresentation；
//   3. tokens.css 的 --wb-grade-* 静态别名层与 canonical 同值（派生层单独钉住）；
//   4. 漂移清零：features.css 情报材料 token 不再持四档外色相或漂移蓝，
//      equipment-tuning.css fallback 不再出现 #b78938；
//   5. data/rewards/choice-rewards.json 每个 bundle 的显式 grade 都在封闭枚举内。

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const errors = [];

function fail(message) { errors.push(message); }
function readText(rel) {
    return fs.readFileSync(path.join(ROOT, rel), 'utf8').replace(/^﻿/, '');
}

const xml = readText('data/items/equipment_mods/ui_presentation.xml');
const canonical = {};
const gradeRe = /<grade><id>(low|medium|high|special)<\/id><label>([^<]+)<\/label><color>(#[0-9A-Fa-f]{6})<\/color><\/grade>/g;
let match;
while ((match = gradeRe.exec(xml)) !== null) {
    canonical[match[1]] = { label: match[2], color: match[3] };
}
if (Object.keys(canonical).length !== 4) fail('ui_presentation.xml must define exactly the four grades');

const presentation = require(path.join(ROOT, 'launcher/web/modules/grade-presentation.js'));
for (const grade of Object.keys(canonical)) {
    const shared = presentation.GRADES[grade];
    if (!shared) { fail('grade-presentation.js missing grade ' + grade); continue; }
    if (shared.color.toUpperCase() !== canonical[grade].color.toUpperCase()) {
        fail('grade-presentation.js color drift for ' + grade + ': ' + shared.color);
    }
    if (shared.label !== canonical[grade].label) {
        fail('grade-presentation.js label drift for ' + grade + ': ' + shared.label);
    }
}

const inventoryUi = readText('launcher/web/modules/inventory-ui.js');
if (!/GradePresentation\.(?:normalize|color)\(/.test(inventoryUi)) {
    fail('inventory-ui.js must consume GradePresentation as the single grade source');
}
for (const grade of Object.keys(canonical)) {
    if (inventoryUi.includes(canonical[grade].color)) {
        fail('inventory-ui.js must not keep a second canonical copy of ' + grade
            + ' (' + canonical[grade].color + ')');
    }
}
if (/58636E/i.test(inventoryUi)) {
    fail('inventory-ui.js must not hardcode the unknown-grade fallback');
}

const tokens = readText('launcher/web/css/workbench/tokens.css');
for (const grade of Object.keys(canonical)) {
    const tokenRe = new RegExp('--wb-grade-' + grade + ":\\s*(#[0-9A-Fa-f]{6})\\b");
    const token = tokenRe.exec(tokens);
    if (!token) { fail('tokens.css missing --wb-grade-' + grade + ' alias'); continue; }
    if (token[1].toUpperCase() !== canonical[grade].color.toUpperCase()) {
        fail('tokens.css --wb-grade-' + grade + ' must alias the canonical value, got ' + token[1]);
    }
}
const unknownToken = /--wb-grade-unknown:\s*(#[0-9A-Fa-f]{6})\b/.exec(tokens);
if (!unknownToken || unknownToken[1].toUpperCase() !== presentation.UNKNOWN_COLOR.toUpperCase()) {
    fail('tokens.css --wb-grade-unknown must match the JS unknown fallback');
}
const derived = { low:'#71C971', medium:'#D6AD58', high:'#7FC9FB', special:'#FFF171' };
for (const grade of Object.keys(derived)) {
    const tokenRe = new RegExp('--wb-grade-core-' + grade + ":\\s*(#[0-9A-Fa-f]{6})\\b");
    const token = tokenRe.exec(tokens);
    if (!token || token[1].toUpperCase() !== derived[grade]) {
        fail('tokens.css --wb-grade-core-' + grade + ' derived shade drift');
    }
}
if (!/--wb-grade-special-on-paper:\s*#8A6D00\b/i.test(tokens)) {
    fail('tokens.css missing the paper-skin special adaptation --wb-grade-special-on-paper');
}

const features = readText('launcher/web/css/panels/features.css');
if (/#007acc\b/i.test(features)) fail('features.css still carries the drifted material-high #007acc');
if (/#8a35c9\b/i.test(features)) fail('features.css still carries the off-spectrum material-rare #8a35c9');
for (const pair of [['material-basic', 'low'], ['material-mid', 'medium'], ['material-high', 'high']]) {
    const ruleRe = new RegExp('\\.intel-h5-token-' + pair[0] + '\\s*\\{[^}]*var\\(--wb-grade-' + pair[1] + '\\)');
    if (!ruleRe.test(features)) {
        fail('features.css .intel-h5-token-' + pair[0] + ' must consume --wb-grade-' + pair[1]);
    }
}
if (!/\.intel-h5-token-material-rare\s*\{[^}]*var\(--wb-grade-special-on-paper\)/.test(features)) {
    fail('features.css .intel-h5-token-material-rare must consume the paper-adapted special token');
}

const tuning = readText('launcher/web/css/workbench/equipment-tuning.css');
if (/#b78938\b/i.test(tuning)) fail('equipment-tuning.css still carries the divergent fallback #b78938');

const inventoryCss = readText('launcher/web/css/workbench/inventory.css');
if (/\.inventory-equip-slot\.grade-(?:low|medium|high|special)\s*\{[^}]*#[0-9A-Fa-f]{6}/.test(inventoryCss)) {
    fail('inventory.css grade cores must consume --wb-grade-core-* tokens, not raw literals');
}

const catalog = JSON.parse(readText('data/rewards/choice-rewards.json'));
const grades = new Set(['low', 'medium', 'high', 'special']);
let gradedBundles = 0;
for (const bundle of catalog.bundles) {
    if (!grades.has(bundle.grade)) {
        fail('choice bundle ' + bundle.id + ' has no explicit closed-enum grade');
    } else {
        gradedBundles += 1;
    }
}

if (errors.length) {
    errors.forEach(message => process.stderr.write('[grade-colors] ERROR: ' + message + '\n'));
    process.stderr.write('[grade-colors] FAIL (' + errors.length + ' error(s))\n');
    process.exit(1);
}
process.stdout.write('[grade-colors] OK: 4 canonical grades pinned XML↔grade-presentation (single JS source), '
    + 'no second copy in inventory-ui.js, '
    + gradedBundles + ' explicitly graded choice bundles, drift list clean\n');
