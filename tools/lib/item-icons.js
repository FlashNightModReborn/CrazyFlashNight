const fs = require('fs');
const path = require('path');

function readText(file, fail) {
    try {
        return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
    } catch (e) {
        fail('cannot read ' + file + ': ' + e.message);
        return '';
    }
}

function decodeXmlText(s) {
    return String(s || '')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, '&');
}

function childText(xml, tagName) {
    const re = new RegExp('<' + tagName + '>\\s*([\\s\\S]*?)\\s*</' + tagName + '>');
    const m = re.exec(xml);
    return m ? decodeXmlText(m[1].trim()) : '';
}

function readItemManifest(itemDir, fail) {
    const raw = readText(path.join(itemDir, 'list.xml'), fail);
    const out = [];
    const re = /<items>\s*([^<]+?)\s*<\/items>/g;
    let m;
    while ((m = re.exec(raw)) !== null) out.push(m[1]);
    if (out.length === 0) fail('data/items/list.xml has no <items> entries');
    return out;
}

function loadItemMeta(projectRoot, fail) {
    const itemDir = path.join(projectRoot, 'data', 'items');
    const files = readItemManifest(itemDir, fail);
    const byName = {};
    for (let i = 0; i < files.length; i += 1) {
        const rel = files[i];
        const raw = readText(path.join(itemDir, rel), fail);
        const itemRe = /<item\b[^>]*>([\s\S]*?)<\/item>/g;
        let m;
        while ((m = itemRe.exec(raw)) !== null) {
            const block = m[1];
            const name = childText(block, 'name');
            if (!name) continue;
            byName[name] = {
                name,
                displayname: childText(block, 'displayname'),
                icon: childText(block, 'icon'),
                type: childText(block, 'type'),
                use: childText(block, 'use'),
                source: rel
            };
        }
    }
    return byName;
}

function itemIcon(metaByName, name) {
    const meta = metaByName[String(name)];
    return meta && meta.icon ? meta.icon : String(name);
}

function attachIcon(stack, metaByName) {
    if (!stack || stack.name === undefined || stack.name === null) return stack;
    const icon = itemIcon(metaByName, stack.name);
    if (icon) stack.icon = icon;
    return stack;
}

module.exports = { loadItemMeta, itemIcon, attachIcon };
