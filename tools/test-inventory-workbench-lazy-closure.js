#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

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

    const npcshopDeps = section(
        registry,
        "Panels.registerLazy('npcshop'",
        "Panels.registerLazy('crafting'");
    const npcshopOrder = [
        'modules/npcshop-runtime.js',
        'modules/npcshop-material-navigation.js',
        'modules/npcshop-secondary-pages.js',
        'modules/npcshop.js'
    ].map(name => npcshopDeps.indexOf("'" + name + "'"));
    assert(npcshopOrder.every(index => index >= 0),
        'NPCShop lazy closure is missing its material navigation controller');
    assert(npcshopOrder.every((index, ordinal) => !ordinal || index > npcshopOrder[ordinal - 1]),
        'NPCShop runtime/navigation/presenter/facade load order drifted');
    const releasePolicy = fs.readFileSync(
        path.join(ROOT, 'tools', 'validate-launcher-release-policy.ps1'), 'utf8');
    assert(releasePolicy.includes("'modules\\npcshop-material-navigation.js'"),
        'Launcher release-policy required-assets gate omits NPCShop material navigation');

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

    // ── arena 生产闭包（P4 工程拆分收尾）：cold-open + 缺项/乱序 fail-fast ──
    // 本 vm 叶门不模拟浏览器 transport retry；真实 LazyLoader 中途 503 后的可重试恢复由
    // tools/test-panel-lazy-loader-browser.js 在 Edge + HTTP server 上独立证明。
    const arenaSection = section(registry, "Panels.registerLazy('arena'", "Panels.registerLazy('team'");
    const arenaDeps = (arenaSection.match(/'modules\/[^']+'/g) || [])
        .map(token => token.slice(1, -1));
    assert.deepStrictEqual(arenaDeps, [
        'modules/workbench-lifecycle.js',
        'modules/workbench-focus.js',
        'modules/workbench-primitives.js',
        'modules/workbench-profile.js',
        'modules/workbench.js',
        'modules/workbench-components.js',
        'modules/arena-meta-rosters.js',
        'modules/arena-factions.js',
        'modules/arena-unit-catalog.js',
        'modules/arena-unit-param-presets.js',
        'modules/arena-custom-presets.js',
        'modules/arena-custom-match-code.js',
        'modules/arena-custom-parameters.js',
        'modules/arena-custom-undo.js',
        'modules/arena-custom-polling.js',
        'modules/arena-custom-param-editor.js',
        'modules/arena-custom-result-view.js',
        'modules/asset-timeline.js',
        'modules/dressup-doll-renderer.js',
        'modules/merc-data.js',
        'modules/merc-portrait-renderer.js',
        'modules/portrait-resolver.js',
        'modules/arena/arena-core.js',
        'modules/arena/arena-shell.js',
        'modules/arena/arena-challenge-browser.js',
        'modules/arena/arena-preview-authority.js',
        'modules/arena/arena-custom-editor.js',
        'modules/arena/arena-result.js',
        'modules/arena-panel.js'
    ], 'arena lazy closure must prepend the shared workbench layer, load shared merc/enemy portrait consumers, then preserve core->shell->browser->preview->editor->result->facade order');

    function createArenaSandbox(registrations) {
        const sandbox = {
            console,
            Panels:{
                register(id, def) { registrations[id] = def; },
                registerLazy() {},
                isOpen() { return false; },
                close() {}
            },
            Bridge:{ on() {}, send() {} },
            setTimeout, clearTimeout, setInterval, clearInterval
        };
        sandbox.window = sandbox;
        return vm.createContext(sandbox);
    }
    function loadArenaClosure(sandbox, deps) {
        deps.forEach(dep => {
            const source = fs.readFileSync(path.join(MODULES, dep.slice('modules/'.length)), 'utf8');
            vm.runInContext(source, sandbox, {filename:dep});
        });
    }

    // cold-open：按 registry 声明顺序冷加载真实闭包后，arena 面板完成自注册且可构造
    const arenaRegistrations = {};
    const coldSandbox = createArenaSandbox(arenaRegistrations);
    loadArenaClosure(coldSandbox, arenaDeps);
    assert(arenaRegistrations.arena && typeof arenaRegistrations.arena.create === 'function',
        'arena cold-open must self-register a constructible panel');
    assert.strictEqual(typeof coldSandbox.Workbench.DualPaneShell, 'function',
        'arena cold-open must load the real shared workbench layer (no stubs)');

    // fail-fast a：闭包缺项（少 workbench-components.js）→ arena/arena-core.js 守卫 fail-fast（P4 起共享层守卫自 facade 前移 core，报错文案不变），
    // 报错点名缺失的共享层，且不做半初始化注册
    const missingRegistrations = {};
    assert.throws(
        () => loadArenaClosure(createArenaSandbox(missingRegistrations),
            arenaDeps.filter(dep => dep !== 'modules/workbench-components.js')),
        /需要先加载 workbench-lifecycle\/focus\/primitives\/profile\/workbench\.js\/components 共享层/,
        'arena must fail fast with a readable error when a shared-layer entry is missing');
    assert(!missingRegistrations.arena,
        'arena must not half-register when the shared layer is incomplete');

    // fail-fast b：闭包乱序（workbench.js 先于 primitives）→ 共享层自身守卫 fail-fast，
    // 报错可读并点名缺失依赖
    const disorderedDeps = arenaDeps.slice();
    disorderedDeps.splice(disorderedDeps.indexOf('modules/workbench.js'), 1);
    disorderedDeps.splice(disorderedDeps.indexOf('modules/workbench-primitives.js'), 0, 'modules/workbench.js');
    assert.throws(
        () => loadArenaClosure(createArenaSandbox({}), disorderedDeps),
        /workbench\.js requires workbench-primitives\.js to load first/,
        'shared layer must fail fast with a readable error when closure order is violated');

    const craftingSection = section(
        registry,
        "Panels.registerLazy('crafting'",
        "Panels.registerLazy('hairdresser'");
    const craftingDeps = (craftingSection.match(/'modules\/[^']+'/g) || [])
        .map(token => token.slice(1, -1));
    assert.deepStrictEqual(craftingDeps, [
        'modules/panel-runtime.js',
        'modules/workbench-lifecycle.js',
        'modules/workbench-focus.js',
        'modules/workbench-primitives.js',
        'modules/workbench-profile.js',
        'modules/workbench.js',
        'modules/workbench-components.js',
        'modules/item-filter.js',
        'modules/portrait-resolver.js',
        'modules/shop-portrait-resolver.js',
        'modules/asset-timeline.js',
        'modules/dressup-doll-renderer.js',
        'modules/workbench-inspection-viewport.js',
        'modules/equipment-inspector.js',
        'modules/crafting-inspector.js',
        'modules/crafting-materials.js',
        'modules/crafting-detail-presenter.js',
        'modules/inventory-runtime.js',
        'modules/crafting-runtime.js',
        'modules/crafting.js'
    ], 'crafting lazy closure must load exact enemy/shop portrait resolvers before its material consumer');
    assert(!craftingSection.includes('dialogue/dialogue-view.js')
        && !craftingSection.includes('map-panel.js')
        && !craftingSection.includes('map-panel-data.js'),
    'crafting portraits must not pull DialogueView or MapPanel runtime internals');
    assert(fs.existsSync(path.join(MODULES, 'portrait-resolver.js'))
        && fs.existsSync(path.join(MODULES, 'shop-portrait-resolver.js')),
    'crafting portrait resolver declarations must resolve to tracked runtime modules');

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
    process.stdout.write('Inventory workbench + arena/crafting/NPCShop lazy closure: 28/28 passed\n');
}

main().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
