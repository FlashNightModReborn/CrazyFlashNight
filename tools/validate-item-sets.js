#!/usr/bin/env node
'use strict';

const path = require('path');
const { loadItemMeta } = require('./lib/item-icons');

const ROOT = path.resolve(__dirname, '..');
const errors = [];

function fail(message) { errors.push(message); }

const meta = loadItemMeta(ROOT, fail);
const sets = new Map();

Object.values(meta).forEach((item) => {
    const id = String(item.setId || '').trim();
    const name = String(item.setName || '').trim();
    const orderText = String(item.setOrder || '').trim();
    if (!id && !name && !orderText) return;
    const context = item.source + ' / ' + item.name;
    if (!id || !name) {
        fail(context + ': setId and setName must be declared together');
        return;
    }
    if (!/^[a-z][a-z0-9_]{1,63}$/.test(id)) fail(context + ': invalid setId "' + id + '"');
    if (name.length > 64 || /[\u0000-\u001f\u007f]/.test(name)) fail(context + ': invalid setName');
    if (!name.endsWith('套装')) fail(context + ': setName must end with "套装"');
    if (item.type !== '武器' && item.type !== '防具') fail(context + ': only equipment may declare a set');
    if (orderText && (!/^\d+$/.test(orderText) || Number(orderText) > 9999)) fail(context + ': invalid setOrder');

    if (!sets.has(id)) sets.set(id, { id, name, order: orderText ? Number(orderText) : 0, items: [] });
    const group = sets.get(id);
    if (group.name !== name) fail(context + ': setId "' + id + '" maps to both "' + group.name + '" and "' + name + '"');
    if (orderText && group.order && group.order !== Number(orderText)) fail(context + ': inconsistent setOrder for "' + id + '"');
    if (orderText && !group.order) group.order = Number(orderText);
    group.items.push({ name:item.name, use:item.use, source:item.source });
});

sets.forEach((group) => {
    if (group.items.length < 2) fail('setId "' + group.id + '" has fewer than 2 items');
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
