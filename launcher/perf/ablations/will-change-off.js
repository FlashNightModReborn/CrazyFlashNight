// 强行清空所有 will-change：避免合成层爆炸 / 永久 GPU 内存占用。
// 视觉零损失（will-change 只是 hint）。
'use strict';
module.exports = {
    name: 'will-change-off',
    description: '清空所有 will-change（合成层提示）',
    css: `*, *::before, *::after { will-change: auto !important; }`,
};
