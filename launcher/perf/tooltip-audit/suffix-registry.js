(function(root) {
    'use strict';
    root.TooltipAuditSuffixRegistry = [
        {id:'none', metaHTML:'', suffix:''},
        {
            id:'balance-meta',
            metaHTML:'<div class="balance-tooltip-meta" aria-label="同级加权 3 层">'
                + '<div class="balance-tooltip-summary"><span class="balance-tooltip-caption">同级加权</span>'
                + '<b class="balance-tooltip-weight">◆+3</b></div></div>',
            suffix:''
        },
        {
            id:'intelligence-pages',
            metaHTML:'<div class="flash-tt-dim kshop-tt-dim">已发现 12 / 12 页</div>',
            suffix:''
        },
        {
            id:'kshop-locked-balance',
            metaHTML:'<div class="balance-tooltip-meta" aria-label="同级加权 -2 层">'
                + '<div class="balance-tooltip-summary"><span class="balance-tooltip-caption">同级加权</span>'
                + '<b class="balance-tooltip-weight">◆-2</b></div></div>',
            suffix:'<div class="flash-tt-lock-banner kshop-tt-lock-banner">⚿ 锁定 — 需要 Lv.99</div>'
        }
    ];
})(typeof window !== 'undefined' ? window : globalThis);
