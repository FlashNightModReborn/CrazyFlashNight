#!/usr/bin/env node
'use strict';

// 从 data/crafting/调酒.json（AS2 改装清单权威源）派生调酒吧台面板直读的静态规格
// bartending-spec.json。Web 侧用它做「玩家投放原料 → 命中配方」的本地匹配与
// 口味/类型/瓶装饮料筛选展示；消耗与产出裁决仍完全走 CraftingPanelService
// snapshot/preview/commit，本文件只投影配方结构与展示标签。
//
// 闭包校验：
//   - 每配方 materials 只含 5 种吧台原料槽 + 情报类收集品（读 收集品_情报.xml 名称集）；
//   - technique 字段全等 AS2 declaredTechnique 合法形状；
//   - flavor/style/bottled 只取封闭枚举；
//   - 「原料槽组合 + shake/ice/aged + 卡莫特林可选态」匹配签名两两不冲突；
//   - optional 卡莫特林配方不得再声明 authored 卡莫特林（否则 0/1 投放映射歧义）。
//
// 输出 = launcher/web/modules/bartending-spec.json
// 用法：node tools/derive-bartending-spec.js [--output <file>] [--check]

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const sourceFile = path.join(projectRoot, 'data', 'crafting', '调酒.json');
const intelFile = path.join(projectRoot, 'data', 'items', '收集品_情报.xml');
const defaultOutput = path.join(projectRoot, 'launcher', 'web', 'modules', 'bartending-spec.json');

const INGREDIENT_SLOTS = ['艾德海德', '布朗森提取物', '粉末德尔塔', '弗拉内吉', '卡莫特林'];
const FLAVORS = ['甜', '苦', '酸', '辣', '气泡'];
const STYLES = ['经典', '优雅', '少女', '硬派', '宣传'];
const SHAKES = ['light', 'hard', 'none'];
const KARMOTRINE = ['required', 'optional', 'none'];
const KARMOTRINE_SLOT = '卡莫特林';

function fail(msg) {
    console.error('[derive-bartending-spec] ' + msg);
    process.exit(1);
}

function parseArgs(argv) {
    const args = { output: defaultOutput, check: false };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--output') { args.output = argv[i + 1] || ''; i += 1; continue; }
        if (arg === '--check') { args.check = true; continue; }
        if (arg === '--help' || arg === '-h') {
            console.error('usage: node tools/derive-bartending-spec.js [--output <file>] [--check]');
            process.exit(0);
        }
        fail('unknown arg: ' + arg);
    }
    return args;
}

function loadIntelNames() {
    const xml = fs.readFileSync(intelFile, 'utf8');
    const names = new Set();
    const re = /<name>([^<]+)<\/name>/g;
    let match;
    while ((match = re.exec(xml)) !== null) names.add(match[1].trim());
    return names;
}

function parseMaterial(entry, label) {
    const text = String(entry || '');
    const hashAt = text.lastIndexOf('#');
    if (hashAt <= 0) fail(label + ': material entry missing #count: ' + text);
    const name = text.substring(0, hashAt);
    const count = Number(text.substring(hashAt + 1));
    if (!Number.isInteger(count) || count < 1 || count > 999) {
        fail(label + ': invalid material count: ' + text);
    }
    return { name: name, count: count };
}

function validTechnique(spec, label) {
    if (spec == null) return null;
    if (typeof spec !== 'object' || Array.isArray(spec)) fail(label + ': technique must be an object');
    if (SHAKES.indexOf(String(spec.shake)) < 0) fail(label + ': invalid technique.shake');
    if (KARMOTRINE.indexOf(String(spec.karmotrine)) < 0) fail(label + ': invalid technique.karmotrine');
    return {
        shake: String(spec.shake),
        ice: spec.ice === true,
        aged: spec.aged === true,
        karmotrine: String(spec.karmotrine)
    };
}

// 原料槽组合 + 手法三元组的匹配签名；karmotrine 只决定「卡莫特林槽」合法计数区间：
//   required → 恰为 authored 计数；optional → 0 或 1；none → 0。
function karmotrineStates(technique, authoredKarmotrine) {
    if (!technique || technique.karmotrine === 'none') return [0];
    if (technique.karmotrine === 'required') return [authoredKarmotrine];
    return authoredKarmotrine === 0 ? [0, 1] : [authoredKarmotrine, authoredKarmotrine + 1];
}

function baseSignature(ingredients, technique) {
    const base = INGREDIENT_SLOTS.filter(function (name) { return name !== KARMOTRINE_SLOT; })
        .map(function (name) { return name + '#' + (ingredients[name] || 0); }).join('|');
    const tech = technique || { shake: 'none', ice: false, aged: false };
    return base + '||' + tech.shake + '|' + tech.ice + '|' + tech.aged;
}

function buildSpec(intelNames) {
    const recipes = JSON.parse(fs.readFileSync(sourceFile, 'utf8'));
    if (!Array.isArray(recipes)) fail('调酒.json root must be an array');
    const seenSignatures = new Map();
    const projected = recipes.map(function (recipe, index) {
        const label = '调酒[' + index + '](' + String(recipe.recipeId || '?') + ')';
        if (!recipe || typeof recipe !== 'object') fail(label + ': recipe must be an object');
        if (typeof recipe.recipeId !== 'string'
                || !/^craft\.bartending\.\d+$/.test(recipe.recipeId)) {
            fail(label + ': missing or invalid recipeId');
        }
        if (typeof recipe.title !== 'string' || !recipe.title.trim()) fail(label + ': invalid title');
        if (FLAVORS.indexOf(String(recipe.flavor)) < 0) {
            fail(label + ': flavor must be one of ' + FLAVORS.join('/'));
        }
        if (STYLES.indexOf(String(recipe.style)) < 0) {
            fail(label + ': style must be one of ' + STYLES.join('/'));
        }
        if (recipe.bottled !== undefined && recipe.bottled !== true && recipe.bottled !== false) {
            fail(label + ': bottled must be boolean');
        }
        if (!Array.isArray(recipe.materials)) fail(label + ': materials must be an array');

        const ingredients = {};
        const extras = [];
        recipe.materials.forEach(function (entry) {
            const material = parseMaterial(entry, label);
            if (INGREDIENT_SLOTS.indexOf(material.name) >= 0) {
                if (ingredients[material.name] !== undefined) {
                    fail(label + ': duplicate slot ingredient ' + material.name);
                }
                ingredients[material.name] = material.count;
            } else {
                if (!intelNames.has(material.name)) {
                    fail(label + ': non-slot material ' + material.name
                        + ' is not a known 收集品/情报 item — add it to 收集品_情报.xml '
                        + 'or move it into the five bar ingredient slots');
                }
                extras.push(material);
            }
        });

        const technique = validTechnique(recipe.technique, label);
        const authoredKarmotrine = ingredients[KARMOTRINE_SLOT] || 0;
        if (technique && technique.karmotrine === 'required' && authoredKarmotrine < 1) {
            fail(label + ': karmotrine=required but no authored 卡莫特林 material');
        }
        if (technique && technique.karmotrine === 'optional' && authoredKarmotrine > 0) {
            fail(label + ': karmotrine=optional must not carry authored 卡莫特林 '
                + '(slot count 0/1 maps to the opt-in choice)');
        }

        const signature = baseSignature(ingredients, technique);
        karmotrineStates(technique, authoredKarmotrine).forEach(function (karmotrineCount) {
            const key = signature + '|karmotrine:' + karmotrineCount;
            if (seenSignatures.has(key)) {
                fail(label + ': match signature collides with ' + seenSignatures.get(key)
                    + ' (' + key + ') — 吧台自由调配时无法区分两杯');
            }
            seenSignatures.set(key, label);
        });

        return {
            recipeIndex: index,
            recipeId: recipe.recipeId,
            title: recipe.title,
            book: String(recipe.book || ''),
            flavor: String(recipe.flavor),
            style: String(recipe.style),
            bottled: recipe.bottled === true,
            ingredients: ingredients,
            extras: extras,
            technique: technique
        };
    });
    return {
        version: 1,
        recipeCount: projected.length,
        ingredientSlots: INGREDIENT_SLOTS,
        flavors: FLAVORS,
        styles: STYLES,
        recipes: projected
    };
}

function stableSubset(payload) {
    return {
        _source: payload._source,
        _note: payload._note,
        version: payload.version,
        recipeCount: payload.recipeCount,
        ingredientSlots: payload.ingredientSlots,
        flavors: payload.flavors,
        styles: payload.styles,
        recipes: payload.recipes
    };
}

function tryReadExistingPayload(outputPath) {
    try {
        if (!fs.existsSync(outputPath)) return null;
        return JSON.parse(fs.readFileSync(outputPath, 'utf8').replace(/^﻿/, ''));
    } catch (e) {
        return null;
    }
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;
    const spec = buildSpec(loadIntelNames());
    const payload = {
        _generatedAt: new Date().toISOString(),
        _source: 'data/crafting/调酒.json + data/items/收集品_情报.xml (non-slot material closure)',
        _note: 'generated by tools/derive-bartending-spec.js, do not hand-edit',
        version: spec.version,
        recipeCount: spec.recipeCount,
        ingredientSlots: spec.ingredientSlots,
        flavors: spec.flavors,
        styles: spec.styles,
        recipes: spec.recipes
    };

    if (args.check) {
        const existing = tryReadExistingPayload(args.output);
        if (!existing) fail('check FAIL: ' + args.output + ' missing or unreadable; run derive explicitly');
        if (JSON.stringify(stableSubset(existing)) !== JSON.stringify(stableSubset(payload))) {
            fail('check FAIL: ' + args.output + ' is stale; run derive explicitly');
        }
        console.log('[derive-bartending-spec] check OK: ' + spec.recipeCount + ' recipes, closure valid.');
        return;
    }

    const outDir = path.dirname(args.output);
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

    const oldPayload = tryReadExistingPayload(args.output);
    if (oldPayload && JSON.stringify(stableSubset(oldPayload)) === JSON.stringify(stableSubset(payload))) {
        console.log('[derive-bartending-spec] unchanged (' + spec.recipeCount + ' recipes), kept _generatedAt='
            + (oldPayload._generatedAt || '<none>'));
        return;
    }

    fs.writeFileSync(args.output, JSON.stringify(payload) + '\n', 'utf8');
    console.log('[derive-bartending-spec] wrote ' + spec.recipeCount + ' recipes → ' + args.output);
}

main();
