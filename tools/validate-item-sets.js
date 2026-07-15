#!/usr/bin/env node
'use strict';

const path = require('path');
const { loadItemMeta, loadItemSetMeta } = require('./lib/item-icons');

const ROOT = path.resolve(__dirname, '..');
const errors = [];

function fail(message) { errors.push(message); }
function xmlText(xml, tag) {
    const match = new RegExp('<' + tag + '>\\s*([\\s\\S]*?)\\s*</' + tag + '>').exec(String(xml || ''));
    return match ? match[1].trim() : '';
}
function xmlBlock(xml, tag) { return xmlText(xml, tag); }
function indexedBlocks(xml, prefix) {
    const result = [];
    const re = new RegExp('<' + prefix + '(\\d+)>\\s*([\\s\\S]*?)\\s*</' + prefix + '\\1>', 'g');
    let match;
    while ((match = re.exec(String(xml || ''))) !== null) result.push({index:Number(match[1]), raw:match[2]});
    return result.sort((a, b) => a.index - b.index);
}
function requireContiguousIndexes(blocks, prefix, context) {
    blocks.forEach((block, expectedIndex) => {
        if (block.index !== expectedIndex) {
            fail(context + ': ' + prefix + ' indexes must be contiguous from 0; expected ' +
                prefix + expectedIndex + ' but found ' + prefix + block.index);
        }
    });
}
function finiteNumber(value) {
    const text = String(value == null ? '' : value).trim();
    return text !== '' && Number.isFinite(Number(text));
}

const meta = loadItemMeta(ROOT, fail);
const catalog = loadItemSetMeta(ROOT, fail);
const sets = new Map();
const names = new Map();
const orders = new Map();

catalog.forEach((entry, index) => {
    const id = String(entry.id || '').trim();
    const name = String(entry.name || '').trim();
    const orderText = String(entry.order || '').trim();
    const order = Number(orderText);
    const context = entry.source + ' / set #' + (index + 1);
    const validId = /^[a-z][a-z0-9_]{1,63}$/.test(id);
    const validName = !!name && name.length <= 64 && !/[\u0000-\u001f\u007f]/.test(name);
    const validOrder = /^\d+$/.test(orderText) && order <= 9999;
    if (!validId) fail(context + ': invalid or missing id "' + id + '"');
    if (!validName) fail(context + ': invalid or missing name');
    if (name && !name.endsWith('套装')) fail(context + ': name must end with "套装"');
    if (!validOrder) fail(context + ': invalid or missing order');
    if (sets.has(id)) fail(context + ': duplicate id "' + id + '"');
    if (names.has(name)) fail(context + ': duplicate name "' + name + '" (also used by "' + names.get(name) + '")');
    if (orders.has(order)) fail(context + ': duplicate order "' + orderText + '" (also used by "' + orders.get(order) + '")');
    if (!validId || !validName || !validOrder || !name.endsWith('套装') || sets.has(id) || names.has(name) || orders.has(order)) return;
    sets.set(id, {id, name, order, items:[], raw:entry.raw || '', effects:new Map()});
    names.set(name, id);
    orders.set(order, id);
});

Object.values(meta).forEach((item) => {
    const id = String(item.setId || '').trim();
    const context = item.source + ' / ' + item.name;
    if (item.setName) fail(context + ': setName must come from item_sets.xml, not the item XML');
    if (item.setOrder) fail(context + ': setOrder must come from item_sets.xml, not the item XML');
    if (!id) return;
    if (item.type !== '武器' && item.type !== '防具') fail(context + ': only equipment may declare a set');
    const group = sets.get(id);
    if (!group) {
        fail(context + ': setId "' + id + '" is missing from item_sets.xml');
        return;
    }
    group.items.push({ name:item.name, use:item.use, source:item.source });
});

sets.forEach((group) => {
    if (group.items.length === 0) fail('setId "' + group.id + '" has no item members');
    else if (group.items.length < 2) fail('setId "' + group.id + '" has fewer than 2 items');
});

const resistanceAttributes = new Map();
sets.forEach((group) => {
    const effectBlocks = indexedBlocks(xmlBlock(group.raw, 'effects'), 'effect_');
    requireContiguousIndexes(effectBlocks, 'effect_', 'setId "' + group.id + '" / effects');
    const groupThresholds = new Map();

    effectBlocks.forEach(({index, raw}) => {
        const context = 'setId "' + group.id + '" / effect_' + index;
        const id = xmlText(raw, 'id');
        const thresholdText = xmlText(raw, 'threshold');
        const threshold = Number(thresholdText);
        const activationGroup = xmlText(raw, 'activationGroup') || id;
        const kind = xmlText(raw, 'kind');
        if (!/^[a-z][a-z0-9_]{1,63}$/.test(id)) fail(context + ': invalid effect id "' + id + '"');
        if (group.effects.has(id)) fail(context + ': duplicate effect id "' + id + '"');
        if (!/^\d+$/.test(thresholdText) || threshold < 1) fail(context + ': threshold must be a positive integer');
        if (!/^[a-z][a-z0-9_]{1,63}$/.test(activationGroup)) fail(context + ': invalid activationGroup');
        if (groupThresholds.has(activationGroup) && groupThresholds.get(activationGroup) !== threshold) {
            fail(context + ': effects in activationGroup "' + activationGroup + '" must share threshold');
        }
        groupThresholds.set(activationGroup, threshold);

        const effect = {id, threshold, activationGroup, kind, raw, components:new Map(), requires:[]};
        group.effects.set(id, effect);

        const requiresRaw = xmlBlock(raw, 'requires');
        const requiresRe = /<effectId>\s*([^<]+?)\s*<\/effectId>/g;
        let requiresMatch;
        while ((requiresMatch = requiresRe.exec(requiresRaw)) !== null) effect.requires.push(requiresMatch[1].trim());

        if (kind === 'template') {
            const template = xmlText(raw, 'template');
            const params = xmlBlock(raw, 'params');
            const attribute = xmlText(params, 'attribute');
            if (template !== 'resistance_entry') fail(context + ': unsupported template "' + template + '"');
            if (attribute !== '原体') fail(context + ': resistance_entry attribute must be 原体 in phase 1');
            if (xmlText(params, 'calculation') !== 'add') fail(context + ': resistance_entry calculation must be add');
            if (!finiteNumber(xmlText(params, 'baseIfMissing')) || !finiteNumber(xmlText(params, 'value'))) {
                fail(context + ': baseIfMissing/value must be finite numbers');
            }
            if (resistanceAttributes.has(attribute)) {
                fail(context + ': duplicate resistance attribute "' + attribute + '" (also in ' + resistanceAttributes.get(attribute) + ')');
            } else resistanceAttributes.set(attribute, group.id + ':' + id);
        } else if (kind === 'routine') {
            if (xmlText(raw, 'mode') !== 'member_components') fail(context + ': routine mode must be member_components');
            if (!xmlText(raw, 'prepareRoutine')) fail(context + ': prepareRoutine is required');
            const componentBlocks = indexedBlocks(xmlBlock(raw, 'components'), 'component_');
            requireContiguousIndexes(componentBlocks, 'component_', context + ' / components');
            const slots = new Set();
            componentBlocks.forEach(({index:componentIndex, raw:componentRaw}) => {
                const componentId = xmlText(componentRaw, 'id');
                const slot = xmlText(componentRaw, 'slot');
                if (!/^[a-z][a-z0-9_]{1,63}$/.test(componentId)) fail(context + ': invalid component_' + componentIndex + ' id');
                if (!slot) fail(context + ': component_' + componentIndex + ' slot is required');
                if (effect.components.has(componentId)) fail(context + ': duplicate component id "' + componentId + '"');
                if (slots.has(slot)) fail(context + ': duplicate component slot "' + slot + '"');
                effect.components.set(componentId, slot);
                slots.add(slot);
            });
            if (componentBlocks.length === 0) fail(context + ': routine must declare components');
            if (threshold > slots.size) fail(context + ': threshold exceeds unique component slots');
        } else {
            fail(context + ': kind must be template or routine');
        }
    });

    group.effects.forEach((effect) => {
        effect.requires.forEach((requiredId) => {
            const required = group.effects.get(requiredId);
            if (!required) fail('setId "' + group.id + '" / effect "' + effect.id + '": missing requires "' + requiredId + '"');
            else if (required.activationGroup !== effect.activationGroup) fail('setId "' + group.id + '" / effect "' + effect.id + '": cross-group requires is not allowed');
            else if (requiredId === effect.id) fail('setId "' + group.id + '" / effect "' + effect.id + '": self dependency');
        });
    });
    const visitState = new Map();
    function visit(effect) {
        const state = visitState.get(effect.id) || 0;
        if (state === 1) { fail('setId "' + group.id + '": effect dependency cycle at "' + effect.id + '"'); return; }
        if (state === 2) return;
        visitState.set(effect.id, 1);
        effect.requires.forEach((requiredId) => { const required = group.effects.get(requiredId); if (required) visit(required); });
        visitState.set(effect.id, 2);
    }
    group.effects.forEach(visit);

    group.items.forEach((item) => {
        const lifecycle = xmlBlock(meta[item.name].raw, 'lifecycle');
        const attrBlocks = indexedBlocks(lifecycle, 'attr_');
        const seenComponents = new Set();
        attrBlocks.forEach(({index, raw}) => {
            const gate = xmlBlock(raw, 'setGate');
            if (!gate) return;
            const effectId = xmlText(gate, 'effectId');
            const componentId = xmlText(gate, 'componentId');
            const effect = group.effects.get(effectId);
            const context = item.source + ' / ' + item.name + ' / attr_' + index;
            if (!effect || effect.kind !== 'routine') fail(context + ': setGate effectId does not reference a routine');
            else if (!effect.components.has(componentId)) fail(context + ': unknown componentId "' + componentId + '"');
            else if (effect.components.get(componentId) !== item.use) fail(context + ': component slot does not match item use');
            if (seenComponents.has(effectId + ':' + componentId)) fail(context + ': duplicate gated component');
            seenComponents.add(effectId + ':' + componentId);
            if (!xmlText(xmlBlock(raw, 'init'), 'initRoutines')) fail(context + ': gated component requires initRoutines');
            if (!xmlText(xmlBlock(raw, 'cycle'), 'cycleRoutines')) fail(context + ': gated component requires cycleRoutines');
        });
    });

    group.effects.forEach((effect) => {
        if (effect.kind !== 'routine') return;
        effect.components.forEach((slot, componentId) => {
            const candidates = group.items.filter((item) => item.use === slot);
            if (candidates.length === 0) fail('setId "' + group.id + '": component "' + componentId + '" has no member in slot "' + slot + '"');
            candidates.forEach((item) => {
                const raw = meta[item.name].raw;
                const gatePattern = new RegExp('<setGate>\\s*<effectId>\\s*' + effect.id + '\\s*</effectId>\\s*<componentId>\\s*' + componentId + '\\s*</componentId>\\s*</setGate>');
                if (!gatePattern.test(raw)) fail(item.source + ' / ' + item.name + ': missing gate for component "' + componentId + '"');
            });
        });
    });
});

const swordSaint = sets.get('sword_saint_armor');
if (swordSaint) {
    if (swordSaint.effects.size !== 2) fail('sword_saint_armor must declare exactly two phase-1 effects');
    const resistance = swordSaint.effects.get('proto_resistance_entry');
    const routine = swordSaint.effects.get('combat_suite');
    if (!resistance || resistance.threshold !== 5 || resistance.activationGroup !== 'sword_saint_full_set') fail('sword_saint_armor resistance effect contract mismatch');
    if (!routine || routine.threshold !== 5 || routine.activationGroup !== 'sword_saint_full_set' || routine.components.size !== 5) fail('sword_saint_armor routine effect contract mismatch');
    if (!resistance || resistance.requires.length !== 1 || resistance.requires[0] !== 'combat_suite') fail('sword_saint_armor resistance must require combat_suite');
    swordSaint.items.forEach((item) => {
        if (/<原体>/.test(meta[item.name].raw)) fail(item.source + ' / ' + item.name + ': sword saint members must not retain magicdefence 原体');
    });
}

if (errors.length) {
    errors.forEach((message) => process.stderr.write('[item-sets] ERROR: ' + message + '\n'));
    process.stderr.write('[item-sets] FAIL (' + errors.length + ' error(s))\n');
    process.exit(1);
}

const result = Array.from(sets.values()).sort((a, b) => a.order - b.order || a.name.localeCompare(b.name, 'zh-CN'));
const itemCount = result.reduce((sum, group) => sum + group.items.length, 0);
if (process.argv.includes('--json')) {
    process.stdout.write(JSON.stringify({schema:'item-sets.v1', setCount:result.length, itemCount, sets:result}, null, 2) + '\n');
} else {
    process.stdout.write('[item-sets] ok: ' + result.length + ' set(s), ' + itemCount + ' item(s)\n');
}
