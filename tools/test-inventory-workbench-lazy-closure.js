#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const MODULES = path.join(ROOT, 'launcher', 'web', 'modules');
const read = name => fs.readFileSync(path.join(MODULES, name), 'utf8');

function section(source, start, end) {
    const from = source.indexOf(start);
    const to = source.indexOf(end, from + start.length);
    assert(from >= 0 && to > from, 'missing source section: ' + start);
    return source.slice(from, to);
}

async function main() {
    const registry = read('panels-lazy-registry.js');
    const workbenchDeps = section(
        registry,
        "Panels.registerLazy('workbench'",
        "Panels.registerLazy('loot'");
    [
        'asset-timeline.js',
        'dressup-doll-renderer.js',
        'workbench-inspection-viewport.js',
        'equipment-inspector.js',
        'equipment-tuning-runtime.js',
        'equipment-tuning-loadout-lifecycle.js',
        'equipment-tuning-view.js',
        'inventory-tuning-scope.js',
        'character-build.js'
    ].forEach(name => assert(!workbenchDeps.includes(name),
        'storage boot closure must not preload ' + name));
    [
        'inventory-runtime.js',
        'inventory-ui.js',
        'inventory-workbench-feature-loader.js',
        'inventory-storage-workbench.js',
        'inventory-workbench.js'
    ].forEach(name => assert(workbenchDeps.includes(name),
        'storage boot closure is missing ' + name));

    const calls = [];
    global.LazyLoader = {
        load(deps) {
            calls.push(deps.slice());
            return Promise.resolve().then(() => {
                global.EquipmentTuningRuntime = {};
                global.EquipmentTuningView = {};
                global.InventoryTuningScope = {};
                global.EquipmentInspector = {};
                if (deps.includes('modules/character-build.js')) {
                    global.CharacterBuild = {CharacterBuildController:function() {}};
                }
            });
        }
    };
    const loaderPath = require.resolve('../launcher/web/modules/inventory-workbench-feature-loader.js');
    delete require.cache[loaderPath];
    const loader = require(loaderPath);
    await loader.loadTuning();
    assert.strictEqual(calls.length, 1);
    assert(calls[0].includes('modules/equipment-tuning-loadout-lifecycle.js'));
    assert(calls[0].includes('modules/equipment-tuning-view.js'));
    assert(!calls[0].includes('modules/character-build.js'));
    await loader.loadBuild();
    assert.strictEqual(calls.length, 2);
    assert(calls[1].includes('modules/character-build/character-build-session-contract.js'));
    assert(calls[1].includes('modules/character-build/character-build-candidate-eligibility.js'));
    assert(calls[1].includes('modules/character-build/character-build-loadout-presenter.js'));
    assert(calls[1].includes('modules/character-build/character-build-candidate-pane.js'));
    assert(calls[1].includes('modules/character-build/character-build-transport.js'));
    assert(calls[1].includes('modules/character-build/character-build-candidate-channel.js'));
    assert(calls[1].includes('modules/equipment-tuning-view.js'));
    assert(calls[1].includes('modules/character-build.js'));
    assert.strictEqual(loader.isTuningReady(), true);
    assert.strictEqual(loader.isBuildReady(), true);

    const crafting = read('crafting.js');
    const organizer = read('crafting-inventory-organizer.js');
    const panels = read('panels.js');
    const config = read('inventory-workbench-config.js');
    assert(crafting.includes('CraftingInventoryOrganizer.mount(_shellEl'));
    assert(crafting.includes("kind:'crafting-organizer'"));
    assert(!crafting.includes("Panels.open('workbench'"));
    assert(organizer.includes("panel:'crafting'"));
    assert(!organizer.includes("Panels.open('workbench'"));
    assert(!panels.includes('isNestedCraftingOrganizer'));
    assert(!panels.includes('_activeHostOwner'));
    assert(!config.includes('resolveReturnTarget'));
    assert(!config.includes('nestedCrafting'));

    [
        'LazyLoader',
        'EquipmentTuningRuntime',
        'EquipmentTuningView',
        'InventoryTuningScope',
        'EquipmentInspector',
        'CharacterBuild'
    ].forEach(name => { delete global[name]; });
    process.stdout.write('Inventory workbench lazy closure: 12/12 passed\n');
}

main().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
