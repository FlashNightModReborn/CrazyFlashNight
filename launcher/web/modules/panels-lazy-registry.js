/**
 * Panels Lazy Registry — 8 个 panel 的依赖声明 + 占位注册。
 *
 * 这里只声明依赖；真正的 Panels.register('id', {create, onOpen, ...}) 由各 panel.js 自己
 * 在被加载时执行。Panels.open(id) 命中 _lazy entry 时，先按依赖列表注入 <script>，
 * 加载完成后调 registerFn() —— 由于各 panel.js 是顶层 IIFE 自注册风格，registerFn 通常空函数即可。
 *
 * 共享依赖：
 *  - minigames/shared/host-bridge.js 被 lockbox / pinalign / gobang 共用，
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
        ['modules/kshop.js'],
        noop);

    // ── help ──
    // marked.min.js 在 boot 时已加载（panel content 用 markdown 渲染）
    Panels.registerLazy('help',
        ['modules/help-panel.js'],
        noop);

    // ── jukebox ──
    Panels.registerLazy('jukebox',
        ['modules/panels/jukebox-panel.js'],
        noop);

    // ── map ──
    // map-panel-data.js / map-fit-presets.js 已 boot 加载（map-hud 依赖），不在此列
    Panels.registerLazy('map',
        ['modules/map-avatar-source-data.js',
         'modules/map-panel.js'],
        noop);

    // ── stage-select ──
    Panels.registerLazy('stage-select',
        ['modules/stage-select-data.js',
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

    // ── intelligence ──
    Panels.registerLazy('intelligence',
        ['modules/intelligence-components.js',
         'modules/intelligence-panel.js'],
        noop);
})();
