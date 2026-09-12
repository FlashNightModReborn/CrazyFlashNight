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
    const registeredDeps = {};
    vm.runInNewContext(registry, {
        Panels:{registerLazy(id, deps) { registeredDeps[id] = Array.from(deps); }},
        LazyLoader:{}, console
    });
    const sharedPreview = 'modules/character-appearance-preview.js';
    const surgeryDeps = registeredDeps.surgery;
    assert(surgeryDeps.includes(sharedPreview));
    assert(surgeryDeps.indexOf('modules/dressup-doll-renderer.js') < surgeryDeps.indexOf(sharedPreview));
    assert(surgeryDeps.indexOf(sharedPreview) < surgeryDeps.indexOf('modules/plastic-surgery.js'));
    const bootstrap = fs.readFileSync(path.join(ROOT, 'launcher/web/bootstrap.html'), 'utf8');
    const bootstrapScripts = Array.from(bootstrap.matchAll(/<script[^>]+src="([^"]+)"/g), value => value[1]);
    assert(bootstrapScripts.includes(sharedPreview));
    assert(bootstrapScripts.indexOf('modules/dressup-doll-renderer.js') < bootstrapScripts.indexOf(sharedPreview));
    assert(bootstrapScripts.indexOf(sharedPreview) < bootstrapScripts.indexOf('modules/bootstrap-character-create.js'));
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
        'inventory-workbench-stash-navigation.js',
        'inventory-workbench-stash-source.js',
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
                if (deps.includes('modules/character-build/character-build-stash-authority.js')) {
                    global.CharacterBuildSession = {CharacterBuildSession:function() {}};
                    global.CharacterBuildTransport = {createRequestMux:function() {}};
                    global.CharacterBuildItemUse = {Controller:function() {}};
                    global.CharacterBuildStashAuthority = {create:function() {}};
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
    assert(calls[1].includes('modules/character-build/character-build-drug-layout.js'));
    assert(calls[1].includes('modules/character-build/character-build-session-contract.js'));
    assert(calls[1].indexOf('modules/character-build/character-build-drug-layout.js')
        < calls[1].indexOf('modules/character-build/character-build-session-contract.js'));
    assert(calls[1].includes('modules/character-build/character-build-candidate-eligibility.js'));
    assert(calls[1].includes('modules/character-build/character-build-loadout-presenter.js'));
    assert(calls[1].includes('modules/loadout-picker/loadout-picker-candidate-pane.js'));
    assert(calls[1].includes('modules/character-build/character-build-transport.js'));
    assert(calls[1].includes('modules/character-build/character-build-candidate-channel.js'));
    assert(calls[1].includes('modules/equipment-tuning-view.js'));
    assert(calls[1].includes('modules/character-build.js'));
    assert(calls[1].includes('modules/character-appearance-preview.js'));
    assert(calls[1].indexOf('modules/dressup-doll-renderer.js')
        < calls[1].indexOf('modules/character-appearance-preview.js'));
    assert(calls[1].indexOf('modules/character-appearance-preview.js')
        < calls[1].indexOf('modules/character-build.js'));
    assert.strictEqual(loader.isTuningReady(), true);
    assert.strictEqual(loader.isBuildReady(), true);

    // ── stash headless 闭包：会话 + item-use + authority，绝不加载人物资源 ──
    // build 闭包同样含 authority，mock 已在 loadBuild 后设置 stash 全局；
    // 先清掉以模拟 storage 冷入口（build 从未加载）下 STASH_DEPS 必须自包含。
    ['CharacterBuildSession', 'CharacterBuildTransport',
        'CharacterBuildItemUse', 'CharacterBuildStashAuthority']
        .forEach(name => { delete global[name]; });
    global.InventoryWorkbenchFeatureLoader = loader;
    const stashLoader = require('../launcher/web/modules/inventory-workbench-stash-navigation.js');
    await stashLoader.loadFeature();
    assert.strictEqual(calls.length, 3);
    assert.deepStrictEqual(calls[2], [
        'modules/character-build/character-build-mutation.js',
        'modules/character-build/character-build-drug-layout.js',
        'modules/character-build/character-build-session-contract.js',
        'modules/character-build-session.js',
        'modules/character-build/character-build-transport.js',
        'modules/character-build/character-build-cooldown-channel.js',
        'modules/character-build/character-build-stash-transport.js',
        'modules/character-build/character-build-item-use.js',
        'modules/character-build/character-build-stash-authority.js'
    ], 'stash cold-open closure must stay session/transport-only and keep load order');
    [
        'modules/character-build.js',
        'modules/character-build-view.js',
        'modules/character-appearance-preview.js',
        'modules/dressup-doll-renderer.js',
        'modules/asset-timeline.js',
        'modules/character-build/character-build-stash-view.js'
    ].forEach(name => assert(!calls[2].includes(name),
        'stash headless closure must not pull ' + name));
    assert.strictEqual(stashLoader.isFeatureReady(), true);
    // stash 不是可导航 view：storage 的 boot 闭包与 build/tuning descriptor 都不得带它
    assert(!workbenchDeps.includes('character-build-stash-authority.js'),
        'workbench boot closure must not preload the stash authority');
    assert(calls[1].includes('modules/character-build/character-build-stash-authority.js'),
        'build feature must already carry the stash authority for the borrowed path');
    assert(!calls[1].includes('modules/character-build/character-build-stash-view.js'),
        'build feature no longer loads the retired stash view');

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
        'noop);');
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
        'CharacterBuild',
        'CharacterBuildSession',
        'CharacterBuildTransport',
        'CharacterBuildItemUse',
        'CharacterBuildStashAuthority'
    ].forEach(name => { delete global[name]; });
    process.stdout.write('Inventory workbench + arena/crafting/NPCShop + shared character preview loading: passed\n');
}

main().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
