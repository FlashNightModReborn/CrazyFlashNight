// Shared by the Git launcher's private V8 instance and the package producer.
// No filesystem, Node globals or Flash actor state are available to the compiler.
const { SaxesParser } = require('saxes');

const directories = ['data/items', 'data/items/equipment_mods', 'data/crafting', 'data/enemy_properties'];
const lists = directories.map((dir) => dir + '/list.xml');
const equipment = 'data/equipment/equipment_config.xml';
const dict = () => Object.create(null);
const asArray = (value) => (Array.isArray(value) ? value : value == null ? [] : [value]);
const isMap = (value) => typeof value === 'object' && value !== null && !Array.isArray(value);

function xml(text, file) {
    const parser = new SaxesParser();
    const stack = [];
    let root;
    const appendText = (value) => {
        if (!stack.length) return;
        const content = stack[stack.length - 1].content;
        if (typeof content[content.length - 1] === 'string') content[content.length - 1] += value;
        else content.push(value);
    };
    parser.on('doctype', () => {
        throw Error('DTD/entities are not catalog inputs');
    });
    parser.on('opentag', ({ name, attributes }) => {
        if (stack.length >= 128) throw Error('XML nesting exceeds 128');
        const node = { name, attributes, content: [] };
        if (stack.length) stack[stack.length - 1].content.push(node);
        else root = node;
        stack.push(node);
    });
    parser.on('closetag', () => stack.pop());
    parser.on('text', appendText);
    parser.on('cdata', appendText);
    try {
        parser.write(text).close();
    } catch (error) {
        throw Error(file + ': ' + error.message);
    }
    return root;
}
function children(node, tag) {
    return node.content.filter((child) => typeof child !== 'string' && (!tag || child.name === tag));
}
function directText(node) {
    return node.content.filter((value) => typeof value === 'string').join('');
}
function scalar(value) {
    if (/^\s*[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[-+]?\d+)?\s*$/i.test(value)) {
        const number = Number(value);
        if (!Number.isFinite(number)) throw Error('Non-finite number in static Tooltip data');
        return number;
    }
    if (/^\s*[-+]?0x[\da-f]+\s*$/i.test(value)) return parseInt(value, 16);
    if (['true', 'True', 'TRUE'].includes(value)) return true;
    if (['false', 'False', 'FALSE'].includes(value)) return false;
    return value;
}
function decodeHtml(value) {
    return value.replace(/&([^&;]{0,10});/g, (whole, name) => {
        if (Object.hasOwn(TOOLTIP_HTML_ENTITIES, name)) return TOOLTIP_HTML_ENTITIES[name];
        const hex = /^#[xX]([\da-fA-F]+)$/.exec(name);
        if (!hex && !/^#\d+$/.test(name)) return whole;
        const code = parseInt(hex ? hex[1] : name.slice(1), hex ? 16 : 10) & 0xffff;
        return code ? String.fromCharCode(code) : '';
    });
}
function xmlValue(node) {
    const attributes = dict();
    for (const [key, value] of Object.entries(node.attributes)) attributes[key] = scalar(value);
    if (!children(node).length) {
        const text = directText(node);
        return text.trim() ? scalar(text) : Object.keys(attributes).length ? attributes : '';
    }
    for (const child of node.content) {
        let key, value;
        if (typeof child === 'string') {
            if (!child.trim()) continue;
            key = 'null';
            value = scalar(child);
        } else {
            key = child.name;
            if (key === 'CaseSwitch') throw Error('Runtime CaseSwitch cannot be baked into Tooltip catalog');
            value =
                key === 'Description' || key === 'MaterialDetail'
                    ? decodeHtml(directText(child))
                    : xmlValue(child);
        }
        if (Object.hasOwn(attributes, key)) attributes[key] = asArray(attributes[key]).concat([value]);
        else attributes[key] = value;
    }
    return attributes;
}
function itemView(value) {
    if (Array.isArray(value)) return value.map(itemView);
    if (!isMap(value)) return value;
    const out = dict();
    for (const key of Object.keys(value).reverse()) if (!key.startsWith('__')) out[key] = itemView(value[key]);
    return out;
}
function words(value) {
    const out = dict();
    for (const word of String(value).split(',')) if (word.trim()) out[word.trim()] = true;
    return out;
}
function normalizeMod(mod) {
    for (const key of [
        'weapontype',
        'excludeWeapontype',
        'grantsWeapontype',
        'grantsUse',
        'provideTags',
        'requireTags',
        'excludeBulletTypes',
        'requireBulletTypes'
    ]) {
        if (mod[key]) mod[key.replace(/s$/, '') + 'Dict'] = words(mod[key]);
    }
    if (!mod.detachPolicy) mod.detachPolicy = 'single';
    if (mod.tag) mod.tagValue = mod.tag;
    function ratios(block) {
        for (const kind of ['percentage', 'multiplier']) {
            for (const [key, value] of Object.entries(block[kind] || {})) {
                if (typeof value !== 'number') throw Error('Non-numeric ' + mod.name + '.' + kind + '.' + key);
                block[kind][key] = value * 0.01;
            }
        }
    }
    function cases(branch, field, useTags, convertRatios) {
        const entries = asArray(branch[field]);
        for (const row of entries) {
            if (convertRatios) ratios(row);
            if (row.name) row.lookupDict = words(row.name);
            else row._isDefault = true;
            if (useTags)
                for (const key of ['provideTags', 'requireTags'])
                    if (row[key]) row[key.slice(0, -1) + 'Dict'] = words(row[key]);
        }
        delete branch[field];
        branch[field + 'Cases'] = entries;
    }
    const stats = mod.stats || {};
    if (!isMap(stats)) throw Error('Invalid stats: ' + mod.name);
    ratios(stats);
    for (const [key, field] of [
        ['baseSwitch', 'value'],
        ['useSwitch', 'use'],
        ['tagSwitch', 'tag'],
        ['bulletSwitch', 'bullet']
    ]) {
        if (!stats[key]) continue;
        cases(stats[key], field, key === 'useSwitch', true);
        if (key === 'baseSwitch' && !stats[key].path) stats[key].path = 'data.damagetype';
    }
    if (mod.skillSwitch) cases(mod.skillSwitch, 'use', false, false);
    return mod;
}
function layout(sources, tolerateRecipeList = false) {
    function entries(dir, tag, suffix = '') {
        const file = dir + '/list.xml';
        return children(xml(sources[file], file), tag).map((node) => {
            const name = directText(node);
            if (
                !name ||
                name.trim() !== name ||
                /[\\:\x00-\x1f]/.test(name) ||
                name.split('/').some((part) => !part || part === '.' || part === '..')
            )
                throw Error(file + ': invalid entry ' + name);
            return dir + '/' + name + suffix;
        });
    }
    const plan = {
        sets: entries(directories[0], 'itemSets'),
        items: entries(directories[0], 'items'),
        mods: entries(directories[1], 'items'),
        recipes: [],
        enemies: entries(directories[3], 'items')
    };
    try {
        plan.recipes = entries(directories[2], 'list', '.json');
    } catch (error) {
        if (!tolerateRecipeList) throw error;
        plan.recipeListError = error.message;
    }
    return plan;
}
function sourcePaths(sources, tolerateRecipeList = false) {
    const plan = layout(sources, tolerateRecipeList);
    return [
        ...new Set([
            ...lists,
            equipment,
            ...plan.sets,
            ...plan.items,
            ...plan.mods,
            ...plan.recipes,
            ...plan.enemies
        ])
    ];
}
function compile(sources, checkout = false) {
    const paths = layout(sources, checkout);
    const parse = (file) => xml(sources[file], file);
    const sets = dict(),
        items = dict(),
        mods = dict(),
        recipesUsing = dict(),
        enemyNames = dict();
    const duplicateItems = [];
    for (const file of paths.sets)
        for (const node of children(parse(file), 'set')) {
            const row = xmlValue(node);
            sets[row.id] = row;
        }
    for (const file of paths.items)
        for (const node of children(parse(file), 'item')) {
            const item = xmlValue(node);
            if (typeof item.name !== 'string' || !item.name) throw Error(file + ': item is missing its name');
            delete item.id;
            delete item.balance;
            if (Object.hasOwn(sets, item.setId)) {
                const meta = sets[item.setId];
                item.setName = meta.name || '';
                item.setOrder = meta.order || 0;
            }
            const view = itemView(item);
            if (Object.hasOwn(items, item.name))
                duplicateItems.push({
                    name: item.name,
                    same: JSON.stringify(items[item.name]) === JSON.stringify(view)
                });
            else items[item.name] = view;
        }
    for (const file of paths.mods) {
        const doc = xmlValue(parse(file));
        for (const row of asArray(doc.mod)) {
            if (typeof row.name !== 'string' || !row.name) throw Error(file + ': mod is missing its name');
            if (Object.hasOwn(mods, row.name)) throw Error(file + ': duplicate mod ' + row.name);
            row.modGrade = doc.modGrade ?? null;
            row.catalogScope = doc.catalogScope ?? null;
            mods[row.name] = normalizeMod(row);
        }
    }
    const levelStatList = [];
    for (const cfg of children(parse(equipment), 'EquipmentConfig'))
        for (const group of children(cfg, 'LevelStatList'))
            for (const level of children(group, 'Level')) {
                if (Number(level.attributes.index) !== levelStatList.length)
                    throw Error(equipment + ': invalid level index');
                levelStatList.push(scalar(directText(level)));
            }
    let recipes = dict();
    let diagnostic = paths.recipeListError;
    let recipeTargets;
    try {
        recipes = compileRecipes(sources, paths.recipes, items);
    } catch (error) {
        if (!checkout) throw error;
        diagnostic = error.message;
        if (!paths.recipeListError) recipeTargets = scanRecipeTargets(sources, paths.recipes);
    }
    for (const [product, recipe] of Object.entries(recipes))
        for (const name of new Set(recipe.materials.map((row) => row.name)))
            (recipesUsing[name] ||= []).push(product);
    for (const names of Object.values(recipesUsing)) names.sort();
    for (const file of paths.enemies)
        for (const node of children(parse(file))) {
            const name = children(node, 'displayname')[0];
            enemyNames[node.name] = (name && directText(name)) || node.name;
        }
    const magicDamageTypes = Object.fromEntries(TOOLTIP_MAGIC_TYPES.map((name) => [name, true]));
    const payload = {
        items,
        mods,
        levelStatList,
        recipes,
        recipesUsing,
        obtainRecords: {},
        enemyNames,
        magicDamageTypes
    };
    if (diagnostic) {
        payload.recipesUnavailable = true;
        if (recipeTargets) payload.recipeTargets = recipeTargets;
    }
    return { payload, duplicateItems, diagnostic };
}
function scanRecipeTargets(sources, paths) {
    if (!paths.length) return undefined;
    const targets = dict();
    for (const file of paths) {
        let rows;
        try {
            rows = JSON.parse(sources[file].replace(/^\uFEFF/, ''));
        } catch {
            return undefined;
        }
        if (!Array.isArray(rows)) return undefined;
        for (const row of rows) {
            if (!row || typeof row !== 'object') return undefined;
            if (typeof row.name === 'string' && row.name) targets[row.name] = true;
            if (Array.isArray(row.materials)) {
                for (const encoded of row.materials) {
                    if (typeof encoded !== 'string') continue;
                    const mat = encoded.split('#')[0];
                    if (mat) targets[mat] = true;
                }
            }
        }
    }
    return targets;
}
function compileRecipes(sources, paths, items) {
    const recipes = dict();
    // AVM1 visits categories in reverse declaration order; the last row wins.
    for (const file of paths.slice().reverse()) {
        let rows;
        try {
            rows = JSON.parse(sources[file].replace(/^\uFEFF/, ''));
        } catch (error) {
            throw Error(file + ': ' + error.message);
        }
        if (!Array.isArray(rows)) throw Error(file + ': expected recipe array');
        for (const row of rows) {
            const where = file + ' / ' + (row?.recipeId || row?.name || '?');
            if (!row || typeof row.name !== 'string' || !Object.hasOwn(items, row.name))
                throw Error(where + ' / name: unknown product ' + row?.name);
            const entries = row.materials === undefined ? [] : row.materials;
            if (!Array.isArray(entries)) throw Error(where + ' / materials: expected array');
            const materials = entries.map((encoded, i) => {
                const quantity = typeof encoded === 'string' && encoded.includes('##');
                const parts = typeof encoded === 'string' ? encoded.split(quantity ? '##' : '#') : [];
                const value = parts.length >= 2 ? scalar(parts[1]) : null;
                if (
                    !Object.hasOwn(items, parts[0]) ||
                    !Number.isSafeInteger(value) ||
                    value < 0 ||
                    parts.length > 3
                )
                    throw Error(where + ' / materials[' + i + ']: invalid material or amount ' + encoded);
                const req = { name: parts[0], value, isQuantity: quantity };
                if (parts[2]) req.tier = parts[2];
                return req;
            });
            recipes[row.name] = { materials };
        }
    }
    return recipes;
}
function archive(items) {
    const records = [];
    for (const [name, item] of Object.entries(items)) {
        if (item.type !== '武器' && item.type !== '防具' && item.use !== '手雷') continue;
        const record = { icon: item.icon, use: item.use };
        if (item.displayname && item.displayname !== name) record.label = item.displayname;
        if (item.setName) record.set = item.setName;
        if (typeof item.description === 'string') record.description = item.description.trim();
        for (const key of ['level', 'power', 'defence', 'damage', 'hp', 'mp'])
            if (Number.isFinite(item.data?.[key])) record[key] = item.data[key];
        records.push('  ' + JSON.stringify(name) + ':' + JSON.stringify(record));
    }
    return '{"version":1,"items":{\n' + records.join(',\n') + '\n}}\n';
}
function serialize(payloadJson, digest) {
    return '{"version":1,"contentVersion":"sha256:' + digest + '",' + payloadJson.slice(1) + '\n';
}
module.exports = {
    lists,
    sourcePaths,
    compile,
    archive,
    serialize,
    listJson: JSON.stringify(lists),
    pathsJson: (sources) => JSON.stringify(sourcePaths(JSON.parse(sources), true)),
    checkout: (sources) => {
        const { payload, diagnostic } = compile(JSON.parse(sources), true);
        return { payload: JSON.stringify(payload), diagnostic: diagnostic || '' };
    },
    archiveJson: (payload) => archive(JSON.parse(payload).items)
};
