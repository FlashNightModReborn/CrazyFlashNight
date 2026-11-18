#!/usr/bin/env node
'use strict';

// The launcher can inspect authored equipment before a Flash actor exists.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'data/tooltip/tooltip-catalog.json');
const target = path.join(root, 'launcher/web/generated/archive-equipment.json');

function compile() {
    const catalog = JSON.parse(fs.readFileSync(source, 'utf8'));
    const rows = [];
    for (const [name, item] of Object.entries(catalog.items)) {
        if (item.type !== '武器' && item.type !== '防具' && item.use !== '手雷') continue;
        const record = {icon:item.icon, use:item.use};
        if (item.displayname && item.displayname !== name) record.label = item.displayname;
        if (item.setName) record.set = item.setName;
        if (typeof item.description === 'string') record.description = item.description.trim();
        for (const field of ['level','power','defence','damage','hp','mp']) {
            if (Number.isFinite(item.data?.[field])) record[field] = item.data[field];
        }
        rows.push('  ' + JSON.stringify(name) + ':' + JSON.stringify(record));
    }
    return '{"version":1,"sourceVersion":' + JSON.stringify(catalog.contentVersion) +
        ',"items":{\n' + rows.join(',\n') + '\n}}\n';
}

function verify() {
    if (!fs.existsSync(target) || fs.readFileSync(target,'utf8').replace(/\r\n/g,'\n') !== compile()) {
        throw new Error('Rebuild the launcher equipment reference with node tools/build-bootstrap-equipment-reference.js');
    }
}

if (require.main === module) {
    if (process.argv.includes('--check')) verify();
    else fs.writeFileSync(target, compile(), 'utf8');
    const data = JSON.parse(fs.readFileSync(target, 'utf8'));
    console.log('Launcher equipment reference: ' + Object.keys(data.items).length +
        ' items, ' + fs.statSync(target).size + ' bytes.');
}
module.exports = {verify};
