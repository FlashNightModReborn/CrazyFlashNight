/**
 * Panels Lazy Registry — 多个 panel 的依赖声明 + 占位注册。
 *
 * 这里只声明依赖；真正的 Panels.register('id', {create, onOpen, ...}) 由各 panel.js 自己
 * 在被加载时执行。Panels.open(id) 命中 _lazy entry 时，先按依赖列表注入 <script>，
 * 加载完成后调 registerFn() —— 由于各 panel.js 是顶层 IIFE 自注册风格，registerFn 通常空函数即可。
 *
 * 共享依赖：
 *  - minigames/shared/host-bridge.js 被 lockbox / pinalign / gobang / blackmarket 共用，
 *    LazyLoader 内置 url 去重，列多次只会真正加载一次。
 *
 * 不在这里管：
 *  - map-panel-data.js 是 map-hud (常驻 HUD) + map panel 共享，仍 boot 同步加载
 *  - CSS 仍在 overlay.html head 里 boot 加载（量小且非热点）
 */
(function() {
    'use strict';

    if (typeof Panels === 'undefined' || typeof LazyLoader === 'undefined') {
        console.error('[panels-lazy-registry] Panels or LazyLoader not loaded');
        return;
    }

    // 各 panel 的 IIFE 自注册执行后，会调 Panels.register('id', {...}) 覆盖 _lazy 占位。
    // 所以 registerFn 在大多数情况下是空 noop。
    function noop() {}

    // ── kshop ──
    Panels.registerLazy('kshop',
        ['modules/panel-runtime.js',
         'modules/workbench-lifecycle.js',
         'modules/workbench-focus.js',
         'modules/workbench-primitives.js',
         'modules/workbench-profile.js',
         'modules/workbench.js',
         'modules/workbench-components.js',
         'modules/item-filter.js',
         'modules/kshop-runtime.js',
         'modules/inventory-runtime.js',
         'modules/inventory-ui.js',
         'modules/kshop-views.js',
         'modules/kshop-cart-controller.js',
         'modules/kshop-catalog-presenter.js',
         'modules/kshop-owned-inventory-presenter.js',
         'modules/kshop-tooltip-presenter.js',
         'modules/kshop-procurement-navigation.js',
         'modules/kshop.js'],
        noop);

    // ── 背包—战备箱（独立 inventory-domain 工作台，不进入商城生命周期）──
    Panels.registerLazy('workbench',
        ['modules/panel-runtime.js',
         'modules/workbench-lifecycle.js',
         'modules/workbench-focus.js',
         'modules/workbench-primitives.js',
         'modules/workbench-profile.js',
         'modules/workbench.js',
         'modules/workbench-components.js',
         'modules/item-filter.js',
         'modules/inventory-runtime.js',
         'modules/inventory-ui.js',
         'modules/inventory-workbench-config.js',
         'modules/inventory-workbench-preparation-menu.js',
         'modules/inventory-workbench-navigation.js',
         'modules/inventory-workbench-header.js',
         'modules/inventory-workbench-quick-transfer.js',
         'modules/inventory-workbench-owned-view.js',
         'modules/inventory-workbench-feature-loader.js',
         'modules/inventory-storage-workbench.js',
         'modules/inventory-workbench.js'],
        noop);

    // ── 地图资源箱战利品（独立 loot domain；背包 ← 战利品单向 transfer-pair）──
    // 顺序固定为共享 runtime/lifecycle/focus/primitives/components，再到 feature 与 facade。
    Panels.registerLazy('loot',
        ['modules/panel-runtime.js',
         'modules/workbench-lifecycle.js',
         'modules/workbench-focus.js',
         'modules/workbench-primitives.js',
         'modules/workbench-profile.js',
         'modules/workbench.js',
         'modules/workbench-components.js',
         'modules/inventory-ui.js',
         'modules/inventory-runtime.js',
         'modules/loot/loot-runtime.js',
         'modules/loot/loot-state.js',
         'modules/loot/loot-view.js',
         'modules/loot/loot-organizer.js',
         'modules/loot/loot-panel.js'],
        noop);

    // ── NPC 金币商店（商品目录 + 背包/材料/情报同级 View）──
    Panels.registerLazy('npcshop',
        ['modules/panel-runtime.js',
         'modules/workbench-lifecycle.js',
         'modules/workbench-focus.js',
         'modules/workbench-primitives.js',
         'modules/workbench-profile.js',
         'modules/workbench.js',
         'modules/workbench-components.js',
         'modules/item-filter.js',
         'modules/inventory-runtime.js',
         'modules/inventory-ui.js',
         'modules/npcshop-runtime.js',
         'modules/npcshop-material-navigation.js',
         'modules/npcshop-secondary-pages.js',
         'modules/npcshop.js'],
        noop);

    // ── 合成工作台（配方目录 + Flash 权威预览/一次性提交）──
    Panels.registerLazy('crafting',
        ['modules/panel-runtime.js',
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
         'modules/crafting.js'],
        noop);

    // ── 理发店（AS2 权威目录 + 本地纸娃娃预览 + 单一 commit）──
    // PanelScale 已由 overlay boot，不重复执行；AssetTimeline → renderer
    // 沿用现有纸娃娃消费者的显式依赖顺序。
    Panels.registerLazy('hairdresser',
        ['modules/panel-runtime.js',
         'modules/asset-timeline.js',
         'modules/dressup-doll-renderer.js',
         'modules/hairdresser-runtime.js',
         'modules/hairdresser.js'],
        noop);

    // ── 技能（独立 domain；不复用物品格 lease/write coordinator）──
    Panels.registerLazy('skills',
        ['modules/panel-runtime.js',
         'modules/workbench-lifecycle.js',
         'modules/workbench-focus.js',
         'modules/workbench-primitives.js',
         'modules/workbench-profile.js',
         'modules/workbench.js',
         'modules/workbench-components.js',
         'modules/item-filter.js',
         'modules/skills-runtime.js',
         'modules/skills-library.js',
         'modules/skills-trainer.js',
         'modules/skills-loadout.js',
         'modules/skills-interactions.js',
         'modules/skills-render.js',
         'modules/skills-diagnostics.js',
         'modules/skills.js'],
        noop);

    // ── help ──
    // marked.min.js 在 boot 时已加载（panel content 用 markdown 渲染）
    Panels.registerLazy('help',
        ['modules/help-panel.js'],
        noop);

    // ── jukebox ──
    Panels.registerLazy('jukebox',
        ['modules/jukebox/jukebox-panel.js'],
        noop);

    // ── cutscene-test（动画测试 · beta，issue #7 bug2）──
    // Ruffle 运行时（cfn-assets.local/_ruffle/，约 29MB）由 panel 内部首次播放时懒加载，不在 deps 里。
    Panels.registerLazy('cutscene-test',
        ['modules/cutscene-test.js'],
        noop);

    // ── dressup ──
    // Dialogue portrait paper-doll preview. Runtime data comes from baked PNG
    // frame sequences and manifest metadata, so no Flash sampling is needed.
    Panels.registerLazy('dressup',
        ['modules/asset-timeline.js',
         'modules/dressup-doll-renderer.js',
         'modules/dressup/dressup-panel.js'],
        noop);

    // ── map ──
    // map-panel-data.js / map-fit-presets.js 已 boot 加载（map-hud 依赖），不在此列
    // stage-select-data.js 供 map panel 派生 hotspot -> 选关页签副动作，不加载 stage-select UI 本体。
    Panels.registerLazy('map',
        ['modules/map-scale-policy.js',
         'modules/map-avatar-source-data.js',
         'modules/stage-select-data.js',
         'modules/map-canvas-stage-renderer.js',
         'modules/map/map-hittest-engine.js',
         'modules/map/map-hotspot-hitcapture.js',
         'modules/map/map-scene-visual-layer.js',
         'modules/map/map-avatar-layer.js',
         'modules/map-panel.js'],
        noop);

    // ── stage-select ──
    // panel-scale.js 虽由 overlay.html boot 加载，仍按竞技场教训在 lazy 闭包内显式声明
    // （panel 之前），防 boot 顺序变化时生产冷打开缺依赖；重复加载为幂等 IIFE 重赋值。
    // stage-select-fixtures.js（P1-B 自 data 拆出）紧随 data：非纯 dev，runtime bridge 失败时
    // 面板 snapshot 合并兜底走 StageSelectData.getFixture → StageSelectFixtures，必须在 panel 之前。
    // P4-a 工程拆分：原 stage-select-panel.js 单文件 IIFE 拆为 modules/stage-select/ 五模块
    // （纯移动）——core（状态容器+跨模块工具，首载）→ view-model（纯数据层，无 DOM，
    // P5 三维 renderer 插座）→ renderer（空间 DOM 舞台+生命周期编排）→ inspector
    // （pinned 决策检查器+难度提交 intent）→ bridge（请求信封+回包守卫）→
    // stage-select-panel.js 薄 facade（Panels.register 装配 + _debug* QA 接口，守五模块全集）。
    // 中间模块只守 core（+vm/renderer），跨模块调用解析于调用时（arena P4 同款纪律）。
    Panels.registerLazy('stage-select',
        ['modules/stage-select-data.js',
         'modules/stage-select-fixtures.js',
         'modules/panel-scale.js',
         'modules/stage-select/stage-select-core.js',
         'modules/stage-select/stage-select-view-model.js',
         'modules/stage-select/stage-select-renderer.js',
         'modules/stage-select/stage-select-inspector.js',
         'modules/stage-select/stage-select-bridge.js',
         'modules/stage-select-panel.js'],
        noop);

    // ── lockbox ──
    Panels.registerLazy('lockbox',
        ['modules/minigames/shared/host-bridge.js',
         'modules/minigames/lockbox/core/index.js',
         'modules/minigames/lockbox/core/solver.js',
         'modules/minigames/lockbox/core/generator.js',
         'modules/minigames/lockbox/lockbox-audio.js',
         'modules/minigames/lockbox/lockbox-panel.js'],
        noop);

    // ── pinalign ──
    Panels.registerLazy('pinalign',
        ['modules/minigames/shared/host-bridge.js',
         'modules/minigames/pinalign/core/index.js',
         'modules/minigames/pinalign/app/level-specs.js',
         'modules/minigames/pinalign/adapter/dom-adapter.js',
         'modules/minigames/pinalign/pinalign-audio.js',
         'modules/minigames/pinalign/pinalign-panel.js'],
        noop);

    // ── gobang ──
    Panels.registerLazy('gobang',
        ['modules/minigames/shared/host-bridge.js',
         'modules/minigames/gobang/core/index.js',
         'modules/minigames/gobang/gobang-audio.js',
         'modules/minigames/gobang/gobang-panel.js'],
        noop);

    // ── blackmarket（全量目录影子测试；防具复用 battle-rig 纸娃娃，仍无正式写入）──
    Panels.registerLazy('blackmarket',
        ['modules/minigames/shared/host-bridge.js',
         'modules/minigames/blackmarket/core/index.js',
         'modules/asset-timeline.js',
         'modules/dressup-doll-renderer.js',
         'modules/workbench-inspection-viewport.js',
         'modules/equipment-inspector.js',
         'modules/merc-data.js',
         'modules/merc-portrait-renderer.js',
         'modules/minigames/blackmarket/visual/equipment-preview.js',
         'modules/minigames/blackmarket/visual/inspection-focus.js',
         'modules/minigames/blackmarket/visual/item-surface.js',
         'modules/minigames/blackmarket/blackmarket-panel.js'],
        noop);

    // ── intelligence ──
    Panels.registerLazy('intelligence',
        ['modules/intelligence-components.js',
         'modules/font-pack-banner.js',
         'modules/intelligence-panel.js'],
        noop);

    // ── arena ──
    // P2 起接入 workbench 共享层，闭包构成/顺序固定（team 同款）：共享层（lifecycle/focus/primitives/
    // profile/shell/components；arena 不消费 inspection-viewport，不列入）→ 领域模块 → 壳（arena-panel）。
    // arena-meta-rosters.js（由 meta_teams.json 派生）+ arena-factions.js（由 arena_factions.json 派生的
    // 势力卡展示投影）先于 panel 载入。P5 的经济/表达式/爬升池由 Host arenaAuthority 下发；缺失时
    // arena 面板 fail-closed，不回退 Web 本地经济真值。
    // P4 工程拆分：原 arena-panel.js 单文件 IIFE 拆为 modules/arena/ 六模块（纯移动）——core（状态容器+
    // 共享工具，首载并守卫 workbench 共享层）→ shell / challenge-browser / preview-authority /
    // custom-editor / result（中间模块只守 core，跨模块调用解析于调用时）→ arena-panel.js 薄 facade
    //（Panels.register 装配 + QA 接口，守六模块全集）。EnemyPortraits / MercPortraits 在 core 前加载，
    // 供挑战目录、对手预览与全兵种目录共用身份解析 / 纸娃娃胸像 / fail-soft 回退。
    Panels.registerLazy('arena',
        ['modules/workbench-lifecycle.js',
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
         'modules/arena-panel.js'],
        noop);

    // ── team (战队：佣兵 / 伙伴 / 战宠 / 机械) ──
    // 子视图继续使用 pets / mercs 协议，但只有 team 是生产 Panel。
    // team 已接入 workbench 共享层，顺序固定：共享层（lifecycle/focus/primitives/profile/shell/
    // components/inspection-viewport）→ 领域（asset-timeline/dressup/merc-data/merc-portrait/team-shared/pet/merc）→ 壳（team-panel）。
    Panels.registerLazy('team',
        ['modules/workbench-lifecycle.js',
         'modules/workbench-focus.js',
         'modules/workbench-primitives.js',
         'modules/workbench-profile.js',
         'modules/workbench.js',
         'modules/workbench-components.js',
         'modules/workbench-inspection-viewport.js',
         'modules/asset-timeline.js',
         'modules/dressup-doll-renderer.js',
         'modules/merc-data.js',
         'modules/merc-portrait-renderer.js',
         'modules/team/team-shared.js',
         'modules/portrait-resolver.js',
         'modules/pet-panel.js',
         'modules/merc-panel.js',
         'modules/team/team-panel.js'],
        noop);

    // ── tasks (任务：我的任务 / 事件日志 / 成就) ──
    // achievement-tab.js 须先于 task-panel.js 加载（task-panel createDOM 时装配 TaskAchievementTab）。
    Panels.registerLazy('tasks',
        ['modules/asset-timeline.js',
         'modules/dressup-doll-renderer.js',
         'modules/dialogue/dialogue-view.js',
         'modules/tasks/achievement-tab.js',
         'modules/tasks/mission-brief-view.js',
         'modules/tasks/dispatch-board-view.js',
         'modules/tasks/task-panel.js'],
        noop);
})();
