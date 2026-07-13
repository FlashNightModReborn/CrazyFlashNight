#!/usr/bin/env node
'use strict';

const path = require('path');
const { loadItemMeta, loadItemSetMeta } = require('./lib/item-icons');

const ROOT = path.resolve(__dirname, '..');
const errors = [];

function fail(message) { errors.push(message); }

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
    sets.set(id, {id, name, order, items:[]});
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
