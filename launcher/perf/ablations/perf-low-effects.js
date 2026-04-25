// 触发现有的 .perf-low-effects 内置降级开关（overlay.css:16-38 起）。
// 测量项目"已实现的应急降级"实际收益作为对照。
'use strict';
module.exports = {
    name: 'perf-low-effects',
    description: '激活 html.perf-low-effects（项目内置降级开关）',
    js: `document.documentElement.classList.add('perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers');`,
};
