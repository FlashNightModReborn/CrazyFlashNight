/**
 * arena-panel.js — 竞技场面板 P4 工程拆分 · 薄 facade。
 *
 * 职责只剩：Panels.register 入口（装配六模块的实现函数）+ QA 调试接口（window.ArenaPanel）。
 * 实现已按职责拆入 modules/arena/：core（状态+工具）→ shell（壳/生命周期）→ challenge-browser
 * （挑战目录/决策/commit）→ preview-authority（AS2 preview 通路+本地采样）→ custom-editor
 * （定制赛编辑器）→ result（结算页）。行为 / 协议 payload / DOM id·class 契约与原单文件一致。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.ArenaCore) {
        throw new Error('arena-panel.js 需要先加载 arena/arena-core.js（P4 拆分模块；顺序见 panels-lazy-registry arena 注册项）');
    }
    if (typeof window === 'undefined' || !window.ArenaShell) {
        throw new Error('arena-panel.js 需要先加载 arena/arena-shell.js（P4 拆分模块；顺序见 panels-lazy-registry arena 注册项）');
    }
    if (typeof window === 'undefined' || !window.ArenaChallengeBrowser) {
        throw new Error('arena-panel.js 需要先加载 arena/arena-challenge-browser.js（P4 拆分模块；顺序见 panels-lazy-registry arena 注册项）');
    }
    if (typeof window === 'undefined' || !window.ArenaPreviewAuthority) {
        throw new Error('arena-panel.js 需要先加载 arena/arena-preview-authority.js（P4 拆分模块；顺序见 panels-lazy-registry arena 注册项）');
    }
    if (typeof window === 'undefined' || !window.ArenaCustomEditor) {
        throw new Error('arena-panel.js 需要先加载 arena/arena-custom-editor.js（P4 拆分模块；顺序见 panels-lazy-registry arena 注册项）');
    }
    if (typeof window === 'undefined' || !window.ArenaResult) {
        throw new Error('arena-panel.js 需要先加载 arena/arena-result.js（P4 拆分模块；顺序见 panels-lazy-registry arena 注册项）');
    }

    var S = ArenaCore.state;


    // ════════════════════════════════════════════════════════════════════════════
    // Panel 注册
    // ════════════════════════════════════════════════════════════════════════════
    Panels.register('arena', {
        create: ArenaShell.createDOM,
        onOpen: ArenaShell.onOpen,
        onRequestClose: ArenaShell.onArenaRequestClose,
        onClose: ArenaShell.onClose
    });


    // ════════════════════════════════════════════════════════════════════════════
    // 调试接口（harness / QA 用）
    // ════════════════════════════════════════════════════════════════════════════
    function _debugGetState() {
        return {
            session: S._session,
            busy: S._busy,
            snapshot: S._snapshot,
            selectedCardIdx: S._selectedCardIdx,
            previewOpponents: S._previewOpponents,
            activeMode: S._activeMode,
            knownEnemyCount: S._knownEnemyCount,
            pendingCount: Object.keys(S._pendingReq).length,
            previewCacheCount: Object.keys(S._previewCache).length,
            previewPendingCount: Object.keys(S._previewPending).length,
            previewErrorCount: Object.keys(S._previewError).length,
            cardKind: S._cardKind,
            monsterSquad: S._monsterSquad,
            customMatch: S._customMatch,
            customEditor: S._customEditor,
            customSelectedSide: S._customSelectedSide,
            customEditorPage: S._customEditorPage,
            customParamEditor: S._customParamEditor,
            customSavedRosters: ArenaCustomEditor.getCustomSavedRosters().slice(),
            customConfirmOpen: S._customConfirmOpen,
            customRun: S._customRun,
            customResult: S._customResult,
            customParamPageActive: !!(S._customParamPage && S._customParamPage.isActive()),
            customEditorScopeActive: !!(S._customEditorScope && S._customEditorScope.isActive()),
            customResultScopeActive: !!(S._customResultScope && S._customResultScope.isActive())
        };
    }


    // 暴露给 harness QA
    if (typeof window !== 'undefined') {
        window.ArenaPanel = {
            getState: _debugGetState,
            getCards: function() { return S._activeCards.slice(); },
            // 测试注入：模拟 AS2 snapshot 的 killStats.byType spritename 列表。
            setKnownEnemies: function(list) {
                ArenaPreviewAuthority.setKnownEnemies(list);
                ArenaShell.refreshModeTabs();
            },
            // 测试/截图：切到堕落模式（需 rosters 已载）。返回切后卡片数。
            switchMode: function(mode) {
                if (!ArenaShell.modeAvailable(mode)) return 0;
                ArenaChallengeBrowser.rebuildForMode(mode);
                if (S._snapshot) ArenaPreviewAuthority.batchRequestPreview();
                return S._activeCards.length;
            }
        };
    }
})();
