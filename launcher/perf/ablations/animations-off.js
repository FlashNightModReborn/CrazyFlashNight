// 关掉所有 CSS 动画与 transition：等同于复用 .perf-no-css-animations 的强力降级。
// 用作收益上界对照——告诉你"所有动画都没了"能省多少。
'use strict';
module.exports = {
    name: 'animations-off',
    description: '禁用所有 CSS animation/transition（上界对照）',
    css: `*, *::before, *::after {
        animation: none !important;
        transition-duration: 0ms !important;
        transition-delay: 0ms !important;
    }`,
};
