/**
 * arena-result.js — 竞技场面板 P4 工程拆分 · 定制赛结算页：战果渲染 / 运行状态轮询 / 回开路径。
 *
 * 本文件由 modules/arena-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议 payload /
 * DOM id·class 契约 / QA 断言不变）。转换规则：原顶层 `var _x` 状态 → ArenaCore.state._x（本文件内
 * 以 `S._x` 访问）；跨模块函数/常量引用 → `模块全局.名字`。加载顺序由 panels-lazy-registry 的
 * arena 注册项与 arena/dev/harness.html script 区固定（与本文件守卫一致）。
 * 依赖守卫：arena/arena-core.js。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.ArenaCore) {
        throw new Error('arena/arena-result.js 需要先加载 arena/arena-core.js（共享基座：状态容器 + 跨模块工具 + 共享常量）');
    }

    var S = ArenaCore.state; // 共享状态（原顶层 var _x）

    // 语义音效命令式入口（契约 §8）：结算页出现的权威结果音，页内按钮仍走 data-audio-cue
    function cue(name) {
        var A = window.BootstrapAudio;
        if (A && typeof A.cue === 'function') A.cue(name);
    }

    // 结算页出现 = 定制赛委托的权威结果落地（契约 §2）：
    // 委托失败 → rejected；已中止 / 无结果数据（战果不可知）→ unknown；
    // 正常产生结算 → success（观赛委托无玩家胜负面，平局 / 超时 / 无胜者同属已完成结算）。
    function cueCustomResultOutcome() {
        var state = (S._customRun && S._customRun.state) || (S._customResult && S._customResult.state) || '';
        var result = (S._customRun && S._customRun.lastResult) || (S._customResult && S._customResult.lastResult) || null;
        if (state === 'failed') { cue('rejected'); return; }
        if (!result || state === 'aborted' || state === 'abort_requested') { cue('unknown'); return; }
        cue('success');
    }


    function customRunActive() {
        return !!(S._customRun && (
            S._customRun.state === 'running' ||
            S._customRun.state === 'queued' ||
            S._customRun.state === 'abort_requested'
        ));
    }

    function customRunTerminal() {
        return !!(S._customRun && (
            S._customRun.state === 'completed' ||
            S._customRun.state === 'failed' ||
            S._customRun.state === 'aborted'
        ));
    }

    function customRunText() {
        if (!S._customRun) return '状态：未委托';
        var text = '状态：' + (S._customRun.state || 'unknown');
        if (S._customRun.completedRuns != null && S._customRun.totalRuns != null) {
            text += ' · ' + S._customRun.completedRuns + '/' + S._customRun.totalRuns;
        }
        if (S._customRun.lastResult && customRunTerminal()) text += ' · ' + customResultSummaryText(S._customRun.lastResult);
        if (S._customRun.batchId) text += ' · ' + S._customRun.batchId;
        if (S._customRun.resultPath && customRunTerminal()) text += ' · ' + S._customRun.resultPath;
        if (S._customRun.lastError) text += ' · ' + S._customRun.lastError;
        if (S._customRun.error && !S._customRun.success) text += ' · ' + S._customRun.error;
        return text;
    }

    function buildCustomRunStatusHtml(isPve) {
        if (isPve) {
            return buildCustomStatusChip('状态', '可挑战', 'ok') +
                buildCustomStatusChip('路径', '标准竞技场', '');
        }
        if (!S._customRun) return buildCustomStatusChip('状态', '未委托', '');
        var state = S._customRun.state || 'unknown';
        var html = buildCustomStatusChip('状态', customRunStateLabel(state), customRunTerminal() ? 'done' : 'active');
        if (S._customRun.completedRuns != null && S._customRun.totalRuns != null) {
            html += buildCustomStatusChip('进度', S._customRun.completedRuns + '/' + S._customRun.totalRuns, '');
        }
        if (S._customRun.lastResult && customRunTerminal()) {
            html += buildCustomStatusChip('结果', customResultSummaryText(S._customRun.lastResult).replace(/^结果：/, ''), 'done');
        }
        if (S._customRun.batchId) html += buildCustomStatusChip('批次', S._customRun.batchId, 'mono');
        if (S._customRun.resultPath && customRunTerminal()) html += buildCustomStatusChip('日志', S._customRun.resultPath, 'mono');
        if (S._customRun.lastError) html += buildCustomStatusChip('错误', S._customRun.lastError, 'error');
        if (S._customRun.error && !S._customRun.success) html += buildCustomStatusChip('错误', S._customRun.error, 'error');
        return html;
    }

    function customRunStateLabel(state) {
        if (state === 'queued') return '排队中';
        if (state === 'running') return '运行中';
        if (state === 'abort_requested') return '中止中';
        if (state === 'completed') return '已完成';
        if (state === 'failed') return '失败';
        if (state === 'aborted') return '已中止';
        if (state === 'idle') return '空闲';
        return state || '未知';
    }

    function buildCustomStatusChip(label, value, kind) {
        var cls = 'arena-custom-status-chip' + (kind ? ' arena-custom-status-chip-' + kind : '');
        return '<span class="' + cls + '"><em>' + ArenaCore.escapeHtml(label) + '</em><b>' + ArenaCore.escapeHtml(value == null ? '--' : value) + '</b></span>';
    }

    function customResultSummaryText(result) {
        if (!result) return '结果：未知';
        var winner = String(result.winner || 'none');
        var label = winner === 'blue' ? '蓝方胜'
            : winner === 'red' ? '红方胜'
            : winner === 'timeout' ? '超时'
            : winner === 'draw' ? '平局'
            : '无胜者';
        var status = result.status ? String(result.status) : '';
        var frames = result.frames != null ? String(result.frames) + '帧' : '';
        var parts = [label];
        if (status) parts.push(status);
        if (frames) parts.push(frames);
        return '结果：' + parts.join(' / ');
    }

    function renderCustomResultView() {
        if (!S._customResultViewEl) return;
        ArenaCustomEditor.ensureCustomMatchState();
        if (typeof ArenaCustomResultView === 'undefined' || !ArenaCustomResultView.render) {
            S._customResultViewEl.innerHTML =
                '<div class="arena-custom-result-panel">' +
                    '<div class="arena-custom-result-error">结算视图模块未加载</div>' +
                '</div>';
            return;
        }
        ArenaCustomResultView.render(S._customResultViewEl, {
            run: S._customRun || {},
            customResult: S._customResult,
            customMatch: S._customMatch,
            escapeHtml: ArenaCore.escapeHtml,
            summarizeCustomRoster: ArenaCustomEditor.summarizeCustomRoster
        });
        cueCustomResultOutcome();
    }

    function onCustomResultClick(e) {
        var node = e.target;
        while (node && node !== S._customResultViewEl) {
            if (node.getAttribute) {
                var action = node.getAttribute('data-custom-result-action');
                if (action === 'back') {
                    onCustomResultBack();
                    return;
                }
                if (action === 'copy') {
                    ArenaCustomEditor.copyCustomMatchCode();
                    return;
                }
                if (action === 'reopen') {
                    reopenCustomResultPanel();
                    return;
                }
            }
            node = node.parentNode;
        }
    }

    function onCustomResultBack() {
        if (S._busy) return;
        ArenaShell.requestCustomResultReturnBase();
    }

    function reopenCustomResultPanel() {
        if (S._busy) return;
        ArenaCustomEditor.ensureCustomMatchState();
        if (S._customMatch && S._customMatch.parsed) S._customMatch.code = S._customMatch.parsed.canonical;
        S._customRun = null;
        S._customResult = null;
        // 再赛一场已回到编辑态，后续 ESC/× 是普通取消，不再请求 AS2 返回基地。
        S._customResultReturnBaseRequired = false;
        S._customConfirmOpen = false;
        S._customEditorPage = 'config';
        S._customParamEditor = null;
        S._customUndo = null;
        clearCustomPoll();
        ArenaChallengeBrowser.rebuildForMode('custom');
        ArenaCore.showToast('已回到定制赛面板，可再次确认开赛');
    }

    function applyCustomRunStatus(data) {
        S._customRun = {
            success: data.success !== false,
            state: data.state || 'unknown',
            note: data.note || '',
            batchId: data.batchId || (S._customRun && S._customRun.batchId) || '',
            manifestHash: data.manifestHash || '',
            manifestPath: data.manifestPath || '',
            frozenManifestPath: data.frozenManifestPath || '',
            resultPath: data.resultPath || '',
            totalRuns: data.totalRuns,
            completedRuns: data.completedRuns,
            currentCaseId: data.currentCaseId || '',
            currentRunId: data.currentRunId || '',
            lastError: data.lastError || data.message || '',
            error: data.error || '',
            lastResult: data.lastResult || (S._customRun && S._customRun.lastResult) || null,
            reopened: data.reopened || (S._customRun && S._customRun.reopened) || false
        };
        ArenaCustomEditor.refreshCustomMatchCard();
    }

    function normalizeCustomResultInitData(initData) {
        if (!initData || initData.mode !== 'custom_result') return null;
        return {
            mode: 'custom_result',
            source: initData.source || 'arena_custom_match_result',
            matchCode: initData.matchCode || '',
            state: initData.state || 'completed',
            batchId: initData.batchId || '',
            resultPath: initData.resultPath || '',
            manifestPath: initData.manifestPath || '',
            frozenManifestPath: initData.frozenManifestPath || '',
            totalRuns: initData.totalRuns,
            completedRuns: initData.completedRuns,
            lastError: initData.lastError || '',
            lastResult: initData.lastResult || null
        };
    }

    function buildCustomRunFromResult(result) {
        return {
            success: result.state !== 'failed',
            state: result.state || 'completed',
            note: 'settled',
            batchId: result.batchId || '',
            manifestHash: '',
            manifestPath: result.manifestPath || '',
            frozenManifestPath: result.frozenManifestPath || '',
            resultPath: result.resultPath || '',
            totalRuns: result.totalRuns,
            completedRuns: result.completedRuns,
            currentCaseId: '',
            currentRunId: '',
            lastError: result.lastError || '',
            error: '',
            lastResult: result.lastResult || null,
            reopened: true
        };
    }

    function clearCustomPoll() {
        S._customPollTimer = ArenaCustomPolling.clear(S._customPollTimer);
    }

    function scheduleCustomStatusPoll() {
        S._customPollTimer = ArenaCustomPolling.schedule(S._customPollTimer, {
            active: S._activeMode === 'custom' && customRunActive(),
            delayMs: 1000,
            callback: function() {
            S._customPollTimer = 0;
            requestCustomStatus();
            }
        });
    }

    function requestCustomStatus() {
        if (S._activeMode !== 'custom' || !S._customRun) return;
        ArenaPreviewAuthority.sendCustomRequest('custom_status', { batchId: S._customRun.batchId || '' }, function(data) {
            applyCustomRunStatus(data);
            if (customRunActive()) scheduleCustomStatusPoll();
        });
    }

    // 导出：仅被其它 arena 模块 / facade 引用的名字
    window.ArenaResult = {
        customRunActive: customRunActive,
        buildCustomRunStatusHtml: buildCustomRunStatusHtml,
        renderCustomResultView: renderCustomResultView,
        onCustomResultClick: onCustomResultClick,
        onCustomResultBack: onCustomResultBack,
        applyCustomRunStatus: applyCustomRunStatus,
        normalizeCustomResultInitData: normalizeCustomResultInitData,
        buildCustomRunFromResult: buildCustomRunFromResult,
        clearCustomPoll: clearCustomPoll,
        scheduleCustomStatusPoll: scheduleCustomStatusPoll
    };
})();
