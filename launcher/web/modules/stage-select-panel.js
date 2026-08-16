/**
 * stage-select-panel.js — 选关面板 P4-a 工程拆分 · 薄 facade。
 *
 * 职责只剩：Panels.register('stage-select') 入口（装配五模块的实现函数）+ QA 调试接口
 * （StageSelectPanel._debug*，签名与原单文件一致）。实现已按四层职责拆入
 * modules/stage-select/：core（共享状态容器 + 跨模块工具）→ view-model（纯数据层：
 * frame 路由 / fixture+snapshot 状态合并 / 选中态 / 挑战模式 / 任务统计 / 导航打分，
 * 无 DOM、无 document/window，P5 三维 renderer 插座）→ renderer（空间 DOM 舞台 /
 * 帧菜单 / 缩放 / 生命周期编排）→ inspector（pinned 决策检查器 + 难度提交 intent）→
 * bridge（请求信封 / pending 表 / 回包守卫）。行为 / 协议 payload / DOM id·class 契约
 * 与原单文件一致。加载顺序见 panels-lazy-registry 的 stage-select 注册项与
 * stage-select/dev/harness.html script 区（与本文件守卫一致）。
 */
var StageSelectPanel = (function() {
    'use strict';

    if (typeof window === 'undefined' || !window.StageSelectCore) {
        throw new Error('stage-select-panel.js 需要先加载 stage-select/stage-select-core.js（P4-a 拆分模块；顺序见 panels-lazy-registry stage-select 注册项）');
    }
    if (typeof window === 'undefined' || !window.StageSelectViewModel) {
        throw new Error('stage-select-panel.js 需要先加载 stage-select/stage-select-view-model.js（P4-a 拆分模块；顺序见 panels-lazy-registry stage-select 注册项）');
    }
    if (typeof window === 'undefined' || !window.StageSelectRenderer) {
        throw new Error('stage-select-panel.js 需要先加载 stage-select/stage-select-renderer.js（P4-a 拆分模块；顺序见 panels-lazy-registry stage-select 注册项）');
    }
    if (typeof window === 'undefined' || !window.StageSelectInspector) {
        throw new Error('stage-select-panel.js 需要先加载 stage-select/stage-select-inspector.js（P4-a 拆分模块；顺序见 panels-lazy-registry stage-select 注册项）');
    }
    if (typeof window === 'undefined' || !window.StageSelectBridge) {
        throw new Error('stage-select-panel.js 需要先加载 stage-select/stage-select-bridge.js（P4-a 拆分模块；顺序见 panels-lazy-registry stage-select 注册项）');
    }

    var S = StageSelectCore.state; // 共享状态（原顶层 var _x）

    Panels.register('stage-select', {
        create: StageSelectRenderer.createDOM,
        onOpen: StageSelectRenderer.onOpen,
        onRebind: StageSelectRenderer.onRebind,
        onRequestClose: StageSelectRenderer.requestClose,
        onClose: StageSelectRenderer.onClose
    });

    // 调试接口（harness / qa-suite / 截图工具消费，签名与原单文件一致）
    function _debugGetState() {
        return {
            isOpen: Panels.getActive && Panels.getActive() === 'stage-select',
            frameLabel: S._currentFrameLabel,
            fixture: S._fixtureName,
            mode: S._mode,
            returnFrameLabel: S._returnFrameLabel,
            frameMenuOpen: S._frameMenuOpen,
            challenge: StageSelectViewModel.isChallengeMode(),
            stageButtonCount: S._buttonLayerEl ? S._buttonLayerEl.querySelectorAll('.stage-select-stage-button').length : 0,
            navButtonCount: S._navLayerEl ? S._navLayerEl.querySelectorAll('.stage-select-nav-button').length : 0,
            layoutWatcherActive: !!S._scaleHandle,
            runtimeSnapshot: S._runtimeSnapshot,
            taskTargets: StageSelectViewModel.getTaskTargets(),
            pendingCount: Object.keys(S._pendingReq).length,
            panelInstanceId: S._panelInstanceId,
            sessionGeneration: S._session,
            lastAppliedStateRevision: S._lastAppliedStateRevision,
            droppedRespCount: S._droppedRespCount,
            busyStageName: S._busyStageName,
            lastError: S._lastError,
            lastDifficultyClick: S._lastDifficultyClick,
            selectedStageId: S._selectedStageId,
            inspectorOpen: StageSelectInspector.isInspectorOpen(),
            openCardStageId: StageSelectViewModel.computeOpenCardId()
        };
    }

    return {
        _debugGetState: _debugGetState,
        _debugSetFrame: StageSelectRenderer.setFrame,
        _debugApplySnapshot: StageSelectRenderer.applyRuntimeSnapshot,
        _debugRequestSnapshot: StageSelectBridge.requestSnapshot,
        _debugSetFixture: function(name) {
            StageSelectRenderer.applyFixture(name);
            if (S._fixtureSelectEl) S._fixtureSelectEl.value = S._fixtureName;
            StageSelectRenderer.renderCurrentFrame();
        }
    };
})();
