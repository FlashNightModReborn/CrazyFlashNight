/**
 * LUT 实验室 · 内置 fixture LUT（vhost 不可达时的降级数据源）
 *
 * 全部为代码程序化生成的 .cube 文本，经 LutLabCube.toRgba8 走与真实样品相同的
 * 解析/重采样管线。明确标注「内置 fixture · 非权威光照数据」，不模拟任何
 * color_engine_preset.xml 权威数值（权威烘焙只走 lutlab.bakeXml 桥命令）。
 */
(function() {
    'use strict';

    function buildCube(title, size, fn) {
        var lines = ['# CF7 LUT 实验室内置 fixture（非权威光照数据）', 'TITLE "' + title + '"', 'LUT_3D_SIZE ' + size];
        for (var b = 0; b < size; b++) for (var g = 0; g < size; g++) for (var r = 0; r < size; r++) {
            var out = fn(r / (size - 1), g / (size - 1), b / (size - 1));
            lines.push(out[0].toFixed(6) + ' ' + out[1].toFixed(6) + ' ' + out[2].toFixed(6));
        }
        return lines.join('\n') + '\n';
    }

    function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
    function luma(r, g, b) { return 0.2126 * r + 0.7152 * g + 0.0722 * b; }

    // identity 用 16³：线性斜坡经三线性重采样仍精确恒等，顺带在常规使用中覆盖重采样路径
    var FIXTURES = [
        {
            name: '内置 · Identity 恒等（16³→32³）',
            group: 'fixture',
            source: 'panel-fixture',
            license: 'CF7 内置',
            notes: '恒等基线；输出应与原图逐像素一致（QA 基准）。内置 fixture · 非权威光照数据',
            cubeText: buildCube('cf7-fixture-identity', 16, function(r, g, b) { return [r, g, b]; })
        },
        {
            name: '内置 · 绿夜视风味（示意）',
            group: 'fixture',
            source: 'panel-fixture',
            license: 'CF7 内置',
            notes: '亮度→绿色映射示意，仅供预览管线冒烟。内置 fixture · 非权威光照数据',
            cubeText: buildCube('cf7-fixture-green-night', 32, function(r, g, b) {
                var l = Math.pow(luma(r, g, b), 0.8);
                return [clamp01(0.12 * l), clamp01(0.18 + 0.82 * l), clamp01(0.10 * l)];
            })
        },
        {
            name: '内置 · 黄昏高对比（示意）',
            group: 'fixture',
            source: 'panel-fixture',
            license: 'CF7 内置',
            notes: 'S 曲线 + 暖偏示意，供观察暗部 banding。内置 fixture · 非权威光照数据',
            cubeText: buildCube('cf7-fixture-dusk-contrast', 32, function(r, g, b) {
                function s(x) { return x * x * (3 - 2 * x); }
                return [clamp01(s(r) * 1.08), clamp01(s(g) * 0.96), clamp01(s(b) * 0.82)];
            })
        }
    ];

    window.CF7 = window.CF7 || {};
    window.CF7.LutLabFixtures = { list: FIXTURES };
})();
