#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CRAFTING_ROOT = path.join(ROOT, 'data', 'crafting');
const CATEGORY_CODES = Object.freeze({
    '铁枪会':'iron-spear',
    '属性武器':'attribute-weapon',
    '烹饪':'cooking',
    '化学生产':'chemistry',
    '武器合成':'weapon',
    '饰品合成':'accessory',
    '进阶防具':'advanced-armor',
    '基础防具':'basic-armor',
    '公社防具':'commune-armor',
    '黑白契约':'black-white',
    '插件合成':'plugin',
    '大学装备':'university'
});
const RECIPE_ID = /^craft\.[a-z0-9]+(?:-[a-z0-9]+)*\.[0-9]{3}$/;

function fail(message) {
    throw new Error(message);
}

function readCategories() {
    const xml = fs.readFileSync(path.join(CRAFTING_ROOT, 'list.xml'), 'utf8');
    const categories = [];
    const pattern = /<list>([^<]+)<\/list>/g;
    let match;
    while ((match = pattern.exec(xml))) categories.push(match[1].trim());
    if (!categories.length) fail('data/crafting/list.xml contains no categories');
    return categories;
}

function topLevelObjectOffsets(source) {
    const offsets = [];
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let index = 0; index < source.length; index++) {
        const ch = source[index];
        if (inString) {
            if (escaped) escaped = false;
            else if (ch === '\\') escaped = true;
            else if (ch === '"') inString = false;
            continue;
        }
        if (ch === '"') { inString = true; continue; }
        if (ch === '[' || ch === '{') {
            depth++;
            if (ch === '{' && depth === 2) offsets.push(index);
        } else if (ch === ']' || ch === '}') {
            depth--;
            if (depth < 0) fail('unbalanced JSON delimiters');
        }
    }
    if (inString || depth !== 0) fail('unterminated JSON structure');
    return offsets;
}

function assignMissingIds(filePath, category, code) {
    let source = fs.readFileSync(filePath, 'utf8');
    const recipes = JSON.parse(source);
    const offsets = topLevelObjectOffsets(source);
    if (!Array.isArray(recipes) || offsets.length !== recipes.length) {
        fail(category + ': recipe array/object boundary mismatch');
    }
    const inserts = [];
    recipes.forEach((recipe, index) => {
        if (recipe && recipe.recipeId == null) {
            inserts.push({
                offset: offsets[index] + 1,
                text: '\n    "recipeId": "craft.' + code + '.'
                    + String(index + 1).padStart(3, '0') + '",'
            });
        }
    });
    for (let index = inserts.length - 1; index >= 0; index--) {
        const insert = inserts[index];
        source = source.slice(0, insert.offset) + insert.text + source.slice(insert.offset);
    }
    if (inserts.length) {
        JSON.parse(source);
        fs.writeFileSync(filePath, source, 'utf8');
    }
    return inserts.length;
}

function validate() {
    const categories = readCategories();
    const authored = Object.keys(CATEGORY_CODES);
    if (categories.length !== authored.length
            || categories.some(category => !CATEGORY_CODES[category])) {
        fail('list.xml category set is not covered by CATEGORY_CODES');
    }
    const seen = new Map();
    let recipeCount = 0;
    categories.forEach(category => {
        const filePath = path.join(CRAFTING_ROOT, category + '.json');
        if (!fs.existsSync(filePath)) fail(category + ': missing JSON file');
        const recipes = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        if (!Array.isArray(recipes)) fail(category + ': root must be an array');
        recipes.forEach((recipe, index) => {
            const label = category + '[' + index + ']';
            if (!recipe || typeof recipe !== 'object' || Array.isArray(recipe)) {
                fail(label + ': recipe must be an object');
            }
            if (typeof recipe.recipeId !== 'string' || !RECIPE_ID.test(recipe.recipeId)) {
                fail(label + ': missing or invalid recipeId');
            }
            if (!recipe.recipeId.startsWith('craft.' + CATEGORY_CODES[category] + '.')) {
                fail(label + ': recipeId category prefix mismatch');
            }
            if (seen.has(recipe.recipeId)) {
                fail(label + ': duplicate recipeId also used by ' + seen.get(recipe.recipeId));
            }
            seen.set(recipe.recipeId, label);
            if (typeof recipe.name !== 'string' || !recipe.name.trim()) fail(label + ': invalid name');
            if (typeof recipe.title !== 'string' || !recipe.title.trim()) fail(label + ': invalid title');
            if (!Array.isArray(recipe.materials)) fail(label + ': materials must be an array');
            recipeCount++;
        });
    });
    if (recipeCount !== 282) fail('expected 282 recipes, got ' + recipeCount);
    process.stdout.write('Crafting recipe identity: ' + recipeCount
        + ' recipes / ' + seen.size + ' unique recipeIds passed\n');
}

function main() {
    const assign = process.argv.includes('--assign-missing');
    const unknown = process.argv.slice(2).filter(value => value !== '--assign-missing');
    if (unknown.length) fail('unknown argument: ' + unknown[0]);
    if (assign) {
        let changed = 0;
        readCategories().forEach(category => {
            const code = CATEGORY_CODES[category];
            if (!code) fail('missing category code: ' + category);
            changed += assignMissingIds(path.join(CRAFTING_ROOT, category + '.json'), category, code);
        });
        process.stdout.write('Assigned ' + changed + ' missing recipeIds\n');
    }
    validate();
}

try { main(); }
catch (error) {
    process.stderr.write('[validate-crafting-recipes] ' + error.message + '\n');
    process.exitCode = 1;
}
