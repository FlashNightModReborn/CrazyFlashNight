'use strict';

const path = require('path');
const SharedEvidence = require('../workbench-live-e2e/lib/evidence-artifact');
const { TARGET_SLOT } = require('./preflight');

const MAX_SAFE = Number.MAX_SAFE_INTEGER;
const BONUS_FIELDS = Object.freeze(['hp', 'mp', 'unarmed', 'defense', 'innerPower']);

function count(value, label) {
    const number = Number(value);
    if (!Number.isSafeInteger(number) || number < 0 || number > MAX_SAFE) {
        throw new Error('gym save ledger field invalid: ' + label);
    }
    return number;
}

function project(data) {
    if (!data || typeof data !== 'object' || !Array.isArray(data['0'])
            || data['0'].length <= 9 || !Array.isArray(data['7'])
            || data['7'].length < BONUS_FIELDS.length) {
        throw new Error('gym save ledger shape invalid');
    }
    const actor = data['0'];
    const bonus = data['7'];
    const bonuses = {};
    BONUS_FIELDS.forEach((field, index) => { bonuses[field] = count(bonus[index], field); });
    return Object.freeze({
        money:count(actor[2], 'money'),
        level:count(actor[3], 'level'),
        experience:count(actor[4], 'experience'),
        skillPoints:count(actor[6], 'skillPoints'),
        kpoint:count(actor[9], 'kpoint'),
        bonuses:Object.freeze(bonuses)
    });
}

function capture(root, slot) {
    if (slot !== TARGET_SLOT) throw new Error('gym ledger may only read cf7_agent_gym');
    const saves = SharedEvidence.assertExactDirectory(path.join(path.resolve(root), 'saves'),
        'gym_ledger');
    const file = SharedEvidence.readExactRegularFile(path.join(saves, slot + '.json'), {
        phase:'gym_ledger', maximumBytes:128 * 1024 * 1024
    });
    let data;
    try { data = JSON.parse(file.bytes.toString('utf8')); }
    catch (error) { throw new Error('gym ledger JSON invalid: ' + error.message); }
    return { path:file.path, bytes:file.length, sha256:file.sha256, values:project(data) };
}

function sameValues(left, right) {
    return SharedEvidence.canonicalJson(left && left.values)
        === SharedEvidence.canonicalJson(right && right.values);
}

module.exports = { BONUS_FIELDS, capture, project, sameValues };
