// 关掉所有 box-shadow：blur 半径越大栅格化越贵，且 keyframe 中改变 box-shadow 极昂贵。
// 视觉影响：UI 失去阴影感，多处会显得"扁"。
'use strict';
module.exports = {
    name: 'box-shadow-off',
    description: '禁用所有 box-shadow',
    css: `*, *::before, *::after { box-shadow: none !important; }`,
};
