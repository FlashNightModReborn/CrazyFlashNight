/**
 * stage-select/stage-select-core.js — 选关面板 P4-a 工程拆分 · 共享基座：状态容器 + 跨模块工具。
 *
 * 本文件由 modules/stage-select-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议 payload /
 * DOM id·class 契约 / QA 断言不变）。转换规则：原顶层 `var _x` 状态 → StageSelectCore.state._x
 * （各模块内以 `S._x` 访问）；跨模块函数引用 → `模块全局.名字`，解析于调用时。加载顺序由
 * panels-lazy-registry 的 stage-select 注册项与 stage-select/dev/harness.html script 区固定。
 * 依赖守卫：本模块只依赖浏览器环境，不守卫其它 stage-select 模块（core 最先加载）。
 * 注意：logDev / clearError 于调用时解析 StageSelectViewModel.isRuntimeMode（mode 状态归
 * ViewModel 所有，core 不回持其引用；调用必然发生在全部模块加载完成之后）。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined') throw new Error('stage-select/stage-select-core.js 需要浏览器 window 环境');

    // ── 状态容器（原 stage-select-panel.js 顶层 `var _x` 全量平移，初始化值逐字保留）──
    var state = {};

    state.DESIGN_W = 1024;
    state.DESIGN_H = 576;
    state._el = undefined;
    state._shellEl = undefined;
    state._stageEl = undefined;
    state._backgroundEl = undefined;
    state._buttonLayerEl = undefined;
    state._cardLayerEl = undefined;
    state._navLayerEl = undefined;
    state._inspectorEl = undefined;
    state._inspectorPreviewEl = undefined;
    state._inspectorNameEl = undefined;
    state._inspectorTypeEl = undefined;
    state._inspectorLockEl = undefined;
    state._inspectorTaskEl = undefined;
    state._inspectorDetailEl = undefined;
    state._inspectorDiffEl = undefined;
    state._inspectorCloseEl = undefined;
    state._tabsEl = undefined;
    state._summaryEl = undefined;
    state._badgeEl = undefined;
    state._logEl = undefined;
    state._fixtureSelectEl = undefined;
    state._frameToggleEl = undefined;
    state._frameToggleLabelEl = undefined;
    state._frameToggleCounterEl = undefined;
    state._frameToggleTaskBadgeEl = undefined;
    state._currentFrameLabel = '';
    state._returnFrameLabel = '';
    state._fixtureName = 'mixed';
    state._fixture = null;
    state._lastDifficultyClick = null;
    state._runtimeSnapshot = null;
    state._pendingReq = {};
    state._reqSeq = 0;
    state._session = 0;
    // P3 会话守卫：_panelInstanceId = Host 权威实例（BuildPanelOpenPayload 注入 initData，
    // dev/harness 无 Host 时为空串 = 未绑定）；_lastAppliedStateRevision = snapshot 单调水位。
    state._panelInstanceId = '';
    state._lastAppliedStateRevision = 0;
    state._droppedRespCount = 0;
    state._mode = 'dev';
    state._busyStageName = '';
    state._lastError = '';
    state._frameMenuOpen = false;
    // P2：持久选中态（pinned 决策检查器触发器）+ hover 卡/焦点/roving tabindex 跟踪。
    // 选中键 = stageButton.id（全局唯一，audit 强制），跨 snapshot/busy/error 全量重建按 id 恢复。
    state._selectedStageId = '';
    state._hoverStageId = '';      // 指针悬停的关卡节点
    state._cardHoverStageId = '';  // 指针悬停的 hover 卡本体（卡已迁至独立卡片层）
    state._focusStageId = '';      // 焦点所在的关卡节点
    state._tabbableStageId = '';   // roving tabindex：节点簇中唯一 tabIndex=0 的节点
    // 打磨批二轮：自有键盘模态位（what-input 式 sticky 标记）——节点焦点环不再信 :focus-visible
    // 启发式（WebView2 宿主的 MoveFocus(Programmatic)/嵌入焦点链会让鼠标点击也命中 :focus-visible），
    // 改由 capture 阶段 keydown→true / pointerdown→false 维护，节点 focusin 按本位挂 .is-kb-focus。
    state._lastInputKeyboard = false;
    state._scaleHandle = null;   // PanelScale 句柄（共享缩放 primitive；onOpen attach / onClose detach）
    state._timers = [];          // 统一登记的 setTimeout，onClose 全清（幂等销毁）

    var S = state;

    // 语义音效命令式入口（契约 §8）：仅本地可拒绝 / 核心提交动作使用，静态元素走 data-audio-cue
    function cue(name) {
        var A = window.BootstrapAudio;
        if (A && typeof A.cue === 'function') A.cue(name);
    }

    function escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function escapeAttr(text) {
        return escapeHtml(text).replace(/'/g, '&#39;');
    }

    function selectorQuote(value) {
        return String(value || '').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    }

    function isWithin(target, parent) {
        if (!target || !parent) return false;
        var node = target;
        while (node) {
            if (node === parent) return true;
            node = node.parentNode;
        }
        return false;
    }

    function logDev(message) {
        if (S._logEl && !StageSelectViewModel.isRuntimeMode()) {
            S._logEl.classList.remove('is-error');
            S._logEl.textContent = message;
        }
        if (window.console && console.log) console.log('[stage-select] ' + message);
    }

    function showError(error) {
        S._lastError = error || 'unknown_error';
        if (S._logEl) {
            S._logEl.classList.add('is-error');
            S._logEl.textContent = S._lastError === 'pending_stage_settlement'
                ? '请先领取或放弃上一关尚未处理的奖励。'
                : S._lastError;
        }
    }

    function clearError() {
        if (!S._lastError && (!S._logEl || !S._logEl.classList.contains('is-error'))) return;
        S._lastError = '';
        if (S._logEl) {
            S._logEl.classList.remove('is-error');
            if (StageSelectViewModel.isRuntimeMode()) S._logEl.textContent = '';
        }
    }

    function scheduleTimer(fn, ms) {
        var id = setTimeout(function() {
            var idx = S._timers.indexOf(id);
            if (idx >= 0) S._timers.splice(idx, 1);
            fn();
        }, ms);
        S._timers.push(id);
        return id;
    }

    function clearTimers() {
        for (var i = 0; i < S._timers.length; i += 1) clearTimeout(S._timers[i]);
        S._timers = [];
    }

    function finiteNumber(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function numericCss(value, fallback) {
        return finiteNumber(value, fallback) + 'px';
    }

    function weighChars(s) {
        var w = 0;
        for (var i = 0; i < s.length; i += 1) {
            w += s.charCodeAt(i) < 128 ? 0.58 : 1;
        }
        return w;
    }

    function cleanStageText(text) {
        return String(text || '')
            .replace(/\r\n/g, '\n')
            .replace(/[ \t]+\n/g, '\n')
            .replace(/\n{3,}/g, '\n\n')
            .replace(/^[\s　]+|[\s　]+$/g, '');
    }

    function flashHtmlToText(text) {
        var value = String(text || '');
        if (!value) return '';
        value = decodeHtmlEntities(value);
        value = value.replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n');
        if (typeof document !== 'undefined' && document.createElement) {
            var div = document.createElement('div');
            div.innerHTML = value;
            return cleanStageText(div.textContent || div.innerText || '');
        }
        return cleanStageText(value.replace(/<[^>]+>/g, ''));
    }

    function decodeHtmlEntities(text) {
        var value = String(text || '');
        if (typeof document === 'undefined' || !document.createElement) {
            return value
                .replace(/&amp;/g, '&')
                .replace(/&lt;/g, '<')
                .replace(/&gt;/g, '>')
                .replace(/&quot;/g, '"')
                .replace(/&#39;/g, "'");
        }
        var textarea = document.createElement('textarea');
        for (var i = 0; i < 2; i++) {
            textarea.innerHTML = value;
            var decoded = textarea.value;
            if (decoded === value) break;
            value = decoded;
        }
        return value;
    }

    function buildStageDetail(button, state) {
        var parts = [];
        var detail = flashHtmlToText(state.detail || button.detail || '');
        var limit = flashHtmlToText(state.limitDetail || '');
        var material = flashHtmlToText(state.materialDetail || '');
        if (detail) parts.push(detail);
        if (limit) parts.push(limit);
        if (!parts.length && material) parts.push(material);
        if (!parts.length) parts.push('暂无资料');
        var text = parts.join('\n');
        return {
            html: escapeHtml(text).replace(/\r?\n/g, '<br>'),
            rawText: text
        };
    }

    function resolveAssetUrl(url) {
        var value = String(url || '');
        if (!value) return value;
        if (/^(?:https?:|file:|data:|\/)/i.test(value)) return value;
        if (value.indexOf('assets/') === 0 && window.location && window.location.pathname.indexOf('/modules/stage-select/dev/') >= 0) {
            return '../../../' + value;
        }
        return value;
    }

    // 导出：状态容器 + 被其它 stage-select 模块引用的工具
    window.StageSelectCore = {
        state: state,
        cue: cue,
        escapeHtml: escapeHtml,
        escapeAttr: escapeAttr,
        selectorQuote: selectorQuote,
        isWithin: isWithin,
        logDev: logDev,
        showError: showError,
        clearError: clearError,
        scheduleTimer: scheduleTimer,
        clearTimers: clearTimers,
        finiteNumber: finiteNumber,
        numericCss: numericCss,
        weighChars: weighChars,
        cleanStageText: cleanStageText,
        flashHtmlToText: flashHtmlToText,
        decodeHtmlEntities: decodeHtmlEntities,
        buildStageDetail: buildStageDetail,
        resolveAssetUrl: resolveAssetUrl
    };
})();
