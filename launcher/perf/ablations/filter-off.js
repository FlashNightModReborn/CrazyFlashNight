// 关掉所有 filter（含 drop-shadow / blur / saturate）：CSS filter 是 fragment shader 重头。
// 视觉影响较大（图标/按钮失去发光），用于 ablation 上界估算。
'use strict';
module.exports = {
    name: 'filter-off',
    description: '禁用所有 filter（含 drop-shadow/blur/saturate）',
    css: `*, *::before, *::after { filter: none !important; -webkit-filter: none !important; }`,
};
