#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const CRAFTING_ROOT = path.join(ROOT, 'data', 'crafting');
const DRESSUP_MANIFEST = path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json');
const ICON_MANIFEST = path.join(ROOT, 'launcher', 'web', 'icons', 'manifest.json');
const INSPECTION_VIEWPORT_MODULE = path.join(ROOT, 'launcher', 'web', 'modules', 'workbench-inspection-viewport.js');
const EQUIPMENT_INSPECTOR_MODULE = path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector.js');
const CRAFTING_INSPECTOR_MODULE = path.join(ROOT, 'launcher', 'web', 'modules', 'crafting-inspector.js');
const ITEM_ROOT = path.join(ROOT, 'data', 'items');
const WEAPON_USES = new Set(['刀', '长枪', '手枪']);
const ARMOR_USES = new Set(['头部装备', '上装装备', '下装装备', '手部装备', '脚部装备', '颈部装备']);

const EXPECTED_NECK_FALLBACKS = [
    '亥猪项链',
    '空手大加成项链',
    '空手中加成项链',
    '冷兵器大加成项链',
    '冷兵器中加成项链',
    '枪械大加成项链',
    '枪械中加成项链',
    '申猴项链',
    '未羊项链',
    '戌狗项链',
    '酉鸡项链',
    '远古诛神项链',
    '战斗狂人军牌',
    '诛神项链',
    '子鼠项链',
    'A兵团精致项链'
].sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_DUAL_BLADES = [
    '輪舞', '超硬质双刀', '黑煞', '炎寒对剑', '战术双刀', '国风双剑',
    '双持中国战刀', '血十字刀剑', '烬灭裁决双刀'
].sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_BLADE_SHEATHS = [
    '虎彻配鞘版', '黑铁武士的刀带鞘', '血刀配鞘版', '寒潭黑蛟-入鞘', '梁上青-入鞘',
    '黑铁剑配鞘', '黑金古刀配鞘', '血能源刃配鞘版', '阎魔刀带鞘版'
].sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_CRAFTING_DUAL_BLADES = ['輪舞', '黑煞', '炎寒对剑']
    .sort((left, right) => left.localeCompare(right, 'zh-CN'));
const EXPECTED_CRAFTING_BLADE_SHEATHS = ['虎彻配鞘版', '血刀配鞘版', '黑铁剑配鞘', '血能源刃配鞘版']
    .sort((left, right) => left.localeCompare(right, 'zh-CN'));

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function loadRecipes() {
    const files = fs.readdirSync(CRAFTING_ROOT)
        .filter(fileName => fileName.toLowerCase().endsWith('.json'))
        .sort();
    const recipes = [];

    files.forEach(fileName => {
        const category = path.basename(fileName, '.json');
        const categoryRecipes = readJson(path.join(CRAFTING_ROOT, fileName));
        assert(Array.isArray(categoryRecipes), 'crafting category must be an array: ' + fileName);
        categoryRecipes.forEach((recipe, recipeIndex) => {
            recipes.push({
                category,
                recipeIndex,
                name: String(recipe.name || ''),
                title: String(recipe.title || '')
            });
        });
    });

    return { files, recipes };
}

function decodeXml(value) {
    return String(value || '')
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

function tagValue(block, tag) {
    const match = block.match(new RegExp('<' + tag + '(?:\\s[^>]*)?>([\\s\\S]*?)</' + tag + '>', 'i'));
    return match ? decodeXml(match[1].trim()) : '';
}

function loadItemMetadata() {
    const result = {};
    fs.readdirSync(ITEM_ROOT)
        .filter(fileName => fileName.toLowerCase().endsWith('.xml'))
        .forEach(fileName => {
            const content = fs.readFileSync(path.join(ITEM_ROOT, fileName), 'utf8');
            const blocks = content.match(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/gi) || [];
            blocks.forEach(block => {
                const name = tagValue(block, 'name');
                if (!name || result[name]) return;
                result[name] = {
                    type: tagValue(block, 'type'),
                    use: tagValue(block, 'use'),
                    actionType: tagValue(block, 'actiontype'),
                    displayName: tagValue(block, 'displayname'),
                    iconName: tagValue(block, 'icon'),
                    sourceFile: fileName
                };
            });
        });
    return result;
}

function uniqueItems(recipeData, dressupManifest, itemMetadata) {
    const byName = new Map();
    recipeData.recipes.forEach(recipe => {
        if (!recipe.name) return;
        if (!byName.has(recipe.name)) byName.set(recipe.name, []);
        byName.get(recipe.name).push(recipe);
    });

    return Array.from(byName.entries()).map(([name, recipeRefs]) => {
        const dressupItem = dressupManifest.items[name] || null;
        const metadata = itemMetadata[name] || {};
        const use = (dressupItem && dressupItem.use) || metadata.use || '';
        const iconName = (dressupItem && dressupItem.icon) || metadata.iconName || name;
        const kind = WEAPON_USES.has(use) ? 'weapon' : (ARMOR_USES.has(use) ? 'armor' : 'fallback');
        return {
            name,
            displayName: metadata.displayName || name,
            iconName,
            use,
            kind,
            recipeRefs,
            dressupItem
        };
    }).sort((left, right) => {
        const order = { weapon: 0, armor: 1, fallback: 2 };
        return order[left.kind] - order[right.kind] ||
            left.use.localeCompare(right.use, 'zh-CN') ||
            left.name.localeCompare(right.name, 'zh-CN');
    });
}

function loadInspector() {
    const context = {
        console,
        DressupDollRenderer: {
            buildStateFromEquipment: function(_manifest, options) { return options; }
        }
    };
    vm.createContext(context);
    [
        [INSPECTION_VIEWPORT_MODULE, 'workbench-inspection-viewport.js'],
        [EQUIPMENT_INSPECTOR_MODULE, 'equipment-inspector.js'],
        [CRAFTING_INSPECTOR_MODULE, 'crafting-inspector.js']
    ].forEach(entry => {
        const source = fs.readFileSync(entry[0], 'utf8').replace(/^\uFEFF/, '');
        vm.runInContext(source, context, { filename: entry[1] });
    });
    if (!context.CraftingInspector ||
        typeof context.CraftingInspector.resolveProductSource !== 'function' ||
        typeof context.CraftingInspector.buildStateForSource !== 'function') {
        throw new Error('CraftingInspector resolver/state helpers were not exported');
    }
    return context.CraftingInspector;
}

function assert(condition, message) {
    if (!condition) throw new Error(message);
}

function sameSet(actual, expected) {
    return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function main() {
    const recipeData = loadRecipes();
    const dressupManifest = readJson(DRESSUP_MANIFEST);
    const iconManifest = readJson(ICON_MANIFEST);
    const itemMetadata = loadItemMetadata();
    const inspector = loadInspector();
    const resolveProductSource = inspector.resolveProductSource;
    const items = uniqueItems(recipeData, dressupManifest, itemMetadata);
    const productCounts = items.reduce((counts, item) => {
        counts[item.kind] += 1;
        return counts;
    }, { weapon: 0, armor: 0, fallback: 0 });

    assert(recipeData.files.length === 12,
        'expected 12 crafting category files, got ' + recipeData.files.length);
    assert(recipeData.recipes.length === 282,
        'expected 282 recipes, got ' + recipeData.recipes.length);
    assert(items.length === 280,
        'expected 280 unique crafting products, got ' + items.length);
    assert(productCounts.weapon === 71 && productCounts.armor === 169 && productCounts.fallback === 40,
        'crafting product split changed: ' + JSON.stringify(productCounts));

    const genders = ['男', '女'];
    const routes = {
        '男': { weapon: 0, armor: 0, icon: 0 },
        '女': { weapon: 0, armor: 0, icon: 0 }
    };
    const decisions = [];
    const mismatches = [];
    const neckFallbacks = new Set();
    const iconFallbackItems = new Map();

    items.forEach(item => {
        const metadata = itemMetadata[item.name];
        assert(metadata, 'item XML metadata missing: ' + item.name);
        const output = {
            name: item.name,
            displayName: item.displayName || metadata.displayName || item.name,
            icon: item.iconName || metadata.iconName || item.name,
            majorType: metadata.type,
            use: metadata.use || item.use,
            actionType: metadata.actionType
        };

        genders.forEach(gender => {
            const resolved = resolveProductSource(output, gender, dressupManifest);
            let expectedKind = item.kind;
            if (item.kind === 'fallback') expectedKind = 'icon';
            if (item.kind === 'armor' && output.use === '颈部装备') expectedKind = 'icon';
            if (resolved.kind !== expectedKind) {
                mismatches.push({
                    name: item.name,
                    gender,
                    expected: expectedKind,
                    actual: resolved.kind,
                    reason: resolved.reason,
                    type: output.majorType,
                    use: output.use
                });
            }
            assert(routes[gender][resolved.kind] !== undefined,
                'unknown inspector route kind: ' + item.name + ' ' + gender + ' ' + resolved.kind);
            routes[gender][resolved.kind] += 1;
            decisions.push({ item, gender, output, resolved });

            if (resolved.kind === 'icon') {
                iconFallbackItems.set(item.name, { item, output, resolved });
                if (item.kind === 'armor') neckFallbacks.add(item.name);
            }
        });
    });

    assert(!mismatches.length, 'inspector route mismatches: ' + JSON.stringify(mismatches, null, 2));
    genders.forEach(gender => {
        const actual = routes[gender];
        assert(actual.weapon === 71 && actual.armor === 153 && actual.icon === 56,
            gender + ' route split mismatch: ' + JSON.stringify(actual));
    });
    assert(decisions.length === 560, 'expected 560 gender-specific route decisions, got ' + decisions.length);

    const actualNeckFallbacks = Array.from(neckFallbacks).sort((left, right) => left.localeCompare(right, 'zh-CN'));
    assert(sameSet(actualNeckFallbacks, EXPECTED_NECK_FALLBACKS),
        'unmapped neck fallback exact-set changed:\nactual=' + JSON.stringify(actualNeckFallbacks) +
        '\nexpected=' + JSON.stringify(EXPECTED_NECK_FALLBACKS));

    assert(iconFallbackItems.size === 56,
        'expected 56 unique icon-fallback products, got ' + iconFallbackItems.size);
    const missingIcons = Array.from(iconFallbackItems.values())
        .filter(entry => !iconManifest[entry.output.icon])
        .map(entry => entry.item.name)
        .sort((left, right) => left.localeCompare(right, 'zh-CN'));
    assert(sameSet(missingIcons, ['灰蛊裂隙弹']),
        'icon-fallback missing set changed: ' + JSON.stringify(missingIcons));

    const monkey = decisions.find(entry => entry.item.name === '申猴项链' && entry.gender === '女');
    assert(monkey && monkey.resolved.kind === 'icon' && monkey.output.icon === '齐天大圣' &&
        monkey.resolved.iconName === '齐天大圣',
    '申猴项链 must resolve its renamed icon key 齐天大圣');

    const garo = decisions.filter(entry => entry.item.name === '黄金骑士牙狼头盔');
    assert(garo.length === 2 && garo.every(entry => entry.resolved.kind === 'armor' &&
        entry.output.icon === '牙狼铠头盔' && entry.resolved.iconName === '牙狼铠头盔' &&
        entry.resolved.gender === entry.gender),
    '黄金骑士牙狼头盔 must resolve dressup by name and icon fallback by 牙狼铠头盔');

    const craftingComposites = decisions.filter(entry => entry.resolved.composition === 'dual-blade' ||
        entry.resolved.composition === 'blade-sheath');
    const craftingDualNames = Array.from(new Set(craftingComposites
        .filter(entry => entry.resolved.composition === 'dual-blade')
        .map(entry => entry.item.name))).sort((left, right) => left.localeCompare(right, 'zh-CN'));
    const craftingSheathNames = Array.from(new Set(craftingComposites
        .filter(entry => entry.resolved.composition === 'blade-sheath')
        .map(entry => entry.item.name))).sort((left, right) => left.localeCompare(right, 'zh-CN'));
    assert(sameSet(craftingDualNames, EXPECTED_CRAFTING_DUAL_BLADES),
        'crafting dual-blade exact-set changed: ' + JSON.stringify(craftingDualNames));
    assert(sameSet(craftingSheathNames, EXPECTED_CRAFTING_BLADE_SHEATHS),
        'crafting blade-sheath exact-set changed: ' + JSON.stringify(craftingSheathNames));
    assert(craftingComposites.length === 14,
        'expected 14 gender-specific composite decisions, got ' + craftingComposites.length);

    const allCompositeNames = { '双刀': [], '疾影': [] };
    Object.keys(itemMetadata).forEach(name => {
        var actionType = itemMetadata[name].actionType;
        if (actionType === '双刀' || actionType === '疾影') allCompositeNames[actionType].push(name);
    });
    Object.keys(allCompositeNames).forEach(actionType => {
        allCompositeNames[actionType].sort((left, right) => left.localeCompare(right, 'zh-CN'));
    });
    assert(sameSet(allCompositeNames['双刀'], EXPECTED_DUAL_BLADES),
        'full dual-blade XML exact-set changed: ' + JSON.stringify(allCompositeNames['双刀']));
    assert(sameSet(allCompositeNames['疾影'], EXPECTED_BLADE_SHEATHS),
        'full blade-sheath XML exact-set changed: ' + JSON.stringify(allCompositeNames['疾影']));

    allCompositeNames['双刀'].concat(allCompositeNames['疾影']).forEach(name => {
        const metadata = itemMetadata[name];
        const expectedComposition = metadata.actionType === '双刀' ? 'dual-blade' : 'blade-sheath';
        const expectedFields = metadata.actionType === '双刀'
            ? ['刀_装扮', '刀2_装扮'] : ['刀_装扮', '刀3_装扮'];
        assert(metadata && (metadata.actionType === '双刀' || metadata.actionType === '疾影'),
            'composite XML actionType missing: ' + name);
        genders.forEach(gender => {
            const resolved = resolveProductSource({
                name,
                icon: metadata.iconName || name,
                majorType: metadata.type,
                use: metadata.use,
                actionType: metadata.actionType
            }, gender, dressupManifest);
            assert(resolved.kind === 'weapon' && resolved.composition === expectedComposition,
                name + ' ' + gender + ' composite route mismatch: ' + JSON.stringify(resolved));
            assert(resolved.components.length === 2 && resolved.components[0].field === expectedFields[0] &&
                resolved.components[1].field === expectedFields[1],
            name + ' must preserve two ordered component slots');
            assert(resolved.components.every(component => dressupManifest.skinKeys[component.skinKey] &&
                dressupManifest.skinKeys[component.skinKey].export),
            name + ' contains an unrenderable composite component');
            const state = inspector.buildStateForSource(resolved, dressupManifest);
            assert(state.rig === 'battle' && state.stateLabel === '兵器站立' &&
                state.strictFields === true && sameSet(state.fitFields, expectedFields) &&
                sameSet(state.drawFields, expectedFields) && !state.equipment &&
                state.keyMap[expectedFields[0]] === resolved.components[0].skinKey &&
                state.keyMap[expectedFields[1]] === resolved.components[1].skinKey,
            name + ' must use the real two-holder battle composition');
        });
    });

    const sameSkinManifest = {
        items: {
            '同模双刀': { fieldsByGender: { '男': { '刀_装扮': 'same', '刀2_装扮': 'same' } } }
        },
        skinKeys: { same: { export: { uri: 'same.png' } } }
    };
    const sameSkin = resolveProductSource({
        name: '同模双刀', icon: '同模双刀', majorType: '武器', use: '刀', actionType: '双刀'
    }, '男', sameSkinManifest);
    assert(sameSkin.kind === 'weapon' && sameSkin.components.length === 2 &&
        sameSkin.components[0].skinKey === sameSkin.components[1].skinKey,
    'same-skin dual blades must keep two holder slots instead of deduplicating');

    const borrowedGenderManifest = {
        items: {
            '借分支双刀': { fieldsByGender: { '男': { '刀_装扮': 'male-primary', '刀2_装扮': 'male-offhand' } } }
        },
        skinKeys: {
            'male-primary': { export: { uri: 'primary.png' } },
            'male-offhand': { export: { uri: 'offhand.png' } }
        }
    };
    const borrowedGender = resolveProductSource({
        name: '借分支双刀', icon: '借分支双刀', majorType: '武器', use: '刀', actionType: '双刀'
    }, '女', borrowedGenderManifest);
    const borrowedState = inspector.buildStateForSource(borrowedGender, borrowedGenderManifest);
    assert(borrowedGender.kind === 'weapon' && borrowedGender.gender === '女' &&
        borrowedState.keyMap['刀_装扮'] === 'male-primary' &&
        borrowedState.keyMap['刀2_装扮'] === 'male-offhand' && borrowedState.strictFields === true,
    'weapon gender fallback must render the already-resolved component keys');

    const missingPartManifest = {
        items: {
            '残缺双刀': { fieldsByGender: { '男': { '刀_装扮': 'primary', '刀2_装扮': 'missing' } } }
        },
        skinKeys: { primary: { export: { uri: 'primary.png' } }, missing: {} }
    };
    const missingPart = resolveProductSource({
        name: '残缺双刀', icon: '残缺双刀', majorType: '武器', use: '刀', actionType: '双刀'
    }, '男', missingPartManifest);
    assert(missingPart.kind === 'icon' && missingPart.reason === 'weapon_component_missing' &&
        sameSet(missingPart.missingFields, ['刀2_装扮']),
    'incomplete dual blade must fall back as a whole');

    const judgment = decisions.find(entry => entry.item.name === '烬灭裁决' && entry.gender === '男');
    assert(judgment && judgment.output.actionType === '长柄' && judgment.resolved.kind === 'weapon' &&
        judgment.resolved.composition === 'single' && judgment.resolved.field === '刀_装扮',
    '烬灭裁决 is a long-handle default form and must not be treated as dual blades');

    const payload = {
        schema: 'cf7-crafting-inspector-coverage-v1',
        recipeFiles: recipeData.files.length,
        recipes: recipeData.recipes.length,
        uniqueProducts: items.length,
        productSplit: productCounts,
        genderDecisions: decisions.length,
        routes,
        routeTotals: {
            weapon: routes['男'].weapon + routes['女'].weapon,
            armor: routes['男'].armor + routes['女'].armor,
            icon: routes['男'].icon + routes['女'].icon
        },
        iconFallbackProducts: iconFallbackItems.size,
        unmappedNeckFallbacks: actualNeckFallbacks.length,
        missingIcons,
        aliases: {
            '申猴项链': '齐天大圣',
            '黄金骑士牙狼头盔': '牙狼铠头盔'
        },
        compositeContracts: {
            fullDualBladeItems: EXPECTED_DUAL_BLADES.length,
            fullBladeSheathItems: EXPECTED_BLADE_SHEATHS.length,
            craftingDualBladeItems: craftingDualNames.length,
            craftingBladeSheathItems: craftingSheathNames.length,
            genderDecisions: craftingComposites.length,
            missingPartFallback: true,
            sameSkinSlotsPreserved: true,
            borrowedGenderComponentsAuthoritative: true,
            longHandleException: '烬灭裁决'
        }
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
}

try {
    main();
} catch (error) {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
}
