// 关掉所有 backdrop-filter：iGPU 上每帧卷积 blur 是头号嫌疑。
// 视觉影响：失去毛玻璃透视，但因元素已有半透明纯色背景兜底，多数情况下肉眼不可分。
'use strict';
module.exports = {
    name: 'backdrop-filter-off',
    description: '禁用所有 backdrop-filter（毛玻璃）',
    css: `*, *::before, *::after { backdrop-filter: none !important; -webkit-backdrop-filter: none !important; }`,
};
