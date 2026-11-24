'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '../../..');
const DEFAULT_OUT = path.resolve(ROOT, '../../../outputs/efficiency-baseline-339');

const SHOWCASE = [
    ['flashlight', '战术手电', 2],
    ['laser', '镭射瞄准具', 3],
    ['graygoo', '灰蛊裂隙弹', 2],
    ['resonance', '谐振波射线弹', 2],
    ['manuscript', '三蝶手稿', 2],
    ['mount', '矩锁多点挂槽板', 2],
    ['grip', '战术握把', 2],
    ['qjz171', '钛合金QJZ171', 3, ['水冷机构', '强化金属管', '弹簧']],
    ['lynx', 'GM6_LYNX', 3, ['强化金属管', '透镜', '弹簧', '成长的勋章']],
    ['absr', '061ABSR', 3, ['强化金属管', '透镜', '弹簧']],
    ['mp510', 'MP510', 2, ['强化金属管', '透镜']],
    ['armor', '钛合金61式胸甲', 3],
    ['libra', '血色光剑天秤', 3],
    ['dominator', 'dominator', 2],
    ['mossberg', '战术版莫斯伯格590', 2],
    ['barrett', '战术巴雷特', 2],
    ['ammo', '手枪通用弹药', 0],
    ['shells', '12号霰弹弹药', 0],
];

function staticSources(root) {
    const byName = new Map();
    function add(name, record, source) {
        if (!name) return;
        if (!byName.has(name)) byName.set(name, []);
        byName.get(name).push({ record, source });
    }
    function listed(dir, tag) {
        const list = fs.readFileSync(path.join(root, dir, 'list.xml'), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
        const tags = new RegExp('<' + tag + '>\\s*([^<]+?)\\s*</' + tag + '>', 'g');
        return Array.from(list.matchAll(tags), match => path.posix.join(dir, match[1] + (tag === 'list' ? '.json' : '')));
    }
    const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8').replace(/^\uFEFF/, ''));
    for (const file of listed('data/shops', 'shops')) {
        const shop = read(file);
        const npc = shop.shopId || path.basename(file, '.json');
        if (npc.startsWith('书中-')) continue; // TooltipInputProjection filters these.
        const seen = new Set();
        for (const entry of Object.values(shop.catalog || {})) {
            const name = typeof entry === 'string' ? entry : entry?.name;
            if (!name || seen.has(name)) continue;
            seen.add(name);
            add(name, { kind: 'shop', npc }, file);
        }
    }
    for (const file of listed('data/kshop', 'kshop')) {
        for (const row of read(file)) {
            add(row.item, { kind: 'kshop', type: row.type || '', priceK: Number(row.price) || 0 }, file);
        }
    }
    for (const file of listed('data/crafting', 'list')) {
        for (const row of read(file)) {
            add(row.name, {
                kind: 'craft', category: path.basename(file, '.json'),
                price: Number(row.price) || 0, kprice: Number(row.kprice) || 0
            }, file);
        }
    }
    return byName;
}

function builder(root) {
    root = path.resolve(root);
    const { compile } = require(path.join(root, 'tools/tooltip-catalog.cjs'));
    const { load } = require(path.join(root, 'launcher/tooltip-engine/tests/helpers.cjs'));
    const { itemInput } = require(path.join(root, 'launcher/tooltip-engine/fixtures.cjs'));
    const { catalog: json, receipt } = compile(root);
    const catalog = JSON.parse(json);
    const engine = load();
    const sources = staticSources(root);
    const counts = { catalogItems: Object.keys(catalog.items).length };
    const provenance = {
        repoBaseline: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(),
        catalogContentVersion: receipt.contentVersion,
        documentBuilder: 'TooltipEngine.buildProjection',
        presentation: 'native',
        sourcePolicy: 'Active non-book NPC shops, K shops and recipe outputs. Showcase fills gaps with labeled stress inputs.'
    };

    function build(id, name, obtain, mods = []) {
        const item = catalog.items[name];
        const projection = {
            obtainRecords: obtain.map(({ record }) => record),
            bladeCount: Number(item.data?.bladeCount) || 0
        };
        const value = { level: 1 };
        if (mods.length) {
            const tags = new Set();
            if (item.data.modslot != null && mods.length > item.data.modslot) throw new Error(name + ': modslot exceeded');
            projection.mods = {};
            for (const modName of mods) {
                const mod = catalog.mods[modName];
                if (!mod?.use.split(',').includes(item.use) ||
                    (mod.weapontypeDict && !mod.weapontypeDict[item.weapontype]) ||
                    mod.excludeWeapontypeDict?.[item.weapontype] ||
                    mod.requireTags || !mod.tagValue || tags.has(mod.tagValue) ||
                    mod.skillSwitch || mod.subweapon || mod.stats?.useSwitch || mod.stats?.bulletSwitch) {
                    throw new Error(name + ': unsupported showcase mod ' + modName);
                }
                tags.add(mod.tagValue);
                projection.mods[modName] = { present: true, useCases: [], bulletCases: [], skill: null };
            }
            value.mods = mods;
            // Supply a DTO like fixtures.cjs. The layout case needs the installed
            // mod rows. Its equipment stats remain the source item's values.
            projection.calculated = Object.fromEntries(
                ['description', 'displayname', 'icon', 'use', 'weapontype', 'actiontype', 'data', 'skill', 'subweapon', 'lifecycle']
                    .filter(key => item[key] !== undefined).map(key => [key, item[key]])
            );
        }
        const input = itemInput(catalog, name, { value, projection });
        const { document, introHTML, descHTML } = engine.buildProjection(input, catalog);
        if (document?.version !== 1 || !document.sections?.length) throw new Error('empty or invalid TooltipDocument');
        return {
            id, name, displayName: document.title || item.displayname || name,
            itemType: item.type, itemUse: item.use || '', layoutType: document.layoutType,
            icon: document.icon, introHTML, descHTML, mods, document, obtain,
            coverageTags: [mods.length ? 'installed-mods' : item.type, ...(obtain.length ? ['acquisition'] : [])]
        };
    }
    return { catalog, sources, counts, provenance, build };
}

function buildFullCatalogSamples(root = ROOT) {
    const { catalog, sources, counts, provenance, build } = builder(root);
    const samples = [], errors = [];
    for (const name of Object.keys(catalog.items)) {
        try {
            samples.push(build(name, name, sources.get(name) || []));
        } catch (error) {
            errors.push({ name, message: String(error.message || error) });
        }
    }
    return { samples, errors, counts, provenance };
}

function buildShowcaseSamples(root = ROOT) {
    const { sources, counts, provenance, build } = builder(root);
    const samples = SHOWCASE.map(([id, name, count, mods]) => {
        let obtain = (sources.get(name) || []).slice(0, count);
        if (id === 'flashlight') {
            const npcs = ['前治安官', '迷之盔甲君'];
            obtain = npcs.map(npc => obtain.find(entry => entry.record.npc === npc));
            if (obtain.some(entry => !entry)) throw new Error(name + ': required shop missing');
        }
        while (obtain.length < count) {
            obtain.push({ record: { kind: 'drop', dropType: 'stage', stageName: '排版样例·探索区域 ' + (obtain.length + 1) }, source: null });
        }
        const sample = build(id, name, obtain, mods);
        if (count && !sample.document.sections.some(section => section.kind === 'acquisition')) {
            throw new Error(name + ': acquisition section missing');
        }
        const attachments = sample.document.sections.find(section => section.kind === 'attachments');
        if (mods?.length && attachments?.rows?.length !== mods.length) {
            throw new Error(name + ': installed-mod row count mismatch');
        }
        return sample;
    });
    return { samples, errors: [], counts, provenance };
}

if (require.main === module) {
    const [flag, output, ...extra] = process.argv.slice(2);
    if (flag !== '--dump-parity' || !output || extra.length) {
        throw new Error('用法: node samples.js --dump-parity <out.json>');
    }
    const { samples, provenance } = buildShowcaseSamples();
    fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
    fs.writeFileSync(output, JSON.stringify({
        schema: 'cf7.tooltip-parity-samples.v1', provenance, samples
    }, null, 2) + '\n');
    console.log(`已写入 ${samples.length} 个展示样本：${path.resolve(output)}`);
}

module.exports = { ROOT, DEFAULT_OUT, buildFullCatalogSamples, buildShowcaseSamples };
