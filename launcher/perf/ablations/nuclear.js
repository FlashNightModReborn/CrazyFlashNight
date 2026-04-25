// 上界对照：把 backdrop-filter + filter + mix-blend-mode + animation + box-shadow 全关。
// 这是"最大可能"的视觉损失，仅用于知道天花板在哪。施工不会用。
'use strict';
module.exports = {
    name: 'nuclear',
    description: '上界对照：关掉所有视觉重头属性（仅做天花板估算）',
    css: `*, *::before, *::after {
        backdrop-filter: none !important;
        -webkit-backdrop-filter: none !important;
        filter: none !important;
        -webkit-filter: none !important;
        mix-blend-mode: normal !important;
        box-shadow: none !important;
        animation: none !important;
        transition-duration: 0ms !important;
        will-change: auto !important;
    }`,
};
