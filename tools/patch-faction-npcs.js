#!/usr/bin/env node
// One-shot patcher for full upper-zone rearrangement of faction NPCs in launcher data
// Targets: map-avatar-source-data.js
'use strict';
const fs = require('fs');
const path = require('path');

const f = path.join(__dirname, '..', 'launcher', 'web', 'modules', 'map-avatar-source-data.js');
let s = fs.readFileSync(f, 'utf8');

function patchNpc(name, oldCx, oldCy, newCx, newCy) {
    const npcIdx = s.indexOf('"' + name + '"');
    if (npcIdx < 0) throw new Error('not found: ' + name);
    const endIdx = s.indexOf('"assetSize"', npcIdx);
    if (endIdx < 0) throw new Error('end not found: ' + name);
    const block = s.substring(npcIdx, endIdx);

    const cxEsc = String(oldCx).replace(/\./g, '\\.');
    const cyEsc = String(oldCy).replace(/\./g, '\\.');
    const centerRe = new RegExp('("center":\\s*\\{\\s*"x":\\s*)' + cxEsc + '(,\\s*"y":\\s*)' + cyEsc);
    const newCenter = '$1' + newCx + '$2' + newCy;
    let newBlock = block.replace(centerRe, newCenter);
    if (newBlock === block) throw new Error('center no match for ' + name + ' pattern=' + centerRe);

    const fmt = (n) => {
        const r = Math.round(n * 100) / 100;
        let s = r.toString();
        if (!s.includes('.')) s += '.0';
        return s;
    };
    const oldRectX = fmt(parseFloat(oldCx) - 22);
    const oldRectY = fmt(parseFloat(oldCy) - 22);
    const newRectX = fmt(parseFloat(newCx) - 22);
    const newRectY = fmt(parseFloat(newCy) - 22);
    const stripDot0 = (s) => s.endsWith('.0') ? s.slice(0, -2) : s;
    const tries = [
        [oldRectX, oldRectY],
        [stripDot0(oldRectX), oldRectY],
        [oldRectX, stripDot0(oldRectY)],
        [stripDot0(oldRectX), stripDot0(oldRectY)],
    ];
    let didRect = false;
    for (const [tx, ty] of tries) {
        const rectRe = new RegExp('("rect":\\s*\\{\\s*"x":\\s*)' + tx.replace(/\./g, '\\.') + '(,\\s*"y":\\s*)' + ty.replace(/\./g, '\\.'));
        const candidate = newBlock.replace(rectRe, '$1' + newRectX + '$2' + newRectY);
        if (candidate !== newBlock) {
            newBlock = candidate;
            didRect = true;
            break;
        }
    }
    if (!didRect) throw new Error('rect no match for ' + name + ' tried=' + JSON.stringify(tries));

    s = s.substring(0, npcIdx) + newBlock + s.substring(endIdx);
    console.log('  patched: ' + name);
}

patchNpc('general头像',   '210.6',  '141.95', '190.6',  '141.95');
patchNpc('gazer头像',     '101.5',  '140.15', '81.5',   '140.15');
patchNpc('director头像',  '163.45', '97.4',   '143.45', '97.4');
patchNpc('itinerant头像', '126.6',  '265.2',  '106.6',  '265.2');
patchNpc('surveyor头像',  '227.0',  '235.95', '207.0',  '235.95');
patchNpc('singer头像',    '511.5',  '130.7',  '439.5',  '130.7');
patchNpc('keyboard头像',  '575.9',  '158.7',  '503.9',  '158.7');
patchNpc('guitar头像',    '449.6',  '158.7',  '377.6',  '158.7');
patchNpc('火凤头像',      '107.3',  '397.3',  '695.12', '92.54');
patchNpc('翅虎头像',      '203.5',  '384.3',  '787.38', '80.07');
patchNpc('黑龙头像',      '249.3',  '405.3',  '831.28', '100.21');
patchNpc('黑铁头像',      '158.35', '487.4',  '726.14', '217.27');

fs.writeFileSync(f, s, 'utf8');
console.log('map-avatar-source-data.js patched (' + s.length + ' chars)');
