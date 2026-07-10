(function(global) {
    'use strict';

    function render(options) {
        options = options || {};
        var detail = options.detail || {};
        var escHtml = options.escHtml || fallbackEscape;
        var dialogueHtml = options.dialogueHtml || escHtml;
        var limitsHtml = options.limitsHtml ? options.limitsHtml(options.limits || []) : '';
        var rewardsHtml = options.rewardsHtml ? options.rewardsHtml(detail.rewards || []) : '';
        var dialogueMode = options.dialogueMode === 'brief' ? 'brief' : 'rich';
        var dialogueButtonText = options.dialogueButtonText || '缩略模式';
        var rewardsTitle = options.rewardsTitle || '任务奖励';
        var title = detail.title || detail.stageName || '任务简报';
        var meta = '';

        if (detail.npcName) meta += '<span class="dgn-npc">委托人：' + escHtml(detail.npcName) + '</span>';
        if (detail.recommendedLevel) meta += '<span class="dgn-lv">推荐等级 ' + escHtml(detail.recommendedLevel) + '</span>';
        if (options.difficulty) meta += '<span class="dgn-diff">难度 ' + escHtml(options.difficulty) + '</span>';
        if (options.statusLabel) meta += '<span class="dispatch-brief-status">' + escHtml(options.statusLabel) + '</span>';

        return '' +
            '<div class="dgn-info mission-brief-info">' +
                '<div class="dgn-summary">' +
                    '<div class="dgn-name">' + escHtml(title) + '</div>' +
                    '<div class="dgn-meta">' + meta + '</div>' +
                    (detail.description ? '<div class="dgn-desc">' + dialogueHtml(detail.description) + '</div>' : '') +
                '</div>' +
                '<div class="dgn-section-title">限制词条</div>' +
                '<div class="dgn-limits">' + limitsHtml + '</div>' +
                ((detail.rewards && detail.rewards.length) ? '<div class="dgn-section-title">' + escHtml(rewardsTitle) + '</div><div class="dgn-rewards">' + rewardsHtml + '</div>' : '') +
                '<div class="dgn-section-title dgn-dialogue-title"><span>任务简报</span>' +
                    '<button type="button" class="tlv-dia-mode-btn dgn-dia-mode-btn" data-dialogue-mode-toggle="1">' + escHtml(dialogueButtonText) + '</button></div>' +
                '<div class="dgn-dialogue cf-dialogue" data-dialogue-mode="' + dialogueMode + '"><div class="tlv-dia-empty">加载简报…</div></div>' +
            '</div>';
    }

    function fallbackEscape(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    global.MissionBriefView = {
        render: render
    };
})(window);
