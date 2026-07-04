(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.ArenaCustomResultView = factory();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
    'use strict';

    function fallbackEscapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatDurationMs(value) {
        var ms = Number(value);
        if (isNaN(ms) || ms < 0) return '--';
        if (ms < 1000) return Math.round(ms) + ' ms';
        return (Math.round(ms / 100) / 10).toFixed(1) + ' s';
    }

    function resultOutcome(result, state) {
        state = state ? String(state) : '';
        if (state === 'failed') return { label: '委托失败', className: 'arena-custom-result-title-failed' };
        if (state === 'aborted' || state === 'abort_requested') return { label: '委托中止', className: 'arena-custom-result-title-neutral' };
        if (!result) return { label: '结果未知', className: 'arena-custom-result-title-neutral' };

        var winner = String(result.winner || 'none');
        if (winner === 'blue') return { label: '蓝方胜', className: 'arena-custom-result-title-blue' };
        if (winner === 'red') return { label: '红方胜', className: 'arena-custom-result-title-red' };
        if (winner === 'draw') return { label: '平局', className: 'arena-custom-result-title-neutral' };
        if (winner === 'timeout') return { label: '超时', className: 'arena-custom-result-title-neutral' };
        return { label: '无胜者', className: 'arena-custom-result-title-neutral' };
    }

    function resultMeta(result, run) {
        var parts = [];
        if (result && result.status) parts.push(String(result.status));
        if (result && result.frames != null) parts.push(String(result.frames) + ' 帧');
        if (result && result.durationMs != null) parts.push(formatDurationMs(result.durationMs));
        if (run && run.batchId) parts.push(run.batchId);
        return parts.join(' · ');
    }

    function summarizeSideRoster(side, parsed, summarizeCustomRoster) {
        if (!parsed) return '--';
        return summarizeCustomRoster(side === 'blue' ? parsed.blueRoster : parsed.redRoster);
    }

    function buildSideHtml(side, title, summary, parsed, escapeHtml, summarizeCustomRoster) {
        var roster = summarizeSideRoster(side, parsed, summarizeCustomRoster);
        var maxHp = summary && summary.maxHp != null ? Number(summary.maxHp) : 0;
        var remainHp = summary && summary.remainHp != null ? Number(summary.remainHp) : 0;
        var aliveCount = summary && summary.aliveCount != null ? Number(summary.aliveCount) : 0;
        var startCount = summary && summary.startCount != null ? Number(summary.startCount) : 0;
        if (isNaN(maxHp) || maxHp < 0) maxHp = 0;
        if (isNaN(remainHp) || remainHp < 0) remainHp = 0;
        if (isNaN(aliveCount) || aliveCount < 0) aliveCount = 0;
        if (isNaN(startCount) || startCount < 0) startCount = 0;
        var pct = maxHp > 0 ? Math.max(0, Math.min(100, Math.round(remainHp * 100 / maxHp))) : 0;

        return '<div class="arena-custom-result-side arena-custom-result-side-' + side + '">' +
            '<div class="arena-custom-result-side-title">' + escapeHtml(title) + '</div>' +
            '<div class="arena-custom-result-side-roster">' + escapeHtml(roster) + '</div>' +
            '<div class="arena-custom-result-side-stats">' +
                '<span>存活 ' + aliveCount + '/' + startCount + '</span>' +
                '<span>HP ' + Math.round(remainHp) + '/' + Math.round(maxHp) + '</span>' +
            '</div>' +
            '<div class="arena-custom-result-hpbar"><i style="width:' + pct + '%"></i></div>' +
        '</div>';
    }

    function render(container, context) {
        if (!container) return;
        context = context || {};
        var escapeHtml = typeof context.escapeHtml === 'function' ? context.escapeHtml : fallbackEscapeHtml;
        var summarizeCustomRoster = typeof context.summarizeCustomRoster === 'function'
            ? context.summarizeCustomRoster
            : function() { return '--'; };
        var run = context.run || {};
        var customResult = context.customResult || null;
        var customMatch = context.customMatch || null;
        var result = run.lastResult || (customResult && customResult.lastResult) || null;
        var outcome = resultOutcome(result, run.state || (customResult && customResult.state));
        var meta = resultMeta(result, run);
        var matchCode = (customMatch && customMatch.code) || (customResult && customResult.matchCode) || '';
        var path = run.resultPath || (customResult && customResult.resultPath) || '';
        var error = run.lastError || (customResult && customResult.lastError) || run.error || '';
        var parsed = customMatch && customMatch.parsed;

        container.innerHTML =
            '<div class="arena-custom-result-panel">' +
                '<div class="arena-custom-result-header">' +
                    '<div>' +
                        '<div class="arena-custom-result-kicker">定制死亡竞赛 · 结算</div>' +
                        '<h2 class="arena-custom-result-title ' + outcome.className + '">' + escapeHtml(outcome.label) + '</h2>' +
                        '<div class="arena-custom-result-meta">' + escapeHtml(meta || '无战斗摘要') + '</div>' +
                    '</div>' +
                    '<button class="arena-custom-result-close" type="button" data-custom-result-action="back" data-audio-cue="confirm">返回基地</button>' +
                '</div>' +
                '<div class="arena-custom-result-sides">' +
                    buildSideHtml('blue', '蓝方', result ? result.blue : null, parsed, escapeHtml, summarizeCustomRoster) +
                    buildSideHtml('red', '红方', result ? result.red : null, parsed, escapeHtml, summarizeCustomRoster) +
                '</div>' +
                '<div class="arena-custom-result-codeblock">' +
                    '<div class="arena-custom-result-label">赛程代码</div>' +
                    '<div class="arena-custom-result-code">' + escapeHtml(matchCode || '--') + '</div>' +
                '</div>' +
                '<div class="arena-custom-result-detail">' +
                    '<span>结果文件</span>' +
                    '<b>' + escapeHtml(path || '--') + '</b>' +
                '</div>' +
                (error ? '<div class="arena-custom-result-error">' + escapeHtml(error) + '</div>' : '') +
                '<div class="arena-custom-result-actions">' +
                    '<button class="arena-custom-btn" type="button" data-custom-result-action="copy" data-audio-cue="confirm">复制代码</button>' +
                    '<button class="arena-custom-btn" type="button" data-custom-result-action="back" data-audio-cue="confirm">返回基地</button>' +
                    '<button class="arena-card-btn-enter arena-custom-result-reopen" type="button" data-custom-result-action="reopen" data-audio-cue="confirm">再赛一场</button>' +
                '</div>' +
            '</div>';
    }

    return {
        render: render
    };
});
