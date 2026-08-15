/**
 * arena-custom-editor.js — 竞技场面板 P4 工程拆分 · 定制赛编辑器：赛程代码 / 阵容编辑 / 参数页 / 确认条 / 开跑与中止。
 *
 * 本文件由 modules/arena-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议 payload /
 * DOM id·class 契约 / QA 断言不变）。转换规则：原顶层 `var _x` 状态 → ArenaCore.state._x（本文件内
 * 以 `S._x` 访问）；跨模块函数/常量引用 → `模块全局.名字`。加载顺序由 panels-lazy-registry 的
 * arena 注册项与 arena/dev/harness.html script 区固定（与本文件守卫一致）。
 * 依赖守卫：通用 EnemyPortraits / MercPortraits + arena/arena-core.js。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.ArenaCore || !window.EnemyPortraits || !window.MercPortraits) {
        throw new Error('arena/arena-custom-editor.js 需要先加载通用怪物/纸娃娃头像组件与 arena/arena-core.js');
    }

    var S = ArenaCore.state; // 共享状态（原顶层 var _x）


    var CUSTOM_MATCH_FALLBACK_CODE =
        'CF7ARENA:v1;mode=mvm;seed=90210;blue=u44@30x2,u48@30x1;red=u164@60x1,u11@30x1';
    var CUSTOM_PVE_FALLBACK_CODE =
        'CF7ARENA:v1;mode=pve;seed=3307;enemy=u44@30x1;player=current';
    var CUSTOM_BROWSER_BATCH_SIZE = 80;
    var CUSTOM_SAVED_ROSTERS_KEY = 'cf7.arena.custom.savedRosters.v1';
    var CUSTOM_SAVED_ROSTER_LIMIT = 24;
    var CUSTOM_TIMEOUT_FPS = 30;
    var _customPortraitCoveragePromise = null;
    var _customPortraitObserver = null;
    var _customTooltipScope = null;
    var CUSTOM_SPAWN_DISTANCE_PRESETS = [
        { label: '近', value: 520 },
        { label: '标准', value: 650 },
        { label: '远', value: 820 }
    ];
    var CUSTOM_TIMEOUT_PRESETS = [
        { label: '60秒', value: 1800 },
        { label: '120秒', value: 3600 },
        { label: '180秒', value: 5400 },
        { label: '300秒', value: 9000 }
    ];
    var CUSTOM_FORMATION_OPTIONS = [
        { id: 'line', label: '横列' },
        { id: 'column', label: '纵队' },
        { id: 'wedge', label: '楔形' },
        { id: 'shield', label: '前盾后排' },
        { id: 'grid', label: '网格散点' }
    ];

    function buildCustomEditorViewHtml() {
        return '<div class="arena-custom-editor-header">' +
                '<button class="arena-custom-btn" type="button" data-custom-editor-action="back" data-audio-cue="cancel">返回配置</button>' +
                '<div class="arena-custom-editor-title-block">' +
                    '<div class="arena-custom-editor-kicker">定制赛阵容</div>' +
                    '<div class="arena-custom-editor-title">配置赛程与阵容</div>' +
                    '<div class="arena-custom-editor-meta">配置总览管理赛程与双方阵容，单方编辑页提供完整单位目录空间</div>' +
                '</div>' +
                    '<div class="arena-custom-editor-actions">' +
                        '<button class="arena-custom-btn" type="button" id="arena-custom-undo" data-custom-editor-action="undo" data-audio-cue="cancel" disabled>撤销</button>' +
                        '<button class="arena-card-btn-enter" type="button" data-custom-editor-action="done" data-audio-cue="confirm">完成</button>' +
                    '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-config-page" data-custom-editor-page="config">' +
                '<div class="arena-custom-config-panel">' +
                    '<div class="arena-custom-config-code">' +
                        '<div class="arena-custom-mode-switch" aria-label="定制赛模式">' +
                            '<button class="arena-custom-btn" type="button" data-custom-mode="mvm" data-audio-cue="confirm">怪物 vs 怪物</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-mode="pve" data-audio-cue="confirm">玩家 vs 怪物</button>' +
                        '</div>' +
                        '<label class="arena-custom-code-label" for="arena-custom-code-input">赛程代码（实时解析）</label>' +
                        '<textarea id="arena-custom-code-input" class="arena-custom-code-input" rows="2" spellcheck="false"></textarea>' +
                        '<div class="arena-custom-code-status" id="arena-custom-code-status"></div>' +
                    '</div>' +
                    '<div class="arena-custom-config-tools">' +
                        '<label class="arena-custom-code-label" for="arena-custom-preset-select">整局待标定组合</label>' +
                        '<select id="arena-custom-preset-select" class="arena-custom-preset-select" aria-label="待标定组合">' + buildCustomPresetOptions() + '</select>' +
                        '<div class="arena-custom-actions arena-custom-editor-code-actions">' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="preset" data-audio-cue="confirm">载入整局</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="random" data-audio-cue="confirm">随机整局</button>' +
                        '</div>' +
                        '<div class="arena-custom-actions arena-custom-editor-code-actions" id="arena-custom-swap-actions">' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="import" data-audio-cue="confirm">校验代码</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="copy" data-audio-cue="confirm">复制代码</button>' +
                            '<button class="arena-custom-btn" type="button" data-custom-action="swap-sides" data-audio-cue="confirm">交换红蓝</button>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-battle-summary" id="arena-custom-battle-summary">' +
                    '<div class="arena-custom-battle-summary-head">' +
                        '<div class="arena-custom-section-title">战场参数</div>' +
                        '<button class="arena-custom-btn" type="button" id="arena-custom-battle-edit" data-custom-editor-action="to-battle" data-audio-cue="confirm">编辑战场</button>' +
                    '</div>' +
                    '<div class="arena-custom-battle-summary-grid">' +
                        '<span><em>开局距离</em><b id="arena-custom-battle-summary-distance">--</b></span>' +
                        '<span><em>战斗时长</em><b id="arena-custom-battle-summary-timeout">--</b></span>' +
                        '<span><em>阵型</em><b id="arena-custom-battle-summary-formation">--</b></span>' +
                        '<span><em>间距</em><b id="arena-custom-battle-summary-spacing">--</b></span>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-side-configs">' +
                    '<div class="arena-custom-side-config-card arena-custom-side-config-blue" id="arena-custom-config-blue"></div>' +
                    '<div class="arena-custom-side-config-card arena-custom-side-config-red" id="arena-custom-config-red"></div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-battle-page" data-custom-editor-page="battle" hidden>' +
                '<div class="arena-custom-battle-editor-head">' +
                    '<div class="arena-custom-side-editor-title-block">' +
                        '<div class="arena-custom-editor-kicker">战场参数</div>' +
                        '<div class="arena-custom-editor-title">调整开局与阵型</div>' +
                        '<div class="arena-custom-editor-meta" id="arena-custom-battle-editor-meta">--</div>' +
                    '</div>' +
                    '<div class="arena-custom-battle-editor-actions">' +
                        '<button class="arena-custom-btn" type="button" data-custom-editor-action="to-config" data-audio-cue="cancel">返回总览</button>' +
                        '<button class="arena-card-btn-enter" type="button" data-custom-editor-action="done" data-audio-cue="confirm">完成</button>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-battle-params arena-custom-battle-params-editor" id="arena-custom-battle-params">' +
                    '<div class="arena-custom-battle-param-grid">' +
                        '<div class="arena-custom-battle-param-card" data-custom-battle-card="spawnDistance">' +
                            '<div class="arena-custom-battle-param-head"><span>开局距离</span><b id="arena-custom-spawn-distance-value">--</b></div>' +
                            '<div class="arena-custom-preset-row" id="arena-custom-spawn-distance-presets"></div>' +
                            '<input class="arena-custom-range" type="range" id="arena-custom-spawn-distance" data-custom-battle-field="spawnDistance">' +
                        '</div>' +
                        '<div class="arena-custom-battle-param-card" data-custom-battle-card="timeoutFrames">' +
                            '<div class="arena-custom-battle-param-head"><span>战斗时长</span><b id="arena-custom-timeout-value">--</b></div>' +
                            '<div class="arena-custom-preset-row" id="arena-custom-timeout-presets"></div>' +
                            '<input class="arena-custom-range" type="range" id="arena-custom-timeout" data-custom-battle-field="timeoutSeconds">' +
                        '</div>' +
                        '<div class="arena-custom-battle-param-card arena-custom-battle-param-card-wide">' +
                            '<div class="arena-custom-battle-param-head"><span>阵型</span><b id="arena-custom-formation-summary">--</b></div>' +
                            '<div class="arena-custom-formation-editors">' +
                                '<div class="arena-custom-formation-side" data-custom-formation-panel="blue">' +
                                    '<div class="arena-custom-formation-side-title" id="arena-custom-blue-formation-title">蓝方</div>' +
                                    '<div class="arena-custom-formation-options" id="arena-custom-blue-formation-options"></div>' +
                                    '<div class="arena-custom-formation-legend" id="arena-custom-blue-formation-legend"></div>' +
                                '</div>' +
                                '<div class="arena-custom-formation-side" data-custom-formation-panel="red">' +
                                    '<div class="arena-custom-formation-side-title" id="arena-custom-red-formation-title">红方</div>' +
                                    '<div class="arena-custom-formation-options" id="arena-custom-red-formation-options"></div>' +
                                    '<div class="arena-custom-formation-legend" id="arena-custom-red-formation-legend"></div>' +
                                '</div>' +
                            '</div>' +
                            '<div class="arena-custom-spacing-row">' +
                                '<span>间距</span>' +
                                '<input class="arena-custom-range" type="range" id="arena-custom-formation-spacing" data-custom-battle-field="formationSpacing">' +
                                '<b id="arena-custom-formation-spacing-value">--</b>' +
                            '</div>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-side-page" data-custom-editor-page="side" hidden>' +
                '<div class="arena-custom-side-editor-head">' +
                    '<div class="arena-custom-side-editor-title-block">' +
                        '<div class="arena-custom-editor-kicker" id="arena-custom-side-editor-kicker">蓝方阵容</div>' +
                        '<div class="arena-custom-editor-title" id="arena-custom-side-editor-title">编辑蓝方</div>' +
                        '<div class="arena-custom-editor-meta" id="arena-custom-side-editor-meta">--</div>' +
                    '</div>' +
                    '<div class="arena-custom-side-editor-actions">' +
                        '<select class="arena-custom-preset-select" data-custom-saved-select="active" aria-label="已保存配置"></select>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="load" data-side="active" data-audio-cue="confirm">读取</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="save" data-side="active" data-audio-cue="confirm">保存</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="random" data-side="active" data-audio-cue="confirm">随机组合</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-side-action="clear" data-side="active" data-audio-cue="cancel">清空</button>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-side-panel">' +
                    '<div class="arena-custom-roster-panel arena-custom-roster-active" id="arena-custom-active-roster-panel" data-side="blue">' +
                        '<div class="arena-custom-roster-head">' +
                            '<button class="arena-custom-roster-tab" type="button" data-custom-editor-action="to-config" data-audio-cue="cancel">返回总览</button>' +
                            '<span class="arena-custom-roster-head-count" id="arena-custom-active-roster-count">--</span>' +
                        '</div>' +
                        '<div class="arena-custom-roster-list" id="arena-custom-active-roster"></div>' +
                    '</div>' +
                    '<div class="arena-custom-browser">' +
                    '<div class="arena-custom-browser-toolbar">' +
                        '<div class="arena-custom-side-switch" aria-label="添加目标">' +
                            '<button type="button" data-custom-side="blue" data-audio-cue="confirm">加到蓝方</button>' +
                            '<button type="button" data-custom-side="red" data-audio-cue="confirm">加到红方</button>' +
                        '</div>' +
                        '<input id="arena-custom-unit-search" class="arena-custom-unit-search" type="search" placeholder="搜索 ID / 名称 / 素材" spellcheck="false">' +
                        '<span class="arena-custom-unit-count" id="arena-custom-unit-count">--</span>' +
                        '<span class="arena-custom-portrait-coverage" id="arena-custom-portrait-coverage" aria-live="polite" data-custom-tooltip="头像覆盖核对中">头像 --/--</span>' +
                    '</div>' +
                    '<div class="arena-custom-unit-filters">' +
                        '<button type="button" data-custom-unit-filter="all" data-audio-cue="confirm">全部</button>' +
                        '<button type="button" data-custom-unit-filter="hostile" data-audio-cue="confirm">敌对</button>' +
                        '<button type="button" data-custom-unit-filter="nonhostile" data-audio-cue="confirm">非敌对</button>' +
                    '</div>' +
                    '<div class="arena-custom-unit-list" id="arena-custom-unit-list"></div>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-editor-page arena-custom-param-page" data-custom-editor-page="params">' +
                '<div class="arena-custom-param-editor-head">' +
                    '<div class="arena-custom-side-editor-title-block">' +
                        '<div class="arena-custom-editor-kicker" id="arena-custom-param-editor-kicker">单位参数</div>' +
                        '<div class="arena-custom-editor-title" id="arena-custom-param-editor-title">编辑参数</div>' +
                        '<div class="arena-custom-editor-meta" id="arena-custom-param-editor-meta">--</div>' +
                    '</div>' +
                    '<div class="arena-custom-param-editor-actions">' +
                        '<button class="arena-custom-btn" type="button" data-custom-param-action="back" data-audio-cue="cancel">返回阵容</button>' +
                        '<button class="arena-custom-btn" type="button" data-custom-param-action="apply" data-audio-cue="confirm">应用</button>' +
                        '<button class="arena-card-btn-enter" type="button" data-custom-param-action="save-back" data-audio-cue="confirm">保存返回</button>' +
                    '</div>' +
                '</div>' +
                '<div class="arena-custom-param-editor-body" id="arena-custom-param-editor-body"></div>' +
            '</div>';
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 定制赛 P2：赛程代码导入 / 后台 single-case 运行 / 状态摘要
    // ════════════════════════════════════════════════════════════════════════════
    function ensureCustomMatchState() {
        if (S._customMatch) return S._customMatch;
        S._customMatch = {
            code: getDefaultCustomMatchCode(),
            parsed: null,
            error: '',
            details: []
        };
        parseCustomMatchCode();
        return S._customMatch;
    }

    function getCustomPresets() {
        if (typeof window !== 'undefined' && window.ArenaCustomPresets) {
            if (window.ArenaCustomPresets.length) return window.ArenaCustomPresets;
            if (window.ArenaCustomPresets.presets && window.ArenaCustomPresets.presets.length) {
                return window.ArenaCustomPresets.presets;
            }
        }
        return [
            { id: 'fallback-default', label: '默认样例', description: '', code: CUSTOM_MATCH_FALLBACK_CODE }
        ];
    }

    function getDefaultCustomMatchCode() {
        var presets = getCustomPresets();
        return (presets[0] && presets[0].code) || CUSTOM_MATCH_FALLBACK_CODE;
    }

    function buildCustomPresetOptions() {
        var presets = getCustomPresets();
        var html = '';
        for (var i = 0; i < presets.length; i++) {
            html += '<option value="' + ArenaCore.escapeAttr(presets[i].id) + '">' + ArenaCore.escapeHtml(presets[i].label) + '</option>';
        }
        return html;
    }

    function getCustomSavedRosters() {
        if (S._customSavedRosters) return S._customSavedRosters;
        S._customSavedRosters = [];
        if (typeof window === 'undefined' || !window.localStorage) return S._customSavedRosters;
        try {
            var raw = window.localStorage.getItem(CUSTOM_SAVED_ROSTERS_KEY);
            if (!raw) return S._customSavedRosters;
            var parsed = JSON.parse(raw);
            var list = parsed && parsed.rosters ? parsed.rosters : (parsed && parsed.length ? parsed : []);
            for (var i = 0; i < list.length; i++) {
                if (!list[i] || !list[i].roster || !list[i].roster.length) continue;
                S._customSavedRosters.push({
                    id: String(list[i].id || ('saved-' + i)),
                    label: String(list[i].label || ('已保存配置 ' + (i + 1))),
                    createdAt: String(list[i].createdAt || ''),
                    roster: cloneCustomRoster(list[i].roster)
                });
            }
        } catch (err) {
            S._customSavedRosters = [];
        }
        return S._customSavedRosters;
    }

    function saveCustomSavedRosters(list) {
        S._customSavedRosters = list || [];
        if (typeof window === 'undefined' || !window.localStorage) {
            ArenaCore.showToast('保存失败：浏览器本地存储不可用');
            return false;
        }
        try {
            window.localStorage.setItem(CUSTOM_SAVED_ROSTERS_KEY, JSON.stringify({
                schema: 'arena-custom-saved-rosters.v1',
                rosters: S._customSavedRosters
            }));
            return true;
        } catch (err) {
            ArenaCore.showToast('保存失败：浏览器本地存储不可用');
            return false;
        }
    }

    function buildCustomSavedRosterOptions() {
        var saved = getCustomSavedRosters();
        if (!saved.length) return '<option value="">暂无已保存配置</option>';
        var html = '';
        for (var i = 0; i < saved.length; i++) {
            html += '<option value="' + ArenaCore.escapeAttr(saved[i].id) + '">' + ArenaCore.escapeHtml(saved[i].label) + '</option>';
        }
        return html;
    }

    function findCustomSavedRosterById(id) {
        var saved = getCustomSavedRosters();
        for (var i = 0; i < saved.length; i++) {
            if (saved[i].id === id) return saved[i];
        }
        return saved[0] || null;
    }

    function collectCustomUnitCatalog() {
        var catalog = {};
        var unitCatalog = (typeof window !== 'undefined' && window.ArenaUnitCatalog)
            ? window.ArenaUnitCatalog.units : null;
        if (unitCatalog && unitCatalog.length) {
            for (var u = 0; u < unitCatalog.length; u++) {
                var unitId = Number(unitCatalog[u].id);
                if (!isNaN(unitId)) catalog[unitId] = unitCatalog[u];
            }
        }

        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (rosters) {
            for (var faction in rosters) {
                var units = (rosters[faction] && rosters[faction].units) || [];
                for (var i = 0; i < units.length; i++) {
                    var id = units[i].type ? Number(String(units[i].type).replace(/^兵种/, '')) : NaN;
                    if (!isNaN(id) && !catalog[id]) catalog[id] = units[i];
                }
            }
        }
        // P1 样例单位兜底：生产 lazy deps 会加载 ArenaMetaRosters；保留兜底只为独立调试页。
        catalog[11] = catalog[11] || { id: 11, name: '巨型僵尸', spritename: '敌人-boss大僵尸' };
        catalog[44] = catalog[44] || { id: 44, name: '左轮', spritename: '敌人-盗贼枪手' };
        catalog[45] = catalog[45] || { id: 45, name: '跳蚤', spritename: '敌人-盗贼侏儒' };
        catalog[48] = catalog[48] || { id: 48, name: '铁拳', spritename: '敌人-盗贼大叔' };
        catalog[164] = catalog[164] || { id: 164, name: '终结者T800', spritename: '敌人-终结者T800' };
        return catalog;
    }

    function getCustomUnitList() {
        var units = (typeof window !== 'undefined' && window.ArenaUnitCatalog && window.ArenaUnitCatalog.units)
            ? window.ArenaUnitCatalog.units : [];
        if (units.length) return units;
        var catalog = collectCustomUnitCatalog();
        var out = [];
        for (var id in catalog) {
            if (!Object.prototype.hasOwnProperty.call(catalog, id)) continue;
            var unit = catalog[id];
            out.push({
                id: Number(id),
                type: '兵种' + id,
                name: unit.name || ('兵种' + id),
                spritename: unit.spritename || '',
                level: unit.level || unit.minLevel || 1,
                height: unit.height || 0,
                slots: unit.slots || [],
                isHostile: unit.isHostile,
                faction: unit.faction || ''
            });
        }
        out.sort(function(a, b) { return a.id - b.id; });
        return out;
    }

    function getCustomUnitById(id) {
        id = Number(id);
        var catalog = collectCustomUnitCatalog();
        return catalog[id] || { id: id, type: '兵种' + id, name: '兵种' + id, spritename: '', level: 1, slots: [] };
    }

    function getCustomUnitParameterPresets(unitId) {
        var store = (typeof window !== 'undefined' && window.ArenaUnitParameterPresets)
            ? window.ArenaUnitParameterPresets : null;
        if (!store || !store.byUnit) return [];
        return store.byUnit[String(Number(unitId))] || [];
    }

    function findCustomUnitParameterPreset(presetId) {
        var store = (typeof window !== 'undefined' && window.ArenaUnitParameterPresets)
            ? window.ArenaUnitParameterPresets : null;
        if (!store || !store.byId || !presetId) return null;
        return store.byId[presetId] || null;
    }

    function buildCustomUnitChoices() {
        var units = getCustomUnitList();
        var out = [];
        for (var i = 0; i < units.length; i++) {
            out.push({ kind: 'base', unit: units[i], preset: null });
            var presets = getCustomUnitParameterPresets(units[i].id);
            for (var p = 0; p < presets.length; p++) {
                out.push({ kind: 'preset', unit: units[i], preset: presets[p] });
            }
        }
        return out;
    }

    function parseCustomMatchCode(options) {
        ensureCustomModule();
        if (!S._customMatch) {
            S._customMatch = { code: getDefaultCustomMatchCode(), parsed: null, error: '', details: [] };
        }
        options = options || {};
        try {
            S._customMatch.parsed = ArenaCustomMatchCode.parseMatchCode(S._customMatch.code, {
                unitCatalog: collectCustomUnitCatalog(),
                caseId: 'arena-custom-p3'
            });
            S._customMatch.code = S._customMatch.parsed.canonical;
            S._customMatch.error = '';
            S._customMatch.details = [];
            if (options.syncEditor !== false) syncCustomEditorFromParsed(S._customMatch.parsed);
        } catch (err) {
            S._customMatch.parsed = null;
            S._customMatch.error = err && err.message ? err.message : String(err);
            S._customMatch.details = err && err.details ? err.details : [];
        }
    }

    function ensureCustomModule() {
        if (typeof ArenaCustomMatchCode === 'undefined' || !ArenaCustomMatchCode.parseMatchCode) {
            throw new Error('ArenaCustomMatchCode 未加载');
        }
        if (typeof ArenaCustomParameters === 'undefined' || !ArenaCustomParameters.parseDraft) {
            throw new Error('ArenaCustomParameters 未加载');
        }
        if (typeof ArenaCustomUndo === 'undefined' || !ArenaCustomUndo.capture) {
            throw new Error('ArenaCustomUndo 未加载');
        }
        if (typeof ArenaCustomPolling === 'undefined' || !ArenaCustomPolling.schedule) {
            throw new Error('ArenaCustomPolling 未加载');
        }
        if (typeof ArenaCustomParamEditor === 'undefined' || !ArenaCustomParamEditor.createState) {
            throw new Error('ArenaCustomParamEditor 未加载');
        }
    }

    function syncCustomEditorFromParsed(parsed) {
        if (!parsed) return;
        var parsedMode = parsed.mode === 'pve' ? 'pve' : 'mvm';
        var previousEditor = S._customEditor || {};
        S._customEditor = {
            mode: parsedMode,
            seed: parsed.seed || 0,
            timeoutFrames: parsed.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            spawnDistance: parsed.spawnDistance || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
            blueFormation: parsed.blueFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
            redFormation: parsed.redFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
            formationSpacing: parsed.formationSpacing || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
            blue: parsedMode === 'pve' ? [] : cloneCustomRoster(parsed.blueRoster),
            red: parsedMode === 'pve' ? cloneCustomRoster(parsed.enemyRoster) : cloneCustomRoster(parsed.redRoster),
            query: previousEditor.query || '',
            filter: previousEditor.filter || 'all',
            expandedFactions: previousEditor.expandedFactions || {},
            unitVisibleRows: previousEditor.unitVisibleRows || CUSTOM_BROWSER_BATCH_SIZE,
            unitScrollableRows: previousEditor.unitScrollableRows || 0
        };
        if (parsedMode === 'pve') S._customSelectedSide = 'red';
        S._customConfirmOpen = false;
    }

    function ensureCustomEditorState() {
        ensureCustomMatchState();
        if (!S._customEditor && S._customMatch && S._customMatch.parsed) syncCustomEditorFromParsed(S._customMatch.parsed);
        if (!S._customEditor) {
            S._customEditor = {
                mode: 'mvm',
                seed: 0,
                timeoutFrames: ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                spawnDistance: ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
                blueFormation: ArenaCustomMatchCode.DEFAULT_FORMATION,
                redFormation: ArenaCustomMatchCode.DEFAULT_FORMATION,
                formationSpacing: ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
                blue: [],
                red: [],
                query: '',
                filter: 'all',
                expandedFactions: {},
                unitVisibleRows: CUSTOM_BROWSER_BATCH_SIZE,
                unitScrollableRows: 0
            };
        }
        sanitizeCustomBattleParams(S._customEditor);
        return S._customEditor;
    }

    function customUndoOptions() {
        return {
            defaultTimeoutFrames: ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            defaultSpawnDistance: ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
            defaultFormation: ArenaCustomMatchCode.DEFAULT_FORMATION,
            defaultFormationSpacing: ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
            browserBatchSize: CUSTOM_BROWSER_BATCH_SIZE
        };
    }

    function sanitizeCustomBattleParams(editor) {
        if (!editor) return;
        editor.timeoutFrames = ArenaCore.clampInt(
            Number(editor.timeoutFrames) || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
            30 * CUSTOM_TIMEOUT_FPS,
            600 * CUSTOM_TIMEOUT_FPS
        );
        editor.spawnDistance = ArenaCore.clampInt(
            Number(editor.spawnDistance) || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
            ArenaCustomMatchCode.MIN_SPAWN_DISTANCE,
            ArenaCustomMatchCode.MAX_SPAWN_DISTANCE
        );
        editor.formationSpacing = ArenaCore.clampInt(
            Number(editor.formationSpacing) || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
            ArenaCustomMatchCode.MIN_FORMATION_SPACING,
            ArenaCustomMatchCode.MAX_FORMATION_SPACING
        );
        editor.blueFormation = normalizeCustomFormation(editor.blueFormation);
        editor.redFormation = normalizeCustomFormation(editor.redFormation);
    }

    function normalizeCustomFormation(value) {
        var id = String(value || ArenaCustomMatchCode.DEFAULT_FORMATION || 'line').toLowerCase();
        var formations = ArenaCustomMatchCode.FORMATIONS || {};
        return formations[id] ? id : (ArenaCustomMatchCode.DEFAULT_FORMATION || 'line');
    }

    function customFormationLabel(id) {
        if (ArenaCustomMatchCode && ArenaCustomMatchCode.formationLabel) {
            return ArenaCustomMatchCode.formationLabel(id);
        }
        for (var i = 0; i < CUSTOM_FORMATION_OPTIONS.length; i++) {
            if (CUSTOM_FORMATION_OPTIONS[i].id === id) return CUSTOM_FORMATION_OPTIONS[i].label;
        }
        return id || '--';
    }

    function customTimeoutSeconds(editor) {
        editor = editor || ensureCustomEditorState();
        return ArenaCore.clampInt(Math.round((Number(editor.timeoutFrames) || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES) / CUSTOM_TIMEOUT_FPS), 30, 600);
    }

    function formatCustomBattleParams(parsed) {
        if (!parsed) return '--';
        return '距离 ' + parsed.spawnDistance +
            ' · 时长 ' + Math.round(parsed.timeoutFrames / CUSTOM_TIMEOUT_FPS) + '秒' +
            ' · ' + formatCustomFormationPair(parsed);
    }

    function formatCustomFormationPair(source) {
        var isPve = source && source.mode === 'pve';
        return (isPve ? '玩家 ' : '蓝 ') + customFormationLabel(source ? source.blueFormation : null) +
            ' / ' + (isPve ? '怪物 ' : '红 ') + customFormationLabel(source ? source.redFormation : null);
    }

    function captureCustomUndo(label) {
        if (!S._customEditor) ensureCustomEditorState();
        S._customUndo = ArenaCustomUndo.capture(S._customEditor, {
            label: label || '上一步',
            selectedSide: S._customSelectedSide,
            editorPage: S._customEditorPage
        }, customUndoOptions());
    }

    function restoreCustomUndo() {
        if (!S._customUndo) {
            ArenaCore.showToast('暂无可撤销操作');
            return;
        }
        var restored = ArenaCustomUndo.restore(S._customUndo, customUndoOptions());
        S._customUndo = null;
        S._customEditor = restored.editor;
        S._customSelectedSide = restored.selectedSide;
        S._customEditorPage = restored.editorPage;
        S._customParamEditor = null;
        syncCustomCodeFromEditor();
        renderCustomEditor();
        renderCustomUnitBrowser();
        ArenaCore.showToast('已撤销：' + restored.label);
    }

    function renderCustomUndoState() {
        var btn = S._el ? S._el.querySelector('#arena-custom-undo') : null;
        ArenaCustomUndo.renderButton(btn, S._customUndo, {
            disabled: S._busy || ArenaResult.customRunActive(),
            truncateText: truncateCustomText
        });
    }

    function renderCustomBattleParams() {
        if (!S._el) return;
        var editor = ensureCustomEditorState();
        sanitizeCustomBattleParams(editor);

        var summaryDistance = S._el.querySelector('#arena-custom-battle-summary-distance');
        var summaryTimeout = S._el.querySelector('#arena-custom-battle-summary-timeout');
        var summaryFormation = S._el.querySelector('#arena-custom-battle-summary-formation');
        var summarySpacing = S._el.querySelector('#arena-custom-battle-summary-spacing');
        var editorMeta = S._el.querySelector('#arena-custom-battle-editor-meta');
        if (summaryDistance) summaryDistance.textContent = editor.spawnDistance + ' px';
        if (summaryTimeout) summaryTimeout.textContent = customTimeoutSeconds(editor) + ' 秒';
        if (summaryFormation) summaryFormation.textContent = formatCustomFormationPair(editor);
        if (summarySpacing) summarySpacing.textContent = editor.formationSpacing + ' px';
        if (editorMeta) editorMeta.textContent = formatCustomBattleParams(editor);

        var distance = S._el.querySelector('#arena-custom-spawn-distance');
        var distanceValue = S._el.querySelector('#arena-custom-spawn-distance-value');
        if (distance) {
            distance.min = ArenaCustomMatchCode.MIN_SPAWN_DISTANCE;
            distance.max = ArenaCustomMatchCode.MAX_SPAWN_DISTANCE;
            distance.step = 10;
            distance.value = editor.spawnDistance;
        }
        if (distanceValue) distanceValue.textContent = editor.spawnDistance + ' px';
        renderCustomPresetButtons('#arena-custom-spawn-distance-presets', 'spawnDistance', CUSTOM_SPAWN_DISTANCE_PRESETS, editor.spawnDistance);

        var timeoutSeconds = customTimeoutSeconds(editor);
        var timeout = S._el.querySelector('#arena-custom-timeout');
        var timeoutValue = S._el.querySelector('#arena-custom-timeout-value');
        if (timeout) {
            timeout.min = 30;
            timeout.max = 600;
            timeout.step = 10;
            timeout.value = timeoutSeconds;
        }
        if (timeoutValue) timeoutValue.textContent = timeoutSeconds + ' 秒';
        renderCustomPresetButtons('#arena-custom-timeout-presets', 'timeoutFrames', CUSTOM_TIMEOUT_PRESETS, editor.timeoutFrames);

        renderCustomFormationButtons('blue', editor.blueFormation);
        renderCustomFormationButtons('red', editor.redFormation);
        renderCustomFormationLegend('blue', editor.blueFormation);
        renderCustomFormationLegend('red', editor.redFormation);

        var blueTitle = S._el.querySelector('#arena-custom-blue-formation-title');
        var redTitle = S._el.querySelector('#arena-custom-red-formation-title');
        if (blueTitle) blueTitle.textContent = editor.mode === 'pve' ? '玩家' : '蓝方';
        if (redTitle) redTitle.textContent = editor.mode === 'pve' ? '怪物' : '红方';
        var summary = S._el.querySelector('#arena-custom-formation-summary');
        if (summary) summary.textContent = customFormationLabel(editor.blueFormation) + ' / ' + customFormationLabel(editor.redFormation);

        var spacing = S._el.querySelector('#arena-custom-formation-spacing');
        var spacingValue = S._el.querySelector('#arena-custom-formation-spacing-value');
        if (spacing) {
            spacing.min = ArenaCustomMatchCode.MIN_FORMATION_SPACING;
            spacing.max = ArenaCustomMatchCode.MAX_FORMATION_SPACING;
            spacing.step = 2;
            spacing.value = editor.formationSpacing;
        }
        if (spacingValue) spacingValue.textContent = editor.formationSpacing + ' px';
    }

    function renderCustomPresetButtons(selector, field, presets, currentValue) {
        var el = S._el ? S._el.querySelector(selector) : null;
        if (!el) return;
        var html = '';
        for (var i = 0; i < presets.length; i++) {
            var active = Number(presets[i].value) === Number(currentValue);
            html += '<button class="arena-custom-preset-chip' + (active ? ' arena-custom-preset-chip-active' : '') + '" type="button" data-custom-battle-preset="' + field + '" data-custom-battle-value="' + presets[i].value + '" data-audio-cue="confirm">' + ArenaCore.escapeHtml(presets[i].label) + '</button>';
        }
        el.innerHTML = html;
    }

    function renderCustomFormationButtons(side, current) {
        var el = S._el ? S._el.querySelector('#arena-custom-' + side + '-formation-options') : null;
        if (!el) return;
        var html = '';
        for (var i = 0; i < CUSTOM_FORMATION_OPTIONS.length; i++) {
            var option = CUSTOM_FORMATION_OPTIONS[i];
            html += '<button class="arena-custom-formation-option' + (option.id === current ? ' arena-custom-formation-option-active' : '') + '" type="button" data-custom-formation-side="' + side + '" data-custom-formation-value="' + option.id + '" data-audio-cue="confirm">' + ArenaCore.escapeHtml(option.label) + '</button>';
        }
        el.innerHTML = html;
    }

    function renderCustomFormationLegend(side, formation) {
        var el = S._el ? S._el.querySelector('#arena-custom-' + side + '-formation-legend') : null;
        if (!el) return;
        var positions = buildCustomFormationPreview(formation, 9, side);
        var html = '';
        for (var i = 0; i < positions.length; i++) {
            html += '<i style="left:' + positions[i].x + '%;top:' + positions[i].y + '%">' + (i + 1) + '</i>';
        }
        el.innerHTML = html;
    }

    function buildCustomFormationPreview(formation, count, side) {
        var out = [];
        var i, row, col, lane, laneCount, depth;
        formation = normalizeCustomFormation(formation);
        for (i = 0; i < count; i++) {
            if (formation === 'column') {
                out.push({ x: 26, y: previewFormationY(i, count) });
            } else if (formation === 'wedge') {
                row = Math.floor((Math.sqrt(8 * i + 1) - 1) / 2);
                col = i - (row * (row + 1) / 2);
                laneCount = Math.min(row + 1, Math.max(1, count - (row * (row + 1) / 2)));
                out.push({ x: 26 + row * 14, y: previewFormationY(col, laneCount) });
            } else if (formation === 'shield') {
                laneCount = Math.min(5, count);
                if (i < laneCount) {
                    out.push({ x: 26, y: previewFormationY(i, laneCount) });
                } else {
                    row = Math.floor((i - laneCount) / 2) + 1;
                    col = (i - laneCount) % 2;
                    out.push({ x: 26 + row * 20, y: previewFormationY(col, Math.min(2, count - laneCount - (row - 1) * 2)) });
                }
            } else if (formation === 'grid') {
                laneCount = Math.min(3, Math.ceil(Math.sqrt(count)));
                depth = Math.floor(i / laneCount);
                lane = i % laneCount;
                out.push({ x: 26 + depth * 16, y: previewFormationY(lane, Math.min(laneCount, count - depth * laneCount)) });
            } else {
                out.push({ x: 26 + i * 6, y: 50 });
            }
        }
        if (side === 'blue') {
            for (i = 0; i < out.length; i++) {
                out[i].x = 100 - out[i].x;
            }
        }
        return out;
    }

    function previewFormationY(lane, laneCount) {
        if (laneCount <= 1) return 50;
        return 14 + (72 * lane / (laneCount - 1));
    }

    function enhanceCustomSelects() {
        if (!S._customEditorViewEl) return;
        var selects = S._customEditorViewEl.querySelectorAll('select.arena-custom-preset-select');
        for (var i = 0; i < selects.length; i++) {
            var select = selects[i];
            var shell = findCustomSelectShell(select);
            if (!shell) {
                shell = document.createElement('div');
                shell.className = 'arena-custom-select-shell';
                select.parentNode.insertBefore(shell, select);
                shell.appendChild(select);
            }
            select.classList.add('arena-custom-native-select');
            select.setAttribute('tabindex', '-1');

            var trigger = shell.querySelector('.arena-custom-select-trigger');
            if (!trigger) {
                trigger = document.createElement('button');
                trigger.type = 'button';
                trigger.className = 'arena-custom-select-trigger';
                trigger.setAttribute('data-custom-select-trigger', '1');
                trigger.setAttribute('aria-haspopup', 'listbox');
                shell.insertBefore(trigger, select);
            }

            var menu = shell.querySelector('.arena-custom-select-menu');
            if (!menu) {
                menu = document.createElement('div');
                menu.className = 'arena-custom-select-menu';
                menu.setAttribute('data-custom-select-menu', '1');
                menu.setAttribute('role', 'listbox');
                menu.hidden = true;
                shell.appendChild(menu);
            }
            syncCustomSelect(select);
        }
    }

    function findCustomSelectShell(node) {
        while (node && node !== S._customEditorViewEl) {
            if (node.classList && node.classList.contains('arena-custom-select-shell')) return node;
            node = node.parentNode;
        }
        return null;
    }

    function syncCustomSelect(select) {
        var shell = findCustomSelectShell(select);
        if (!shell) return;
        var trigger = shell.querySelector('.arena-custom-select-trigger');
        var menu = shell.querySelector('.arena-custom-select-menu');
        var option = select.options[select.selectedIndex] || select.options[0];
        var label = option ? option.text : '';
        if (trigger) {
            trigger.textContent = label;
            trigger.removeAttribute('title');
            trigger.setAttribute('data-custom-tooltip', label);
            trigger.disabled = !!select.disabled;
            trigger.setAttribute('aria-expanded', shell.classList.contains('arena-custom-select-open') ? 'true' : 'false');
        }
        if (menu && !menu.hidden) renderCustomSelectMenu(select, menu);
    }

    function renderCustomSelectMenu(select, menu) {
        var value = select.value;
        var html = '';
        for (var i = 0; i < select.options.length; i++) {
            var option = select.options[i];
            var active = option.value === value;
            html += '<button class="arena-custom-select-option' + (active ? ' arena-custom-select-option-active' : '') + '" type="button" role="option" aria-selected="' + (active ? 'true' : 'false') + '" data-custom-select-value="' + ArenaCore.escapeAttr(option.value) + '">' + ArenaCore.escapeHtml(option.text) + '</button>';
        }
        menu.innerHTML = html;
    }

    function closeCustomSelectMenus(exceptShell) {
        if (!S._customEditorViewEl) return;
        var shells = S._customEditorViewEl.querySelectorAll('.arena-custom-select-shell');
        for (var i = 0; i < shells.length; i++) {
            if (exceptShell && shells[i] === exceptShell) continue;
            shells[i].classList.remove('arena-custom-select-open');
            var menu = shells[i].querySelector('.arena-custom-select-menu');
            var trigger = shells[i].querySelector('.arena-custom-select-trigger');
            if (menu) menu.hidden = true;
            if (trigger) trigger.setAttribute('aria-expanded', 'false');
        }
        S._customSelectOpen = exceptShell || null;
    }

    function openCustomSelect(select) {
        var shell = findCustomSelectShell(select);
        if (!shell) return;
        var menu = shell.querySelector('.arena-custom-select-menu');
        var trigger = shell.querySelector('.arena-custom-select-trigger');
        closeCustomSelectMenus(shell);
        renderCustomSelectMenu(select, menu);
        shell.classList.add('arena-custom-select-open');
        if (menu) menu.hidden = false;
        if (trigger) trigger.setAttribute('aria-expanded', 'true');
        S._customSelectOpen = shell;
        var active = menu ? menu.querySelector('.arena-custom-select-option-active') : null;
        if (active && active.scrollIntoView) active.scrollIntoView({ block: 'nearest' });
    }

    function handleCustomSelectClick(e) {
        var node = e.target;
        var shellAtTarget = findCustomSelectShell(node);
        while (node && node !== S._customEditorViewEl) {
            if (node.getAttribute) {
                if (node.getAttribute('data-custom-select-trigger')) {
                    var triggerShell = findCustomSelectShell(node);
                    var triggerSelect = triggerShell ? triggerShell.querySelector('select.arena-custom-preset-select') : null;
                    if (triggerSelect) {
                        if (triggerShell.classList.contains('arena-custom-select-open')) closeCustomSelectMenus();
                        else openCustomSelect(triggerSelect);
                        e.preventDefault();
                        return true;
                    }
                }
                if (node.getAttribute('data-custom-select-value') != null) {
                    var optionShell = findCustomSelectShell(node);
                    var optionSelect = optionShell ? optionShell.querySelector('select.arena-custom-preset-select') : null;
                    if (optionSelect) {
                        optionSelect.value = node.getAttribute('data-custom-select-value');
                        syncCustomSelect(optionSelect);
                        closeCustomSelectMenus();
                        optionSelect.dispatchEvent(new Event('change', { bubbles: true }));
                        e.preventDefault();
                        return true;
                    }
                }
            }
            node = node.parentNode;
        }
        if (!shellAtTarget) closeCustomSelectMenus();
        return false;
    }

    function onCustomSelectKeydown(e) {
        var shell = findCustomSelectShell(e.target);
        if (!shell) return;
        var select = shell.querySelector('select.arena-custom-preset-select');
        if (!select) return;
        var key = e.key || e.keyCode;
        if (key === 'Escape' || key === 27) {
            closeCustomSelectMenus();
            e.preventDefault();
            return;
        }
        if (key === 'Enter' || key === ' ' || key === 'ArrowDown' || key === 13 || key === 32 || key === 40) {
            if (!shell.classList.contains('arena-custom-select-open')) {
                openCustomSelect(select);
                e.preventDefault();
                return;
            }
        }
        if (shell.classList.contains('arena-custom-select-open') && (key === 'ArrowDown' || key === 'ArrowUp' || key === 40 || key === 38)) {
            var delta = (key === 'ArrowUp' || key === 38) ? -1 : 1;
            var next = Math.max(0, Math.min(select.options.length - 1, select.selectedIndex + delta));
            if (next !== select.selectedIndex) {
                select.selectedIndex = next;
                syncCustomSelect(select);
                select.dispatchEvent(new Event('change', { bubbles: true }));
            }
            e.preventDefault();
        }
    }

    function cloneCustomRoster(roster) {
        var out = [];
        roster = roster || [];
        for (var i = 0; i < roster.length; i++) {
            var id = roster[i].id != null ? roster[i].id : ArenaCustomMatchCode.normalizeUnitId(roster[i].type);
            var entry = {
                id: Number(id),
                type: '兵种' + Number(id),
                level: Number(roster[i].level) || 1,
                count: Number(roster[i].count) || 1
            };
            var parameters = roster[i].parameters || roster[i].Parameters || roster[i]['参数'];
            if (customHasParameters(parameters)) entry.parameters = cloneCustomParameters(parameters);
            if (roster[i].presetId) entry.presetId = roster[i].presetId;
            if (roster[i].presetLabel) entry.presetLabel = roster[i].presetLabel;
            out.push(entry);
        }
        return out;
    }

    function cloneCustomParameters(value) {
        return ArenaCustomParameters.clone(value);
    }

    function customHasParameters(value) {
        return ArenaCustomParameters.has(value);
    }

    function customParameterText(value) {
        return ArenaCustomParameters.text(value);
    }

    function customParametersEqual(a, b) {
        return ArenaCustomParameters.equal(a, b);
    }

    function syncCustomCodeFromEditor(options) {
        options = options || {};
        ensureCustomModule();
        var editor = ensureCustomEditorState();
        sanitizeCustomBattleParams(editor);
        if (editor.mode === 'pve') {
            S._customSelectedSide = 'red';
            S._customMatch.code = ArenaCustomMatchCode.serializeMatchCode({
                mode: 'pve',
                seed: editor.seed || 0,
                timeoutFrames: editor.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                spawnDistance: editor.spawnDistance || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
                blueFormation: editor.blueFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                redFormation: editor.redFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                formationSpacing: editor.formationSpacing || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
                enemyRoster: editor.red,
                player: 'current'
            });
        } else {
            S._customMatch.code = ArenaCustomMatchCode.serializeMatchCode({
                mode: 'mvm',
                seed: editor.seed || 0,
                timeoutFrames: editor.timeoutFrames || ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
                spawnDistance: editor.spawnDistance || ArenaCustomMatchCode.DEFAULT_SPAWN_DISTANCE,
                blueFormation: editor.blueFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                redFormation: editor.redFormation || ArenaCustomMatchCode.DEFAULT_FORMATION,
                formationSpacing: editor.formationSpacing || ArenaCustomMatchCode.DEFAULT_FORMATION_SPACING,
                blueRoster: editor.blue,
                redRoster: editor.red
            });
        }
        parseCustomMatchCode({ syncEditor: false });
        S._customConfirmOpen = false;
        if (options.refresh !== false) refreshCustomMatchCard();
    }

    function refreshCustomMatchCard() {
        if (S._activeMode !== 'custom') return;
        ensureCustomMatchState();
        ensureCustomEditorState();
        var input = S._el ? S._el.querySelector('#arena-custom-code-input') : null;
        if (input && document.activeElement !== input) input.value = S._customMatch.code;

        var summaryEl = S._el ? S._el.querySelector('#arena-custom-summary') : null;
        var caseEl = S._el ? S._el.querySelector('#arena-custom-case') : null;
        var statusEl = S._el ? S._el.querySelector('#arena-custom-status') : null;
        var feeEl = S._el ? S._el.querySelector('#arena-custom-fee') : null;
        var btn = S._el ? S._el.querySelector('.arena-custom-generate') : null;
        var abortBtn = S._el ? S._el.querySelector('.arena-custom-abort') : null;
        var subtitleEl = S._el ? S._el.querySelector('.arena-custom-subtitle') : null;
        renderCustomEditor();
        // 阵容增删/数量修改会经 syncCustomCodeFromEditor 回到这里。此时单位目录
        // 的查询、筛选与展开集合都没有改变，重建目录不得把维护者送回顶部。
        // 搜索、筛选、切换势力和首次进入单方页仍由各自入口无 preserveScroll
        // 地渲染，因此语义变化后的结果起点保持不变。
        renderCustomUnitBrowser({ preserveScroll: S._customEditorPage === 'side' });
        renderCustomConfirm();
        renderCustomCodeStatus();
        if (!summaryEl || !caseEl || !statusEl || !feeEl || !btn || !abortBtn) return;

        if (!S._customMatch.parsed) {
            summaryEl.innerHTML = buildCustomErrorHtml(S._customMatch);
            caseEl.textContent = '等待有效赛程代码';
            statusEl.innerHTML = ArenaResult.buildCustomRunStatusHtml(false);
            feeEl.textContent = '--';
            btn.disabled = true;
            abortBtn.disabled = true;
            return;
        }

        var parsed = S._customMatch.parsed;
        if (parsed.mode === 'pve') {
            var enemyCount = customRosterTotal(parsed.enemyRoster);
            if (subtitleEl) subtitleEl.textContent = '玩家 vs 怪物 · 标准竞技场 · 无掉落无经验';
            summaryEl.innerHTML =
                '<div class="arena-custom-side arena-custom-side-blue arena-custom-side-player">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">玩家</span>' +
                        '<span class="arena-custom-side-count">当前存档</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">使用当前角色、装备、技能和操作</span>' +
                '</div>' +
                '<div class="arena-custom-vs-mark">VS</div>' +
                '<div class="arena-custom-side arena-custom-side-red">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">怪物</span>' +
                        '<span class="arena-custom-side-count">' + enemyCount + ' 单位</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">' + ArenaCore.escapeHtml(summarizeCustomRoster(parsed.enemyRoster)) + '</span>' +
                    '<button class="arena-custom-side-edit" type="button" data-custom-action="edit" data-custom-edit-side="red" data-audio-cue="confirm">调整怪物</button>' +
                '</div>';
            caseEl.textContent =
                'seed=' + parsed.seed +
                ' · player=current' +
                ' · ' + formatCustomBattleParams(parsed) +
                ' · 无掉落 / 无经验 / 标准竞技场';
        } else {
            var blueCount = customRosterTotal(parsed.blueRoster);
            var redCount = customRosterTotal(parsed.redRoster);
            if (subtitleEl) subtitleEl.textContent = '怪物 vs 怪物 · 后台单局 · 无掉落无经验';
            summaryEl.innerHTML =
                '<div class="arena-custom-side arena-custom-side-blue">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">蓝方</span>' +
                        '<span class="arena-custom-side-count">' + blueCount + ' 单位</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">' + ArenaCore.escapeHtml(summarizeCustomRoster(parsed.blueRoster)) + '</span>' +
                    '<button class="arena-custom-side-edit" type="button" data-custom-action="edit" data-custom-edit-side="blue" data-audio-cue="confirm">调整蓝方</button>' +
                '</div>' +
                '<div class="arena-custom-vs-mark">VS</div>' +
                '<div class="arena-custom-side arena-custom-side-red">' +
                    '<div class="arena-custom-side-head">' +
                        '<span class="arena-custom-side-title">红方</span>' +
                        '<span class="arena-custom-side-count">' + redCount + ' 单位</span>' +
                    '</div>' +
                    '<span class="arena-custom-side-roster">' + ArenaCore.escapeHtml(summarizeCustomRoster(parsed.redRoster)) + '</span>' +
                    '<button class="arena-custom-side-edit" type="button" data-custom-action="edit" data-custom-edit-side="red" data-audio-cue="confirm">调整红方</button>' +
                '</div>';
            caseEl.textContent =
                'seed=' + parsed.seed +
                ' · 上限 ' + parsed.calibrationCase.timeoutFrames + ' 帧' +
                ' · ' + formatCustomBattleParams(parsed) +
                ' · 无掉落 / 无经验 / 原死亡流程';
        }
        statusEl.innerHTML = ArenaResult.buildCustomRunStatusHtml(parsed.mode === 'pve');
        feeEl.textContent = ArenaCore.formatMoney(parsed.venueFeeEstimate);
        btn.textContent = S._customConfirmOpen ? '确认页已打开' : '检查并确认';
        btn.disabled = S._busy || (parsed.mode !== 'pve' && ArenaResult.customRunActive());
        abortBtn.disabled = S._busy || parsed.mode === 'pve' || !ArenaResult.customRunActive();
    }

    function renderCustomEditor() {
        if (!S._el) return;
        var editor = ensureCustomEditorState();
        if (editor.mode === 'pve') S._customSelectedSide = 'red';
        var configPage = S._el.querySelector('[data-custom-editor-page="config"]');
        var battlePage = S._el.querySelector('[data-custom-editor-page="battle"]');
        var sidePage = S._el.querySelector('[data-custom-editor-page="side"]');
        if (configPage) configPage.hidden = S._customEditorPage !== 'config';
        if (battlePage) battlePage.hidden = S._customEditorPage !== 'battle';
        if (sidePage) sidePage.hidden = S._customEditorPage !== 'side';
        // P3：参数页不再走 hidden 切换，由 SecondaryPage 承载（syncCustomParamPageVisibility）

        var modeBtns = S._el.querySelectorAll('[data-custom-mode]');
        for (var mb = 0; mb < modeBtns.length; mb++) {
            var mode = modeBtns[mb].getAttribute('data-custom-mode');
            modeBtns[mb].classList.toggle('arena-custom-mode-active', mode === editor.mode);
        }
        renderCustomUndoState();

        var sideConfigs = S._el.querySelector('.arena-custom-side-configs');
        if (sideConfigs) sideConfigs.classList.toggle('arena-custom-side-configs-pve', editor.mode === 'pve');
        var swapActions = S._el.querySelector('#arena-custom-swap-actions');
        if (swapActions) swapActions.classList.toggle('arena-custom-pve-actions', editor.mode === 'pve');
        var swapBtn = S._el.querySelector('[data-custom-action="swap-sides"]');
        if (swapBtn) swapBtn.hidden = editor.mode === 'pve';
        var presetLabel = S._el.querySelector('label[for="arena-custom-preset-select"]');
        if (presetLabel) presetLabel.textContent = editor.mode === 'pve' ? '待标定怪物组合' : '整局待标定组合';

        var blueConfigEl = S._el.querySelector('#arena-custom-config-blue');
        var redConfigEl = S._el.querySelector('#arena-custom-config-red');
        if (blueConfigEl) {
            blueConfigEl.hidden = false;
            blueConfigEl.classList.toggle('arena-custom-side-config-player', editor.mode === 'pve');
            blueConfigEl.innerHTML = editor.mode === 'pve'
                ? buildCustomPlayerConfigCardHtml()
                : buildCustomSideConfigCardHtml('blue', editor.blue);
        }
        if (redConfigEl) redConfigEl.innerHTML = buildCustomSideConfigCardHtml('red', editor.red);

        var activeRoster = getCustomSideRoster(S._customSelectedSide);
        var activeRosterEl = S._el.querySelector('#arena-custom-active-roster');
        if (activeRosterEl) {
            releaseCustomTooltips(activeRosterEl);
            activeRosterEl.innerHTML = buildCustomRosterEditorHtml(S._customSelectedSide, activeRoster);
            mountCustomUnitPortraits(activeRosterEl);
        }

        var activePanel = S._el.querySelector('#arena-custom-active-roster-panel');
        if (activePanel) {
            activePanel.setAttribute('data-side', S._customSelectedSide);
            activePanel.classList.toggle('arena-custom-roster-blue', S._customSelectedSide === 'blue');
            activePanel.classList.toggle('arena-custom-roster-red', S._customSelectedSide === 'red');
        }
        var titleEl = S._el.querySelector('#arena-custom-side-editor-title');
        var kickerEl = S._el.querySelector('#arena-custom-side-editor-kicker');
        var metaEl = S._el.querySelector('#arena-custom-side-editor-meta');
        var countEl = S._el.querySelector('#arena-custom-active-roster-count');
        var sideLabel = customSideLabel(S._customSelectedSide);
        if (kickerEl) kickerEl.textContent = sideLabel + '阵容';
        if (titleEl) titleEl.textContent = '编辑' + sideLabel;
        if (metaEl) metaEl.textContent = customRosterTotal(activeRoster) + ' 单位 · ' + (activeRoster.length ? summarizeCustomRoster(activeRoster) : '空阵容');
        if (countEl) countEl.textContent = customRosterTotal(activeRoster) + ' 单位';

        var savedOptions = buildCustomSavedRosterOptions();
        var savedSelects = S._el.querySelectorAll('[data-custom-saved-select]');
        for (var ss = 0; ss < savedSelects.length; ss++) {
            savedSelects[ss].innerHTML = savedOptions;
        }
        renderCustomBattleParams();

        var panels = S._el.querySelectorAll('.arena-custom-roster-panel');
        for (var i = 0; i < panels.length; i++) {
            panels[i].classList.toggle('arena-custom-roster-active', panels[i].getAttribute('data-side') === S._customSelectedSide);
        }
        var sideBtns = S._el.querySelectorAll('[data-custom-side]');
        for (var s = 0; s < sideBtns.length; s++) {
            var side = sideBtns[s].getAttribute('data-custom-side');
            if (editor.mode === 'pve' && side === 'blue') {
                sideBtns[s].hidden = true;
                continue;
            }
            sideBtns[s].hidden = false;
            if (editor.mode === 'pve' && side === 'red') sideBtns[s].textContent = '加到怪物';
            else sideBtns[s].textContent = side === 'red' ? '加到红方' : '加到蓝方';
            sideBtns[s].classList.toggle('arena-custom-side-target-active', side === S._customSelectedSide);
        }
        renderCustomParamEditor();
        enhanceCustomSelects();
        bindCustomTooltips(S._customEditorViewEl);
        syncCustomParamPageVisibility();
    }

    // P3：参数页 = SecondaryPage。open/close 与 _customEditorPage 同步（唯一状态驱动点）：
    // open 时编辑器头部与其余页面对象由组件压制（inert + aria-hidden），焦点移入并
    // trap Tab；close 由各领域出口（返回阵容/保存返回/Esc/编辑器整页关闭级联）触发。
    // 编辑器整页隐藏时（总览/结算页互斥）不做开合——隐藏的编辑器里没有可呈现的二级页。
    function syncCustomParamPageVisibility() {
        if (!S._customParamPage) return;
        if (S._customEditorViewEl && S._customEditorViewEl.hidden) return;
        if (S._customEditorPage === 'params') {
            if (!S._customParamPage.isActive()) {
                S._customParamPage.open({
                    opener: S._customParamOpener,
                    initialFocus: '[data-custom-param-action="back"]'
                });
            }
        } else if (S._customParamPage.isActive()) {
            S._customParamPage.close('page-switch', { restoreFocus: false });
        }
    }

    function buildCustomSideConfigCardHtml(side, roster) {
        var sideLabel = customSideLabel(side);
        var total = customRosterTotal(roster);
        var empty = !roster || !roster.length;
        var rosterText = empty ? '尚未配置单位' : summarizeCustomRoster(roster);
        return '<div class="arena-custom-side-config-head">' +
                '<div>' +
                    '<div class="arena-custom-side-title">' + sideLabel + '</div>' +
                    '<div class="arena-custom-side-count">' + total + ' 单位</div>' +
                '</div>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="edit" data-side="' + side + '" data-audio-cue="confirm">编辑阵容</button>' +
            '</div>' +
            '<div class="arena-custom-side-config-roster">' + ArenaCore.escapeHtml(rosterText) + '</div>' +
            '<div class="arena-custom-side-config-load">' +
                '<select class="arena-custom-preset-select" data-custom-saved-select="' + side + '" aria-label="' + sideLabel + '已保存配置">' + buildCustomSavedRosterOptions() + '</select>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="load" data-side="' + side + '" data-audio-cue="confirm">读取</button>' +
            '</div>' +
            '<div class="arena-custom-side-config-actions">' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="random" data-side="' + side + '" data-audio-cue="confirm">随机组合</button>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="save" data-side="' + side + '" data-audio-cue="confirm">保存配置</button>' +
                '<button class="arena-custom-btn" type="button" data-custom-side-action="clear" data-side="' + side + '" data-audio-cue="cancel">清空</button>' +
            '</div>';
    }

    function buildCustomPlayerConfigCardHtml() {
        return '<div class="arena-custom-side-config-head">' +
                '<div>' +
                    '<div class="arena-custom-side-title">玩家</div>' +
                    '<div class="arena-custom-side-count">当前存档</div>' +
                '</div>' +
            '</div>' +
            '<div class="arena-custom-side-config-roster arena-custom-player-config-roster">' +
                '使用当前角色、装备、技能和操作' +
            '</div>';
    }

    function customSideLabel(side) {
        var editor = S._customEditor || null;
        if (editor && editor.mode === 'pve') return side === 'red' ? '怪物' : '玩家';
        return side === 'red' ? '红方' : '蓝方';
    }

    function resolveCustomSide(side) {
        var editor = S._customEditor || null;
        if (editor && editor.mode === 'pve') return 'red';
        if (side === 'active') return S._customSelectedSide;
        return side === 'red' ? 'red' : 'blue';
    }

    function getCustomSideRoster(side) {
        var editor = ensureCustomEditorState();
        return resolveCustomSide(side) === 'red' ? editor.red : editor.blue;
    }

    function setCustomSideRoster(side, roster) {
        var editor = ensureCustomEditorState();
        if (resolveCustomSide(side) === 'red') editor.red = cloneCustomRoster(roster || []);
        else editor.blue = cloneCustomRoster(roster || []);
        syncCustomCodeFromEditor();
    }

    function showCustomEditorConfigPage() {
        S._customEditorPage = 'config';
        S._customParamEditor = null;
        renderCustomEditor();
        renderCustomUnitBrowser();
    }

    function showCustomSideEditorPage(side) {
        S._customSelectedSide = resolveCustomSide(side);
        S._customEditorPage = 'side';
        S._customParamEditor = null;
        renderCustomEditor();
        renderCustomUnitBrowser();
    }

    function showCustomBattleEditorPage() {
        S._customEditorPage = 'battle';
        S._customParamEditor = null;
        renderCustomEditor();
    }

    function showCustomParamEditorPage(side, index) {
        side = resolveCustomSide(side);
        var entry = getCustomRosterEntry(side, index);
        if (!entry) return;
        S._customSelectedSide = side;
        S._customParamEditor = buildCustomParamEditorState(side, index, 'json', entry);
        // 记录 opener（阵容行「参数」按钮），供 SecondaryPage opener 归还语义使用；
        // 阵容列表随 render 重建，真实归还由 focusCustomParamOpener 按 side/index 找回新节点
        S._customParamOpener = (typeof document !== 'undefined' && document.activeElement
            && document.activeElement.hasAttribute
            && document.activeElement.hasAttribute('data-custom-edit-params'))
            ? document.activeElement : null;
        S._customEditorPage = 'params';
        renderCustomEditor();
    }

    function buildCustomParamEditorState(side, index, mode, entry) {
        return ArenaCustomParamEditor.createState(side, index, mode, entry);
    }

    function getCustomRosterEntry(side, index) {
        var editor = ensureCustomEditorState();
        var roster = resolveCustomSide(side) === 'red' ? editor.red : editor.blue;
        index = Number(index);
        if (index < 0 || index >= roster.length) return null;
        return roster[index];
    }

    function renderCustomParamEditor() {
        if (!S._el) return;
        var bodyEl = S._el.querySelector('#arena-custom-param-editor-body');
        if (!bodyEl) return;
        if (S._customEditorPage !== 'params') return;

        var state = S._customParamEditor;
        var entry = state ? getCustomRosterEntry(state.side, state.index) : null;
        ArenaCustomParamEditor.render({
            rootEl: S._el,
            bodyEl: bodyEl,
            state: state,
            entry: entry,
            unit: entry ? getCustomUnitById(entry.id) : null,
            sideLabel: state ? customSideLabel(state.side) : '',
            summary: entry ? (summarizeCustomParameters(entry.parameters) || '默认参数') : '',
            titleEl: S._el.querySelector('#arena-custom-param-editor-title'),
            kickerEl: S._el.querySelector('#arena-custom-param-editor-kicker'),
            metaEl: S._el.querySelector('#arena-custom-param-editor-meta'),
            escapeHtml: ArenaCore.escapeHtml
        });
    }

    function customParamEditorDirty() {
        var entry = S._customParamEditor ? getCustomRosterEntry(S._customParamEditor.side, S._customParamEditor.index) : null;
        return ArenaCustomParamEditor.dirty(S._customParamEditor, entry);
    }

    function leaveCustomParamEditorDiscardingDraft() {
        var side = S._customParamEditor ? S._customParamEditor.side : S._customSelectedSide;
        var index = S._customParamEditor ? S._customParamEditor.index : -1;
        if (customParamEditorDirty()) ArenaCore.showToast('已放弃未应用参数草稿');
        showCustomSideEditorPage(side);
        focusCustomParamOpener(side, index);
    }

    // 参数页 opener 焦点归还（P3 共享合同）：阵容列表随 renderCustomEditor 重建，
    // 按 side/index 在重渲后的阵容行上找回同一个「参数」入口。
    function focusCustomParamOpener(side, index) {
        if (!S._el || index == null || index < 0) return;
        var btn = S._el.querySelector('#arena-custom-active-roster [data-custom-edit-params][data-side="'
            + side + '"][data-index="' + index + '"]');
        if (btn && typeof btn.focus === 'function') btn.focus({ preventScroll: true });
    }

    function updateCustomParamDraft(text) {
        if (!S._customParamEditor) return;
        ArenaCustomParamEditor.updateDraft(S._customParamEditor, text);
        updateCustomParamInlineState();
    }

    function updateCustomParamInlineState() {
        if (!S._el || S._customEditorPage !== 'params') return;
        var entry = S._customParamEditor ? getCustomRosterEntry(S._customParamEditor.side, S._customParamEditor.index) : null;
        ArenaCustomParamEditor.updateInline(S._el, S._customParamEditor, entry);
    }

    function setCustomParamEditorMode(mode) {
        if (!S._customParamEditor) return;
        if (!ArenaCustomParamEditor.setMode(S._customParamEditor, mode)) {
            renderCustomEditor();
            return;
        }
        renderCustomEditor();
    }

    function applyCustomParamDraft(returnToSide) {
        if (!S._customParamEditor) return false;
        var mode = S._customParamEditor.mode === 'xml' ? 'xml' : 'json';
        var parsed = ArenaCustomParamEditor.parseCurrent(S._customParamEditor);
        if (!parsed.ok) {
            S._customParamEditor.error = parsed.error;
            renderCustomEditor();
            return false;
        }
        var side = S._customParamEditor.side;
        var index = S._customParamEditor.index;
        if (!setCustomRosterParametersValue(side, index, parsed.value)) return false;
        var entry = getCustomRosterEntry(side, index);
        if (entry) {
            S._customParamEditor = buildCustomParamEditorState(side, index, mode, entry);
        }
        ArenaCore.showToast(customSideLabel(side) + '单位参数已应用');
        if (returnToSide) {
            showCustomSideEditorPage(side);
            focusCustomParamOpener(side, index);
        } else renderCustomEditor();
        return true;
    }

    function clearCustomParamDraft() {
        if (!S._customParamEditor) return;
        ArenaCustomParamEditor.clearDraft(S._customParamEditor);
        renderCustomEditor();
    }

    function buildCustomRosterEditorHtml(side, roster) {
        if (!roster || !roster.length) {
            return '<div class="arena-custom-roster-empty">从右侧单位目录添加到' + customSideLabel(side) + '</div>';
        }
        var html = '';
        for (var i = 0; i < roster.length; i++) {
            var entry = roster[i];
            var unit = getCustomUnitById(entry.id);
            var paramSummary = entry.presetLabel || summarizeCustomParameters(entry.parameters);
            var paramLabel = paramSummary ? truncateCustomText(paramSummary, 22) : '默认参数';
            var paramClass = customHasParameters(entry.parameters) ? ' arena-custom-param-pill-active' : '';
            html += '<div class="arena-custom-roster-row">' +
                buildCustomUnitPortraitHtml(unit) +
                '<div class="arena-custom-roster-info">' +
                    '<b>' + ArenaCore.escapeHtml(unit.name || ('兵种' + entry.id)) + '</b>' +
                    '<span>兵种' + entry.id + ' · ' + ArenaCore.escapeHtml(unit.spritename || '--') + (paramSummary ? ' · ' + ArenaCore.escapeHtml(paramSummary) : '') + '</span>' +
                '</div>' +
                '<label>Lv.<input class="arena-custom-mini-input" type="number" min="1" max="999" value="' + entry.level + '" data-custom-roster-input="level" data-side="' + side + '" data-index="' + i + '"></label>' +
                '<div class="arena-custom-count-stepper">' +
                    '<button type="button" data-custom-adjust-count="-1" data-side="' + side + '" data-index="' + i + '" data-audio-cue="cancel">−</button>' +
                    '<input class="arena-custom-mini-input" type="number" min="1" max="20" value="' + entry.count + '" data-custom-roster-input="count" data-side="' + side + '" data-index="' + i + '">' +
                    '<button type="button" data-custom-adjust-count="1" data-side="' + side + '" data-index="' + i + '" data-audio-cue="confirm">+</button>' +
                '</div>' +
                '<button class="arena-custom-param-pill' + paramClass + '" type="button" data-custom-edit-params data-side="' + side + '" data-index="' + i + '" data-custom-tooltip="' + ArenaCore.escapeAttr(paramSummary || '编辑单位参数') + '" data-audio-cue="confirm">' +
                    '<span>' + ArenaCore.escapeHtml(paramLabel) + '</span>' +
                    '<b>参数</b>' +
                '</button>' +
                '<button class="arena-custom-icon-btn" type="button" data-custom-tooltip="移除" data-custom-remove data-side="' + side + '" data-index="' + i + '" data-audio-cue="cancel">×</button>' +
            '</div>';
        }
        return html;
    }

    function renderCustomUnitBrowser(options) {
        options = options || {};
        var listEl = S._el ? S._el.querySelector('#arena-custom-unit-list') : null;
        var countEl = S._el ? S._el.querySelector('#arena-custom-unit-count') : null;
        var searchEl = S._el ? S._el.querySelector('#arena-custom-unit-search') : null;
        if (!listEl || !countEl || !searchEl) return;
        disconnectCustomPortraitObserver();
        releaseCustomTooltips(listEl);
        var previousScrollTop = options.preserveScroll ? listEl.scrollTop : 0;
        var editor = ensureCustomEditorState();
        editor.expandedFactions = editor.expandedFactions || {};
        editor.unitVisibleRows = editor.unitVisibleRows || CUSTOM_BROWSER_BATCH_SIZE;
        if (document.activeElement !== searchEl) searchEl.value = editor.query || '';

        var query = ArenaCore.normalizeSearchText(editor.query || '');
        var filter = editor.filter || 'all';
        var choices = buildCustomUnitChoices();
        var factionLookup = buildCustomFactionLookup();
        var groups = [];
        var groupMap = {};
        var matchCount = 0;
        for (var i = 0; i < choices.length; i++) {
            var choice = choices[i];
            var unit = choice.unit;
            if (filter === 'hostile' && unit.isHostile === false) continue;
            if (filter === 'nonhostile' && unit.isHostile !== false) continue;
            var faction = customUnitFaction(unit, factionLookup);
            if (query && ArenaCore.normalizeSearchText(customUnitChoiceSearchText(choice, faction)).indexOf(query) < 0) continue;
            var key = faction || '未归类';
            if (!groupMap[key]) {
                groupMap[key] = { key: key, label: customFactionLabel(key), units: [] };
                groups.push(groupMap[key]);
            }
            groupMap[key].units.push({ choice: choice, faction: key });
            matchCount++;
        }
        groups.sort(sortCustomUnitGroups);

        countEl.textContent = matchCount + '/' + choices.length + ' 条目';
        renderCustomPortraitCoverage();
        var filterBtns = S._el.querySelectorAll('[data-custom-unit-filter]');
        for (var f = 0; f < filterBtns.length; f++) {
            filterBtns[f].classList.toggle('arena-custom-unit-filter-active', filterBtns[f].getAttribute('data-custom-unit-filter') === filter);
        }
        if (!matchCount) {
            listEl.innerHTML = '<div class="arena-custom-unit-empty">没有匹配单位</div>';
            editor.unitScrollableRows = 0;
            return;
        }
        var html = '';
        var renderedRows = 0;
        var expandedRows = 0;
        var hiddenRows = 0;
        var forceExpanded = !!query;
        for (var g = 0; g < groups.length; g++) {
            var group = groups[g];
            var expanded = forceExpanded || editor.expandedFactions[group.key] === true;
            html += buildCustomUnitGroupHtml(group, expanded, forceExpanded);
            if (!expanded) continue;
            expandedRows += group.units.length;
            for (var m = 0; m < group.units.length; m++) {
                if (renderedRows >= editor.unitVisibleRows) {
                    hiddenRows += group.units.length - m;
                    break;
                }
                html += buildCustomUnitRowHtml(group.units[m].choice, group.units[m].faction);
                renderedRows++;
            }
        }
        if (hiddenRows > 0) {
            html += '<div class="arena-custom-unit-more">继续滚动加载剩余 ' + hiddenRows + ' 个单位</div>';
        }
        listEl.innerHTML = html;
        mountCustomUnitPortraits(listEl);
        editor.unitScrollableRows = expandedRows;
        if (options.preserveScroll) listEl.scrollTop = previousScrollTop;
        else listEl.scrollTop = 0;
    }

    function buildCustomFactionLookup() {
        var lookup = {};
        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (!rosters) return lookup;
        for (var faction in rosters) {
            if (!Object.prototype.hasOwnProperty.call(rosters, faction)) continue;
            var units = (rosters[faction] && rosters[faction].units) || [];
            for (var i = 0; i < units.length; i++) {
                if (units[i].type) lookup[units[i].type] = faction;
            }
        }
        return lookup;
    }

    function customUnitFaction(unit, lookup) {
        if (unit && unit.faction) return unit.faction;
        var type = unit && unit.type ? unit.type : ('兵种' + (unit ? unit.id : ''));
        return (lookup && lookup[type]) || '未归类';
    }

    function customFactionLabel(faction) {
        if (!faction || faction === 'unknown' || faction === '未归类') return '未归类';
        return faction;
    }

    function sortCustomUnitGroups(a, b) {
        if (a.key === '未归类' && b.key !== '未归类') return 1;
        if (b.key === '未归类' && a.key !== '未归类') return -1;
        if (a.label === b.label) return 0;
        return a.label > b.label ? 1 : -1;
    }

    function buildCustomUnitGroupHtml(group, expanded, queryActive) {
        var cls = 'arena-custom-unit-group' +
            (expanded ? ' arena-custom-unit-group-expanded' : '') +
            (queryActive ? ' arena-custom-unit-group-search' : '');
        return '<button class="' + cls + '" type="button" data-custom-toggle-faction="' + ArenaCore.escapeAttr(group.key) + '" data-custom-faction-count="' + group.units.length + '" data-audio-cue="confirm">' +
            '<span class="arena-custom-unit-group-arrow">' + (expanded ? '▾' : '▸') + '</span>' +
            '<span class="arena-custom-unit-group-name">' + ArenaCore.escapeHtml(group.label) + '</span>' +
            '<span class="arena-custom-unit-group-count">' + group.units.length + '</span>' +
        '</button>';
    }

    function buildCustomUnitRowHtml(choice, faction) {
        var unit = choice.unit;
        var preset = choice.preset;
        var slots = summarizeCustomSlots(unit);
        var hostileLabel = unit.isHostile === false ? ' · 非敌对' : '';
        var factionLabel = faction && faction !== '未归类' ? ' · ' + faction : '';
        var presetLabel = preset ? (' · 预设 · ' + (preset.summary || summarizeCustomParameters(preset.parameters))) : '';
        var presetAttr = preset ? ' data-custom-preset-id="' + ArenaCore.escapeAttr(preset.id) + '"' : '';
        var rowClass = 'arena-custom-unit-row' +
            (preset ? ' arena-custom-unit-row-preset' : '') +
            (unit.isHostile === false ? ' arena-custom-unit-row-nonhostile' : '');
        return '<button class="' + rowClass + '" type="button" data-custom-add-unit="' + unit.id + '"' + presetAttr + ' data-custom-faction="' + ArenaCore.escapeAttr(faction || '') + '" data-audio-cue="confirm">' +
            buildCustomUnitPortraitHtml(unit) +
            '<span class="arena-custom-unit-main">' +
                '<b>' + ArenaCore.escapeHtml(unit.name || ('兵种' + unit.id)) + '</b>' +
                '<em>' + ArenaCore.escapeHtml(unit.spritename || '--') + '</em>' +
            '</span>' +
            '<span class="arena-custom-unit-meta">Lv.' + (preset && preset.defaultLevel ? preset.defaultLevel : (unit.level || 1)) + factionLabel + hostileLabel + presetLabel + (slots ? ' · ' + ArenaCore.escapeHtml(slots) : '') + '</span>' +
        '</button>';
    }

    function buildCustomUnitPortraitHtml(unit) {
        unit = unit || {};
        var portraitRef = unit.spritename || '';
        var portraitKind = customUnitUsesDressupPortrait(unit) ? 'dressup' : 'enemy';
        var title = portraitRef ? ((portraitKind === 'dressup' ? '纸娃娃头像：' : '怪物头像：') + portraitRef) : '头像来源缺失';
        return '<span class="arena-custom-unit-portrait" data-arena-unit-id="' + ArenaCore.escapeAttr(unit.id == null ? '' : unit.id) + '" data-arena-portrait-kind="' + portraitKind + '" data-arena-portrait-ref="' + ArenaCore.escapeAttr(portraitRef) + '" data-custom-tooltip="' + ArenaCore.escapeAttr(title) + '">' +
            '<img alt="" draggable="false">' +
            '<span class="arena-custom-unit-id-badge">u' + (unit.id == null ? '--' : unit.id) + '</span>' +
        '</span>';
    }

    function customUnitUsesDressupPortrait(unit) {
        return !!(unit && unit.portrait && unit.portrait.kind === 'dressup'
            && unit.portrait.actor && typeof unit.portrait.actor === 'object');
    }

    function getCustomTooltipScope() {
        if (_customTooltipScope && !_customTooltipScope.disposed) return _customTooltipScope;
        _customTooltipScope = (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.createScope)
            ? PanelTooltip.createScope('arena-custom-editor', {profile:'simple-tooltip'}) : null;
        return _customTooltipScope;
    }

    function releaseCustomTooltips(root) {
        if (!root) return;
        // 释放旧 DOM 时不得为了“释放”反向创建一个全新 scope；首次真实绑定时再创建。
        var scope = (_customTooltipScope && !_customTooltipScope.disposed) ? _customTooltipScope : null;
        if (scope && scope.releaseTree) scope.releaseTree(root);
        else if (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.releaseTree) {
            PanelTooltip.releaseTree(root);
        }
    }

    function buildCustomTooltipHtml(text) {
        return '<div class="arena-custom-simple-tooltip">' + ArenaCore.escapeHtml(text || '') + '</div>';
    }

    function bindCustomTooltips(root) {
        if (!root) return;
        var scope = getCustomTooltipScope();
        if (!scope || !scope.bindAsync) return;
        var nodes = root.querySelectorAll('[data-custom-tooltip]');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].removeAttribute('title');
            scope.bindAsync(nodes[i], {
                key: function(e, node) { return 'arena-custom:' + (node.getAttribute('data-custom-tooltip') || ''); },
                resolveItem: function(e, node) { return node.getAttribute('data-custom-tooltip') || ''; },
                renderBasic: buildCustomTooltipHtml
            });
        }
    }

    function disconnectCustomPortraitObserver() {
        if (_customPortraitObserver) _customPortraitObserver.disconnect();
        _customPortraitObserver = null;
    }

    function mountCustomUnitPortrait(node) {
        if (!node || node.getAttribute('data-arena-portrait-mounted') === '1') return;
        var img = node.querySelector('img');
        if (!img) return;
        node.setAttribute('data-arena-portrait-mounted', '1');
        var unit = getCustomUnitById(node.getAttribute('data-arena-unit-id'));
        if (customUnitUsesDressupPortrait(unit)) {
            MercPortraits.mount(node, img, unit.portrait.actor, {
                // 与佣兵卡共享同一个 cacheKey、胸像相机与 112px 快照；竞技场只决定窗口尺寸。
                variant: 'card',
                size: 112,
                alt: ''
            });
            return;
        }
        EnemyPortraits.mount(node, img, {
            consumer: 'arena',
            portraitRef: node.getAttribute('data-arena-portrait-ref') || '',
            legacyUrl: EnemyPortraits.fallbackUrl()
        });
    }

    function mountCustomUnitPortraits(root) {
        // 标准挑战页仍会预渲染隐藏的定制编辑器 DOM；隐藏态不应提前拉取
        // manifest/头像。showCustomEditorView 会先取消 hidden 再重渲染，届时
        // 才执行真实挂载，避免普通竞技场入口产生无意义请求和离页取消噪音。
        if (!root || !window.EnemyPortraits || !window.MercPortraits || !S._customEditorViewEl || S._customEditorViewEl.hidden) return;
        bindCustomTooltips(root);
        var nodes = root.querySelectorAll('[data-arena-portrait-ref]');
        var lazyList = root.id === 'arena-custom-unit-list' && typeof IntersectionObserver !== 'undefined';
        if (lazyList) {
            disconnectCustomPortraitObserver();
            _customPortraitObserver = new IntersectionObserver(function(entries, observer) {
                for (var j = 0; j < entries.length; j++) {
                    if (!entries[j].isIntersecting) continue;
                    observer.unobserve(entries[j].target);
                    mountCustomUnitPortrait(entries[j].target);
                }
            }, {
                root: root,
                rootMargin: '144px 0px',
                threshold: 0.01
            });
            for (var n = 0; n < nodes.length; n++) _customPortraitObserver.observe(nodes[n]);
            return;
        }
        for (var i = 0; i < nodes.length; i++) {
            mountCustomUnitPortrait(nodes[i]);
        }
    }

    function customCatalogPortraitRoutes() {
        var units = window.ArenaUnitCatalog && window.ArenaUnitCatalog.units || [];
        var routes = {};
        var enemyRefs = [];
        var dressupReadyRefs = [];
        var dressupMissingRefs = [];
        for (var i = 0; i < units.length; i++) {
            var ref = String(units[i].spritename || '').trim();
            if (!ref) continue;
            var dressupRef = ref.indexOf('主角-') === 0;
            if (!routes[ref]) routes[ref] = { kind: dressupRef ? 'dressup' : 'enemy', ready: true };
            if (dressupRef && !customUnitUsesDressupPortrait(units[i])) routes[ref].ready = false;
        }
        Object.keys(routes).forEach(function(ref) {
            if (routes[ref].kind === 'dressup') {
                (routes[ref].ready ? dressupReadyRefs : dressupMissingRefs).push(ref);
            } else enemyRefs.push(ref);
        });
        return {
            total: Object.keys(routes).length,
            enemyRefs: enemyRefs,
            dressupReadyRefs: dressupReadyRefs,
            dressupMissingRefs: dressupMissingRefs
        };
    }

    function customCatalogPortraitCoverage() {
        var routes = customCatalogPortraitRoutes();
        return EnemyPortraits.coverage(routes.enemyRefs).then(function(enemy) {
            var dressupReady = routes.dressupReadyRefs.length;
            var dressupMissing = routes.dressupMissingRefs.length;
            return {
                manifestAvailable: enemy.manifestAvailable,
                total: routes.total,
                ready: enemy.ready + dressupReady,
                missing: enemy.missing + dressupMissing,
                missingRefs: enemy.missingRefs.concat(routes.dressupMissingRefs),
                routes: {
                    enemy: { total: enemy.total, ready: enemy.ready, missing: enemy.missing },
                    dressup: { total: dressupReady + dressupMissing, ready: dressupReady, missing: dressupMissing }
                }
            };
        });
    }

    function renderCustomPortraitCoverage() {
        var el = S._el ? S._el.querySelector('#arena-custom-portrait-coverage') : null;
        if (!el || !window.EnemyPortraits || !S._customEditorViewEl || S._customEditorViewEl.hidden) return;
        el.textContent = '头像核对中';
        el.setAttribute('data-coverage-state', 'loading');
        if (!_customPortraitCoveragePromise) {
            _customPortraitCoveragePromise = customCatalogPortraitCoverage();
        }
        _customPortraitCoveragePromise.then(function(result) {
            if (!el.isConnected) return;
            el.textContent = '头像 ' + result.ready + '/' + result.total;
            el.setAttribute('data-coverage-ready', result.ready);
            el.setAttribute('data-coverage-missing', result.missing);
            el.setAttribute('data-coverage-total', result.total);
            el.setAttribute('data-coverage-enemy-ready', result.routes.enemy.ready);
            el.setAttribute('data-coverage-dressup-ready', result.routes.dressup.ready);
            el.setAttribute('data-coverage-state', result.manifestAvailable ? (result.missing ? 'partial' : 'complete') : 'unavailable');
            el.setAttribute('data-custom-tooltip', result.manifestAvailable
                ? ('纸娃娃 ' + result.routes.dressup.ready + '/' + result.routes.dressup.total +
                    '；怪物清单 ' + result.routes.enemy.ready + '/' + result.routes.enemy.total +
                    (result.missing ? ('；' + result.missing + ' 个仍使用锁定图回退') : '；全目录头像已闭合'))
                : '头像清单不可用，当前全部使用锁定图回退');
        });
    }

    function summarizeCustomSlots(unit) {
        var slots = unit && unit.slots ? unit.slots : [];
        if (!slots.length) return '';
        var parts = [];
        for (var i = 0; i < slots.length && i < 2; i++) {
            parts.push(slots[i].value);
        }
        return parts.join(' / ');
    }

    function customUnitSearchText(unit, faction) {
        return [
            unit.id,
            unit.type,
            unit.name,
            unit.spritename,
            faction || unit.faction || '',
            summarizeCustomSlots(unit)
        ].join(' ');
    }

    function customUnitChoiceSearchText(choice, faction) {
        var preset = choice && choice.preset;
        return [
            customUnitSearchText(choice.unit, faction),
            preset ? preset.id : '',
            preset ? preset.label : '',
            preset ? preset.summary : '',
            preset && preset.parameterKeys ? preset.parameterKeys.join(' ') : '',
            preset && preset.sourceStages ? preset.sourceStages.join(' ') : '',
            preset ? customParameterText(preset.parameters) : ''
        ].join(' ');
    }

    function renderCustomConfirm() {
        var confirmEl = S._el ? S._el.querySelector('#arena-custom-confirm') : null;
        if (!confirmEl) return;
        var bodyEl = confirmEl.querySelector('#arena-custom-confirm-body');
        var cardEl = S._el ? S._el.querySelector('.arena-card-custom') : null;
        if (!S._customConfirmOpen || !S._customMatch || !S._customMatch.parsed) {
            confirmEl.hidden = true;
            if (bodyEl) bodyEl.innerHTML = '';
            if (cardEl) cardEl.classList.remove('arena-card-custom-confirming');
            if (S._customConfirmBar) S._customConfirmBar.update({ label: '确认委托', status: '', canCommit: false, state: '', busy: false });
            return;
        }
        var parsed = S._customMatch.parsed;
        confirmEl.hidden = false;
        if (cardEl) cardEl.classList.add('arena-card-custom-confirming');
        if (parsed.mode === 'pve') {
            if (bodyEl) bodyEl.innerHTML =
                '<div class="arena-custom-confirm-head">' +
                    '<div>' +
                        '<div class="arena-custom-confirm-title">确认挑战</div>' +
                        '<div class="arena-custom-confirm-subtitle">启动后关闭 Web 面板，使用当前玩家进入标准竞技场</div>' +
                    '</div>' +
                    '<div class="arena-custom-confirm-fee">' + ArenaCore.formatMoney(0) + '</div>' +
                '</div>' +
                '<div class="arena-custom-confirm-grid">' +
                    '<span>玩家</span><b>当前存档 / 当前装备 / 当前操作</b>' +
                    '<span>怪物</span><b>' + ArenaCore.escapeHtml(summarizeCustomRoster(parsed.enemyRoster)) + '</b>' +
                    '<span>战场参数</span><b>' + ArenaCore.escapeHtml(formatCustomBattleParams(parsed)) + '</b>' +
                    '<span>规则</span><b>无押金 / 无奖金 / 无掉落 / 无经验</b>' +
                    '<span>复现</span><b>仅复现怪物配置，不复现玩家状态</b>' +
                '</div>';
        } else {
            if (bodyEl) bodyEl.innerHTML =
                '<div class="arena-custom-confirm-head">' +
                    '<div>' +
                        '<div class="arena-custom-confirm-title">确认委托</div>' +
                        '<div class="arena-custom-confirm-subtitle">启动后将关闭 Web 面板，战斗结束再回开结算页</div>' +
                    '</div>' +
                    '<div class="arena-custom-confirm-fee">' + ArenaCore.formatMoney(parsed.venueFeeEstimate) + '</div>' +
                '</div>' +
                '<div class="arena-custom-confirm-grid">' +
                    '<span>蓝方</span><b>' + ArenaCore.escapeHtml(summarizeCustomRoster(parsed.blueRoster)) + '</b>' +
                    '<span>红方</span><b>' + ArenaCore.escapeHtml(summarizeCustomRoster(parsed.redRoster)) + '</b>' +
                    '<span>战斗上限</span><b>' + parsed.calibrationCase.timeoutFrames + ' 帧</b>' +
                    '<span>战场参数</span><b>' + ArenaCore.escapeHtml(formatCustomBattleParams(parsed)) + '</b>' +
                    '<span>规则</span><b>无掉落 / 无经验 / 原死亡流程</b>' +
                '</div>';
        }
        // 共享 CommitBar 状态投影（§5.2：成本与提交状态在确认区同区域呈现）：
        // busy = custom_start/enter 飞行中（原实现主按钮 busy 期仍可点、静默 no-op，P3 修正为可见禁用）
        if (S._customConfirmBar) {
            if (S._busy) {
                S._customConfirmBar.update({ busy: true, status: '正在提交，请稍候…', state: 'busy' });
            } else if (parsed.mode === 'pve') {
                S._customConfirmBar.update({
                    label: '开始挑战',
                    status: '免费 · 使用当前玩家进入标准竞技场',
                    canCommit: true, state: 'ready', busy: false
                });
            } else {
                S._customConfirmBar.update({
                    label: '确认委托',
                    status: '场地费 ' + ArenaCore.formatMoney(parsed.venueFeeEstimate) + ' · 委托后关闭面板',
                    canCommit: !ArenaResult.customRunActive(), state: 'ready', busy: false
                });
            }
        }
    }

    // custom_start / PVE enter 失败：除 toast 外把失败原因落到确认条（交互真实性：
    // 失败原因不随 toast 消失，下次动作前持续可读）
    function setCustomConfirmError(text) {
        if (S._customConfirmBar && S._customConfirmOpen) {
            S._customConfirmBar.update({ busy: false, canCommit: true, state: 'error', status: String(text || '提交失败') });
        }
    }

    function buildCustomErrorHtml(state) {
        var text = state.error || '解析失败';
        if (state.details && state.details.length) {
            text += ': ' + state.details.map(function(d) {
                return (d.field ? d.field + ' ' : '') + d.message;
            }).join('; ');
        }
        return '<div class="arena-opponents-error">' + ArenaCore.escapeHtml(text) + '</div>';
    }

    function summarizeCustomRoster(roster) {
        roster = roster || [];
        var parts = [];
        for (var i = 0; i < roster.length; i++) {
            var params = summarizeCustomParameters(roster[i].parameters);
            parts.push(roster[i].type + (params ? '{' + params + '}' : '') + ' Lv.' + roster[i].level + ' ×' + roster[i].count);
        }
        return parts.join(' / ');
    }

    function summarizeCustomParameters(parameters) {
        if (!customHasParameters(parameters)) return '';
        var parts = [];
        var keys = Object.keys(parameters).sort();
        for (var i = 0; i < keys.length && parts.length < 3; i++) {
            var key = keys[i];
            var value = parameters[key];
            if (value == null || typeof value === 'object') parts.push(key);
            else parts.push(key + '=' + String(value));
        }
        if (keys.length > parts.length) parts.push('+' + (keys.length - parts.length));
        return parts.join(' / ');
    }

    function truncateCustomText(text, maxLen) {
        text = String(text || '');
        maxLen = Number(maxLen) || 24;
        if (text.length <= maxLen) return text;
        return text.slice(0, Math.max(1, maxLen - 1)) + '…';
    }

    function customRosterTotal(roster) {
        var total = 0;
        roster = roster || [];
        for (var i = 0; i < roster.length; i++) total += Number(roster[i].count) || 0;
        return total;
    }

    function renderCustomCodeStatus() {
        var el = S._el ? S._el.querySelector('#arena-custom-code-status') : null;
        if (!el || !S._customMatch) return;
        if (S._customMatch.parsed) {
            var parsed = S._customMatch.parsed;
            var left = parsed.mode === 'pve'
                ? customRosterTotal(parsed.enemyRoster)
                : customRosterTotal(parsed.blueRoster);
            var right = parsed.mode === 'pve'
                ? 1
                : customRosterTotal(parsed.redRoster);
            el.className = 'arena-custom-code-status arena-custom-code-status-ok';
            el.textContent = '实时解析 OK · mode=' + parsed.mode + ' · seed=' + parsed.seed + ' · ' + left + ' vs ' + right + ' · ' + formatCustomBattleParams(parsed);
        } else {
            el.className = 'arena-custom-code-status arena-custom-code-status-error';
            el.textContent = '实时解析失败 · ' + (S._customMatch.error || '赛程代码无效');
        }
    }

    function onCustomCodeInput(e) {
        ensureCustomMatchState();
        var input = e.target || e.currentTarget;
        S._customMatch.code = input.value;
        parseCustomMatchCode();
        refreshCustomMatchCard();
    }

    function handleCustomAction(action, node) {
        if (!action) return false;
        if (S._busy || ArenaResult.customRunActive()) return true;
        ensureCustomMatchState();
        if (action === 'random') {
            applyRandomCustomPreset();
        } else if (action === 'preset') {
            applySelectedCustomPreset();
        } else if (action === 'copy') {
            copyCustomMatchCode();
        } else if (action === 'swap-sides') {
            swapCustomSides();
        } else if (action === 'edit') {
            ArenaShell.showCustomEditorForSide(node ? node.getAttribute('data-custom-edit-side') : '');
        } else {
            parseCustomMatchCode();
            refreshCustomMatchCard();
            ArenaCore.showToast(S._customMatch.parsed ? '赛程代码已导入' : '赛程代码无效');
        }
        return true;
    }

    function setCustomEditorMode(mode) {
        mode = mode === 'pve' ? 'pve' : 'mvm';
        var editor = ensureCustomEditorState();
        if (editor.mode === mode) return;
        captureCustomUndo('切换模式');
        editor.mode = mode;
        if (mode === 'pve') {
            S._customSelectedSide = 'red';
            if (!editor.red.length) {
                var fallback = parseCustomCodeForEditor(CUSTOM_PVE_FALLBACK_CODE);
                if (fallback && fallback.enemyRoster) editor.red = cloneCustomRoster(fallback.enemyRoster);
            }
        } else if (!editor.blue.length) {
            var parsed = parseCustomCodeForEditor(CUSTOM_MATCH_FALLBACK_CODE);
            if (parsed) {
                editor.blue = cloneCustomRoster(parsed.blueRoster);
                if (!editor.red.length) editor.red = cloneCustomRoster(parsed.redRoster);
            }
        }
        syncCustomCodeFromEditor();
        ArenaCore.showToast(mode === 'pve' ? '已切换为玩家 vs 怪物' : '已切换为怪物 vs 怪物');
    }

    function applyRandomCustomPreset() {
        var presets = getCustomPresets();
        captureCustomUndo('随机整局');
        if (!presets.length) {
            applyCustomMatchCode(getDefaultCustomMatchCode(), '已载入默认组合');
            return;
        }
        var nextIndex = Math.floor(Math.random() * presets.length);
        if (presets.length > 1 && nextIndex === S._customSampleIndex) {
            nextIndex = (nextIndex + 1) % presets.length;
        }
        S._customSampleIndex = nextIndex;
        var select = S._el ? S._el.querySelector('#arena-custom-preset-select') : null;
        if (select && presets[S._customSampleIndex]) {
            select.value = presets[S._customSampleIndex].id;
            syncCustomSelect(select);
        }
        applyCustomPresetCodeForCurrentMode(presets[S._customSampleIndex].code, '已随机抽取待标定组合');
    }

    function applySelectedCustomPreset() {
        var select = S._el ? S._el.querySelector('#arena-custom-preset-select') : null;
        var preset = findCustomPresetById(select ? select.value : '');
        captureCustomUndo('载入整局');
        applyCustomPresetCodeForCurrentMode((preset && preset.code) || getDefaultCustomMatchCode(), '已载入待标定组合');
    }

    function applyCustomPresetCodeForCurrentMode(code, toast) {
        var editor = ensureCustomEditorState();
        if (editor.mode !== 'pve') {
            applyCustomMatchCode(code, toast);
            return;
        }
        var parsed = parseCustomCodeForEditor(code);
        if (!parsed) {
            ArenaCore.showToast('预设解析失败');
            return;
        }
        var roster = parsed.mode === 'pve'
            ? parsed.enemyRoster
            : ((parsed.redRoster && parsed.redRoster.length) ? parsed.redRoster : parsed.blueRoster);
        editor.red = cloneCustomRoster(roster || []);
        syncCustomCodeFromEditor();
        if (toast) ArenaCore.showToast(toast);
    }

    function parseCustomCodeForEditor(code) {
        ensureCustomModule();
        try {
            return ArenaCustomMatchCode.parseMatchCode(code, {
                unitCatalog: collectCustomUnitCatalog(),
                caseId: 'arena-custom-p3'
            });
        } catch (err) {
            return null;
        }
    }

    function applyRandomCustomSidePreset(side) {
        side = resolveCustomSide(side);
        var presets = getCustomPresets();
        if (!presets.length) return;
        var preset = presets[Math.floor(Math.random() * presets.length)];
        var parsed = parseCustomPresetForRoster(preset);
        if (!parsed) {
            ArenaCore.showToast('随机组合解析失败');
            return;
        }
        var roster = parsed.mode === 'pve'
            ? parsed.enemyRoster
            : ((parsed.redRoster && parsed.redRoster.length) ? parsed.redRoster : parsed.blueRoster);
        captureCustomUndo(customSideLabel(side) + '随机组合');
        setCustomSideRoster(side, roster || []);
        ArenaCore.showToast(customSideLabel(side) + '已随机抽取待标定组合');
    }

    function parseCustomPresetForRoster(preset) {
        if (!preset || !preset.code) return null;
        return parseCustomCodeForEditor(preset.code);
    }

    function saveCustomSideConfig(side) {
        side = resolveCustomSide(side);
        var roster = cloneCustomRoster(getCustomSideRoster(side));
        if (!roster.length) {
            ArenaCore.showToast(customSideLabel(side) + '为空，未保存');
            return;
        }
        var summary = summarizeCustomRoster(roster);
        var label = customSideLabel(side) + ' · ' + customRosterTotal(roster) + '体 · ' + truncateCustomText(summary, 26);
        var saved = getCustomSavedRosters().slice();
        saved.unshift({
            id: 'saved-' + Date.now() + '-' + Math.floor(Math.random() * 10000),
            label: label,
            createdAt: new Date().toISOString(),
            roster: roster
        });
        if (saved.length > CUSTOM_SAVED_ROSTER_LIMIT) saved.length = CUSTOM_SAVED_ROSTER_LIMIT;
        if (!saveCustomSavedRosters(saved)) return;
        renderCustomEditor();
        ArenaCore.showToast(customSideLabel(side) + '配置已保存');
    }

    function loadCustomSideConfig(side) {
        side = resolveCustomSide(side);
        var selectorKey = side;
        var activeSelect = S._el ? S._el.querySelector('[data-custom-saved-select="active"]') : null;
        if (S._customEditorPage === 'side' && activeSelect) selectorKey = 'active';
        var select = S._el ? S._el.querySelector('[data-custom-saved-select="' + selectorKey + '"]') : null;
        var saved = findCustomSavedRosterById(select ? select.value : '');
        if (!saved) {
            ArenaCore.showToast('暂无可读取配置');
            return;
        }
        captureCustomUndo(customSideLabel(side) + '读取配置');
        setCustomSideRoster(side, saved.roster);
        ArenaCore.showToast(customSideLabel(side) + '已读取配置');
    }

    function swapCustomSides() {
        var editor = ensureCustomEditorState();
        captureCustomUndo('交换红蓝');
        var nextBlue = cloneCustomRoster(editor.red);
        var nextRed = cloneCustomRoster(editor.blue);
        editor.blue = nextBlue;
        editor.red = nextRed;
        S._customSelectedSide = S._customSelectedSide === 'red' ? 'blue' : 'red';
        syncCustomCodeFromEditor();
        ArenaCore.showToast('红蓝配置已交换');
    }

    function handleCustomSideAction(action, side) {
        if (!action) return false;
        if (S._busy || ArenaResult.customRunActive()) return true;
        if ((S._customEditor && S._customEditor.mode === 'pve') && side === 'blue') {
            ArenaCore.showToast('玩家使用当前存档，无需配置');
            return true;
        }
        side = resolveCustomSide(side);
        if (action === 'edit') {
            showCustomSideEditorPage(side);
        } else if (action === 'random') {
            applyRandomCustomSidePreset(side);
        } else if (action === 'save') {
            saveCustomSideConfig(side);
        } else if (action === 'load') {
            loadCustomSideConfig(side);
        } else if (action === 'clear') {
            clearCustomRosterSide(side);
        } else {
            return false;
        }
        return true;
    }

    function findCustomPresetById(id) {
        var presets = getCustomPresets();
        for (var i = 0; i < presets.length; i++) {
            if (presets[i].id === id) return presets[i];
        }
        return presets[0] || null;
    }

    function applyCustomMatchCode(code, toast) {
        ensureCustomMatchState();
        S._customMatch.code = code || getDefaultCustomMatchCode();
        parseCustomMatchCode();
        refreshCustomMatchCard();
        if (toast) ArenaCore.showToast(toast);
    }

    function onCustomUnitSearchInput(e) {
        var editor = ensureCustomEditorState();
        var input = e.target || e.currentTarget;
        editor.query = input.value || '';
        resetCustomUnitBrowserWindow(editor);
        renderCustomUnitBrowser();
    }

    function resetCustomUnitBrowserWindow(editor) {
        editor = editor || ensureCustomEditorState();
        editor.unitVisibleRows = CUSTOM_BROWSER_BATCH_SIZE;
    }

    function onCustomUnitBrowserScroll(e) {
        var listEl = e.currentTarget || e.target;
        if (!listEl) return;
        if (listEl.scrollTop + listEl.clientHeight < listEl.scrollHeight - 48) return;
        var editor = ensureCustomEditorState();
        var visibleRows = editor.unitVisibleRows || CUSTOM_BROWSER_BATCH_SIZE;
        var totalRows = editor.unitScrollableRows || 0;
        if (visibleRows >= totalRows) return;
        editor.unitVisibleRows = Math.min(totalRows, visibleRows + CUSTOM_BROWSER_BATCH_SIZE);
        renderCustomUnitBrowser({ preserveScroll: true });
    }

    function toggleCustomUnitFaction(factionKey) {
        var editor = ensureCustomEditorState();
        editor.expandedFactions = editor.expandedFactions || {};
        if (editor.expandedFactions[factionKey]) delete editor.expandedFactions[factionKey];
        else editor.expandedFactions[factionKey] = true;
        resetCustomUnitBrowserWindow(editor);
        // 展开/收起只改变当前目录的局部结构；分类按钮可能位于长目录深处，
        // 重建分组时必须保留维护者所在位置。搜索、过滤等结果集变化仍由
        // 各自入口使用默认渲染，从顶部展示新的语义结果。
        renderCustomUnitBrowser({ preserveScroll: true });
    }

    function onCustomEditorInput(e) {
        var input = e.target;
        if (!input) return;
        if (input.id === 'arena-custom-code-input') {
            onCustomCodeInput(e);
            return;
        }
        if (input.hasAttribute && input.hasAttribute('data-custom-param-editor-input')) {
            updateCustomParamDraft(input.value);
            return;
        }
        if (input.hasAttribute && input.hasAttribute('data-custom-battle-field')) {
            applyCustomBattleInput(input, false);
            return;
        }
        if (input.id !== 'arena-custom-unit-search') return;
        onCustomUnitSearchInput(e);
    }

    function onCustomSideSelect(e) {
        var side = e.currentTarget.getAttribute('data-custom-side');
        if (side === 'blue' || side === 'red') {
            if ((S._customEditor && S._customEditor.mode === 'pve') && side === 'blue') {
                S._customSelectedSide = 'red';
                renderCustomEditor();
                return;
            }
            S._customSelectedSide = side;
            renderCustomEditor();
        }
    }

    function onCustomWorkbenchClick(e) {
        if (handleCustomSelectClick(e)) return;
        var node = e.target;
        while (node && node !== e.currentTarget) {
            if (node.getAttribute) {
                var editorAction = node.getAttribute('data-custom-editor-action');
                if (editorAction === 'back' || editorAction === 'done') {
                    if (editorAction === 'back' && S._customEditorPage === 'params') {
                        leaveCustomParamEditorDiscardingDraft();
                        return;
                    }
                    if (editorAction === 'back' && (S._customEditorPage === 'side' || S._customEditorPage === 'battle')) {
                        showCustomEditorConfigPage();
                        return;
                    }
                    ArenaShell.showGridView();
                    return;
                }
                if (editorAction === 'undo') {
                    restoreCustomUndo();
                    return;
                }
                if (editorAction === 'to-config') {
                    showCustomEditorConfigPage();
                    return;
                }
                if (editorAction === 'to-battle') {
                    showCustomBattleEditorPage();
                    return;
                }
                if (editorAction === 'copy') {
                    copyCustomMatchCode();
                    return;
                }
                var customMode = node.getAttribute('data-custom-mode');
                if (customMode === 'mvm' || customMode === 'pve') {
                    setCustomEditorMode(customMode);
                    return;
                }
                var customAction = node.getAttribute('data-custom-action');
                if (handleCustomAction(customAction, node)) {
                    return;
                }
                var battlePreset = node.getAttribute('data-custom-battle-preset');
                if (battlePreset) {
                    setCustomBattleValue(battlePreset, Number(node.getAttribute('data-custom-battle-value')), true);
                    return;
                }
                var formationSide = node.getAttribute('data-custom-formation-side');
                if (formationSide === 'blue' || formationSide === 'red') {
                    setCustomFormationValue(formationSide, node.getAttribute('data-custom-formation-value'));
                    return;
                }
                var sideAction = node.getAttribute('data-custom-side-action');
                if (handleCustomSideAction(sideAction, node.getAttribute('data-side'))) {
                    return;
                }
                var side = node.getAttribute('data-custom-side');
                if (side === 'blue' || side === 'red') {
                    if ((S._customEditor && S._customEditor.mode === 'pve') && side === 'blue') {
                        S._customSelectedSide = 'red';
                        renderCustomEditor();
                        return;
                    }
                    S._customSelectedSide = side;
                    renderCustomEditor();
                    return;
                }
                var paramMode = node.getAttribute('data-custom-param-mode');
                if (paramMode === 'json' || paramMode === 'xml') {
                    setCustomParamEditorMode(paramMode);
                    return;
                }
                var paramAction = node.getAttribute('data-custom-param-action');
                if (paramAction === 'back') {
                    leaveCustomParamEditorDiscardingDraft();
                    return;
                }
                if (paramAction === 'apply') {
                    applyCustomParamDraft(false);
                    return;
                }
                if (paramAction === 'save-back') {
                    applyCustomParamDraft(true);
                    return;
                }
                if (paramAction === 'clear') {
                    clearCustomParamDraft();
                    return;
                }
                var filter = node.getAttribute('data-custom-unit-filter');
                if (filter === 'all' || filter === 'hostile' || filter === 'nonhostile') {
                    var editor = ensureCustomEditorState();
                    editor.filter = filter;
                    resetCustomUnitBrowserWindow(editor);
                    renderCustomUnitBrowser();
                    return;
                }
                var factionKey = node.getAttribute('data-custom-toggle-faction');
                if (factionKey) {
                    toggleCustomUnitFaction(factionKey);
                    return;
                }
                var clearSide = node.getAttribute('data-custom-clear-side');
                if (clearSide === 'blue' || clearSide === 'red') {
                    clearCustomRosterSide(clearSide);
                    return;
                }
                var adjustCount = node.getAttribute('data-custom-adjust-count');
                if (adjustCount) {
                    adjustCustomRosterCount(node.getAttribute('data-side'), Number(node.getAttribute('data-index')), Number(adjustCount));
                    return;
                }
                var addId = node.getAttribute('data-custom-add-unit');
                if (addId) {
                    addCustomUnitToSide(Number(addId), S._customSelectedSide, node.getAttribute('data-custom-preset-id'));
                    return;
                }
                if (node.hasAttribute('data-custom-edit-params')) {
                    showCustomParamEditorPage(node.getAttribute('data-side'), Number(node.getAttribute('data-index')));
                    return;
                }
                if (node.hasAttribute('data-custom-remove')) {
                    removeCustomRosterEntry(node.getAttribute('data-side'), Number(node.getAttribute('data-index')));
                    return;
                }
                var confirmAction = node.getAttribute('data-custom-confirm-action');
                if (confirmAction === 'cancel') {
                    S._customConfirmOpen = false;
                    refreshCustomMatchCard();
                    return;
                }
                // confirmAction === 'start' 不在此路由：P3 起由确认条共享 CommitBar 的
                // onCommit 单一持有（disabled/busy 由组件原生吞掉，不再走委派）
            }
            node = node.parentNode;
        }
    }

    function onCustomWorkbenchChange(e) {
        var input = e.target;
        if (!input || !input.getAttribute) return;
        if (input.hasAttribute('data-custom-battle-field')) {
            applyCustomBattleInput(input, true);
            return;
        }
        var field = input.getAttribute('data-custom-roster-input');
        if (field !== 'level' && field !== 'count') return;
        updateCustomRosterEntry(input.getAttribute('data-side'), Number(input.getAttribute('data-index')), field, Number(input.value));
    }

    function applyCustomBattleInput(input, captureUndo) {
        var field = input.getAttribute('data-custom-battle-field');
        var value = Number(input.value);
        if (field === 'timeoutSeconds') value = value * CUSTOM_TIMEOUT_FPS;
        setCustomBattleValue(field === 'timeoutSeconds' ? 'timeoutFrames' : field, value, captureUndo);
    }

    function setCustomBattleValue(field, value, captureUndo) {
        var editor = ensureCustomEditorState();
        sanitizeCustomBattleParams(editor);
        var next = Number(value);
        if (field === 'timeoutFrames') next = ArenaCore.clampInt(next, 30 * CUSTOM_TIMEOUT_FPS, 600 * CUSTOM_TIMEOUT_FPS);
        else if (field === 'spawnDistance') next = ArenaCore.clampInt(next, ArenaCustomMatchCode.MIN_SPAWN_DISTANCE, ArenaCustomMatchCode.MAX_SPAWN_DISTANCE);
        else if (field === 'formationSpacing') next = ArenaCore.clampInt(next, ArenaCustomMatchCode.MIN_FORMATION_SPACING, ArenaCustomMatchCode.MAX_FORMATION_SPACING);
        else return;
        if (editor[field] === next) {
            renderCustomBattleParams();
            return;
        }
        if (captureUndo) captureCustomUndo('调整战场参数');
        editor[field] = next;
        syncCustomCodeFromEditor();
        renderCustomBattleParams();
    }

    function setCustomFormationValue(side, value) {
        var editor = ensureCustomEditorState();
        var field = side === 'red' ? 'redFormation' : 'blueFormation';
        var next = normalizeCustomFormation(value);
        if (editor[field] === next) return;
        captureCustomUndo('调整阵型');
        editor[field] = next;
        syncCustomCodeFromEditor();
        renderCustomBattleParams();
    }

    function addCustomUnitToSide(unitId, side, presetId) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        var unit = getCustomUnitById(unitId);
        var preset = findCustomUnitParameterPreset(presetId);
        var parameters = preset && customHasParameters(preset.parameters) ? cloneCustomParameters(preset.parameters) : null;
        var level = preset && Number(preset.defaultLevel) > 0
            ? Number(preset.defaultLevel)
            : (Number(unit.level) > 0 ? Number(unit.level) : 1);
        for (var i = 0; i < roster.length; i++) {
            if (roster[i].id === unitId && roster[i].level === level && customParametersEqual(roster[i].parameters, parameters)) {
                captureCustomUndo(customSideLabel(side) + '添加单位');
                roster[i].count++;
                syncCustomCodeFromEditor();
                return;
            }
        }
        captureCustomUndo(customSideLabel(side) + '添加单位');
        var entry = { id: unitId, type: '兵种' + unitId, level: level, count: 1 };
        if (parameters) {
            entry.parameters = parameters;
            entry.presetId = preset.id;
            entry.presetLabel = preset.summary || summarizeCustomParameters(parameters);
        }
        roster.push(entry);
        syncCustomCodeFromEditor();
    }

    function removeCustomRosterEntry(side, index) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (index >= 0 && index < roster.length) {
            captureCustomUndo(customSideLabel(side) + '移除单位');
            roster.splice(index, 1);
            syncCustomCodeFromEditor();
        }
    }

    function clearCustomRosterSide(side) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (!roster || !roster.length) return;
        captureCustomUndo(customSideLabel(side) + '清空阵容');
        if (side === 'red') editor.red = [];
        else editor.blue = [];
        syncCustomCodeFromEditor();
    }

    function adjustCustomRosterCount(side, index, delta) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (index < 0 || index >= roster.length) return;
        var next = (Number(roster[index].count) || 1) + delta;
        if (next < 1) next = 1;
        if (next > 20) next = 20;
        if (next === roster[index].count) return;
        captureCustomUndo(customSideLabel(side) + '调整数量');
        roster[index].count = next;
        syncCustomCodeFromEditor();
    }

    function updateCustomRosterEntry(side, index, field, value) {
        var editor = ensureCustomEditorState();
        var roster = side === 'red' ? editor.red : editor.blue;
        if (index < 0 || index >= roster.length) return;
        if (isNaN(value) || value < 1) value = 1;
        value = Math.floor(value);
        if (field === 'count' && value > 20) value = 20;
        if (roster[index][field] === value) return;
        captureCustomUndo(customSideLabel(side) + (field === 'level' ? '调整等级' : '调整数量'));
        roster[index][field] = value;
        // 数字输入 change 后也要刷新隐藏入口卡，否则点“完成”回 grid 会看到旧摘要。
        syncCustomCodeFromEditor();
    }

    function setCustomRosterParametersValue(side, index, value) {
        var editor = ensureCustomEditorState();
        var roster = resolveCustomSide(side) === 'red' ? editor.red : editor.blue;
        if (index < 0 || index >= roster.length) return false;
        if (customParametersEqual(roster[index].parameters, value)) return true;
        captureCustomUndo(customSideLabel(side) + '应用参数');
        if (customHasParameters(value)) {
            roster[index].parameters = cloneCustomParameters(value);
            delete roster[index].presetId;
            roster[index].presetLabel = summarizeCustomParameters(roster[index].parameters);
        } else {
            delete roster[index].parameters;
            delete roster[index].presetId;
            delete roster[index].presetLabel;
        }
        syncCustomCodeFromEditor();
        return true;
    }

    function copyCustomMatchCode() {
        ensureCustomMatchState();
        if (S._customMatch.parsed) S._customMatch.code = S._customMatch.parsed.canonical;
        var text = S._customMatch.code || '';
        var done = function() { ArenaCore.showToast('赛程代码已复制'); };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done, function() { ArenaCore.showToast('复制失败，请手动复制'); });
        } else {
            ArenaCore.showToast('当前环境不支持自动复制');
        }
        var input = S._el ? S._el.querySelector('#arena-custom-code-input') : null;
        if (input) input.value = text;
    }

    function onCustomGenerate() {
        if (S._busy || ArenaResult.customRunActive()) return;
        ensureCustomMatchState();
        parseCustomMatchCode();
        refreshCustomMatchCard();
        if (!S._customMatch.parsed) {
            ArenaCore.showToast('赛程代码无效');
            return;
        }
        S._customConfirmOpen = true;
        refreshCustomMatchCard();
    }

    function startCustomMatch() {
        if (S._busy || ArenaResult.customRunActive()) return;
        ensureCustomMatchState();
        // P3：提交触发的重解析只是再规范化同一赛程码（内容未变），不应把确认条当作
        // 「代码已编辑」失效——保留确认层，共享 CommitBar 的 busy/失败投影才可见、可重试
        var keepConfirmOpen = S._customConfirmOpen;
        parseCustomMatchCode();
        if (keepConfirmOpen && S._customMatch.parsed) S._customConfirmOpen = true;
        refreshCustomMatchCard();
        if (!S._customMatch.parsed) {
            ArenaCore.showToast('赛程代码无效');
            return;
        }
        if (S._customMatch.parsed.mode === 'pve') {
            startCustomPveMatch(S._customMatch.parsed);
            return;
        }
        S._busy = true;
        refreshCustomMatchCard();
        ArenaPreviewAuthority.sendCustomRequest('custom_start', {
            matchCode: S._customMatch.parsed.canonical,
            calibrationCase: S._customMatch.parsed.calibrationCase,
            venueFeeEstimate: S._customMatch.parsed.venueFeeEstimate
        }, function(data) {
            S._busy = false;
            ArenaResult.applyCustomRunStatus(data);
            if (data.success === false) {
                ArenaCore.showToast(data.message || data.error || '委托启动失败');
                setCustomConfirmError(data.message || data.error || '委托启动失败');
                return;
            }
            ArenaCore.showToast('定制赛委托已开始');
            if (data.closePanel) {
                ArenaShell.requestClose({ dismissReturnStack: true });
                return;
            }
            ArenaResult.scheduleCustomStatusPoll();
        });
    }

    function startCustomPveMatch(parsed) {
        var payload = parsed && parsed.enterPayload;
        if (!payload || !payload.roster || !payload.roster.length) {
            ArenaCore.showToast('怪物配置为空');
            return;
        }
        S._busy = true;
        refreshCustomMatchCard();

        var reqId = 'arena_custom_pve_' + (++S._reqSeq) + '_' + S._session;
        S._pendingReq[reqId] = function(data) {
            S._busy = false;
            refreshCustomMatchCard();
            if (!data.success) {
                ArenaCore.showToast(data.error || '挑战发起失败');
                setCustomConfirmError(data.error || '挑战发起失败');
                return;
            }
            ArenaCore.showToast('玩家对怪物挑战已开始');
            if (data.closePanel) ArenaShell.requestClose({ dismissReturnStack: true });
        };

        var msg = {};
        for (var key in payload) {
            if (Object.prototype.hasOwnProperty.call(payload, key)) msg[key] = payload[key];
        }
        msg.type = 'panel';
        msg.panel = 'arena';
        msg.cmd = 'enter';
        msg.callId = reqId;
        msg.difficulty = S._initDifficulty || msg.difficulty || '';
        msg.matchCode = parsed.canonical;
        Bridge.send(msg);
    }

    function onCustomAbort() {
        if (S._busy || !ArenaResult.customRunActive()) return;
        S._busy = true;
        refreshCustomMatchCard();
        ArenaPreviewAuthority.sendCustomRequest('custom_abort', {
            batchId: S._customRun.batchId || ''
        }, function(data) {
            S._busy = false;
            ArenaResult.applyCustomRunStatus(data);
            ArenaCore.showToast(data.success === false ? (data.message || data.error || '中止失败') : '已请求中止');
            if (ArenaResult.customRunActive()) ArenaResult.scheduleCustomStatusPoll();
        });
    }

    // 导出：仅被其它 arena 模块 / facade 引用的名字
    window.ArenaCustomEditor = {
        buildCustomEditorViewHtml: buildCustomEditorViewHtml,
        ensureCustomMatchState: ensureCustomMatchState,
        getCustomSavedRosters: getCustomSavedRosters,
        parseCustomMatchCode: parseCustomMatchCode,
        ensureCustomEditorState: ensureCustomEditorState,
        closeCustomSelectMenus: closeCustomSelectMenus,
        onCustomSelectKeydown: onCustomSelectKeydown,
        cloneCustomParameters: cloneCustomParameters,
        customHasParameters: customHasParameters,
        refreshCustomMatchCard: refreshCustomMatchCard,
        renderCustomEditor: renderCustomEditor,
        showCustomEditorConfigPage: showCustomEditorConfigPage,
        leaveCustomParamEditorDiscardingDraft: leaveCustomParamEditorDiscardingDraft,
        renderCustomUnitBrowser: renderCustomUnitBrowser,
        summarizeCustomRoster: summarizeCustomRoster,
        onCustomUnitBrowserScroll: onCustomUnitBrowserScroll,
        onCustomEditorInput: onCustomEditorInput,
        onCustomWorkbenchClick: onCustomWorkbenchClick,
        onCustomWorkbenchChange: onCustomWorkbenchChange,
        copyCustomMatchCode: copyCustomMatchCode,
        onCustomGenerate: onCustomGenerate,
        startCustomMatch: startCustomMatch,
        onCustomAbort: onCustomAbort
    };
})();
