// 关掉所有 mix-blend-mode：blend mode 强制层 readback，破坏 GPU fast-path。
// Kimi 独家发现的大头，预估 panel 态可降 8-13%。
'use strict';
module.exports = {
    name: 'mix-blend-off',
    description: '禁用所有 mix-blend-mode（blend 强制 readback）',
    css: `*, *::before, *::after { mix-blend-mode: normal !important; }`,
};
