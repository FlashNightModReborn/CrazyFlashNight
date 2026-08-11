#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const {
    normalizeLegacyGender,
    projectMercDressupPortrait
} = require('./lib/arena-portrait-routing');

const ROOT = path.resolve(__dirname, '..');
const sourceMercenaries = require(path.join(ROOT, 'data', 'merc', 'mercenaries.json'));
const metaTeams = require(path.join(ROOT, 'data', 'arena', 'meta_teams.json'));
const moduleText = fs.readFileSync(path.join(ROOT, 'launcher', 'web', 'modules', 'arena-meta-rosters.js'), 'utf8');
const context = { window: {} };
vm.runInNewContext(moduleText, context, { filename: 'arena-meta-rosters.js' });
const webMercenaries = JSON.parse(JSON.stringify(context.window.ArenaMetaRosters.mercenaries));

function rawEquipment(merc) {
    const out = {};
    for (const slot of Object.keys(merc.equipment || {}).sort()) {
        const value = merc.equipment[slot];
        if (value != null && String(value).trim()) out[slot] = String(value);
    }
    return out;
}

const expected = sourceMercenaries
    .filter(merc => merc && !merc.hidden && Number(merc.level) > 0 && merc.id != null && merc.name != null)
    .map(merc => ({
        id: Number(merc.id),
        name: String(merc.name),
        level: Number(merc.level),
        gender: normalizeLegacyGender(merc.gender),
        height: Number(merc.height) || 0,
        face: merc.face != null ? String(merc.face) : '',
        hair: merc.hair != null ? String(merc.hair) : '',
        equipment: rawEquipment(merc),
        portrait: projectMercDressupPortrait(merc),
        weight: 1
    }))
    .sort((a, b) => a.level - b.level || a.id - b.id);

assert.strictEqual(expected.length, 199, 'fixture must retain the 199 public mercenary projections');
assert.deepStrictEqual(webMercenaries, expected,
    'Arena Web merc projections must preserve the exact source face/hair/equipment tuple plus canonical actor');
assert.deepStrictEqual(metaTeams.mercenaries, expected,
    'meta_teams.json and Arena Web projection must derive from the same public mercenary tuple');

for (const hidden of sourceMercenaries.filter(merc => merc && merc.hidden)) {
    assert(!webMercenaries.some(merc => Number(merc.id) === Number(hidden.id) && merc.name === String(hidden.name)),
        `hidden mercenary ${hidden.id}/${hidden.name} must not leak into ArenaMetaRosters`);
}

process.stdout.write('Arena meta mercenary portrait tuple tests passed.\n');
