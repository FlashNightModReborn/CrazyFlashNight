/**
 * LUT 实验室 · .CUBE 解析器（Adobe Cube LUT 3D）
 *
 * 契约：
 *  - 支持 TITLE / LUT_3D_SIZE / DOMAIN_MIN / DOMAIN_MAX；其他关键字明确拒绝。
 *  - 数据行 R 分量变化最快（.cube 标准序）；数量必须恰为 size^3。
 *  - 内部统一 32^3 RGBA8（alpha 固定 255）；16/17/33/64 等其他尺寸经三线性重采样到 32^3，
 *    端点保持精确（identity 任意尺寸重采样后仍恒等）。
 *  - DOMAIN 非默认 [0,1] 时保留 domainMin/domainMax，由渲染器 shader 做输入域映射。
 *
 * 同时暴露 window.CF7.LutLabCube（面板/QA）与 module.exports（Node 单测）。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LutLabCube = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var TARGET_SIZE = 32;

    function fail(message) { throw new Error('.CUBE: ' + message); }

    function parse(text) {
        if (typeof text !== 'string' || !text.length) fail('空文件');
        var size = 0, title = '';
        var domainMin = [0, 0, 0], domainMax = [1, 1, 1];
        var values = [];
        var lines = text.split(/\r\n|\r|\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line || line.charAt(0) === '#') continue;
            var parts = line.split(/\s+/);
            var head = parts[0].toUpperCase();
            if (head === 'TITLE') { title = line.slice(5).trim().replace(/^"|"$/g, ''); continue; }
            if (head === 'LUT_3D_SIZE') {
                size = parseInt(parts[1], 10);
                if (!isFinite(size) || size < 2 || size > 64) fail('LUT_3D_SIZE 非法: ' + parts[1]);
                continue;
            }
            if (head === 'LUT_1D_SIZE') fail('暂不支持 1D LUT（LUT_1D_SIZE）');
            if (head === 'DOMAIN_MIN' || head === 'DOMAIN_MAX') {
                var v = parts.slice(1, 4).map(Number);
                if (v.length !== 3 || v.some(function(x) { return !isFinite(x); })) fail(head + ' 需要 3 个数值');
                if (head === 'DOMAIN_MIN') domainMin = v; else domainMax = v;
                continue;
            }
            var nums = parts.map(Number);
            if (nums.length === 3 && nums.every(function(x) { return isFinite(x); })) {
                values.push(nums[0], nums[1], nums[2]);
                continue;
            }
            fail('无法识别的行 ' + (i + 1) + ': ' + line.slice(0, 40));
        }
        if (!size) fail('缺少 LUT_3D_SIZE');
        if (values.length !== size * size * size * 3) {
            fail('数据点数量不符：期望 ' + (size * size * size) + ' 实际 ' + (values.length / 3));
        }
        for (var d = 0; d < 3; d++) {
            if (!(domainMax[d] > domainMin[d])) fail('DOMAIN_MAX 必须大于 DOMAIN_MIN');
        }
        return { title: title, size: size, domainMin: domainMin, domainMax: domainMax, data: new Float32Array(values) };
    }

    // 三线性重采样到 32^3；目标体素 i 表达归一化坐标 i/31，映射回源体素空间 (i/31)*(n-1)。
    function resample32(src) {
        var n = src.size;
        var out = new Float32Array(TARGET_SIZE * TARGET_SIZE * TARGET_SIZE * 3);
        var s = src.data;
        function at(r, g, b, c) { return s[((b * n + g) * n + r) * 3 + c]; }
        for (var b = 0; b < TARGET_SIZE; b++) for (var g = 0; g < TARGET_SIZE; g++) for (var r = 0; r < TARGET_SIZE; r++) {
            var dst = ((b * TARGET_SIZE + g) * TARGET_SIZE + r) * 3;
            if (n === TARGET_SIZE) {
                out[dst] = at(r, g, b, 0); out[dst + 1] = at(r, g, b, 1); out[dst + 2] = at(r, g, b, 2);
                continue;
            }
            var coords = [r, g, b].map(function(i) { return i / (TARGET_SIZE - 1) * (n - 1); });
            var lo = coords.map(Math.floor), hi = coords.map(function(x) { return Math.min(n - 1, Math.floor(x) + 1); });
            var f = coords.map(function(x, k) { return x - lo[k]; });
            for (var c = 0; c < 3; c++) {
                var acc = 0;
                for (var corner = 0; corner < 8; corner++) {
                    var w = 1;
                    for (var k = 0; k < 3; k++) w *= (corner >> k & 1) ? f[k] : 1 - f[k];
                    acc += w * at(
                        (corner & 1) ? hi[0] : lo[0],
                        (corner & 2) ? hi[1] : lo[1],
                        (corner & 4) ? hi[2] : lo[2], c);
                }
                out[dst + c] = acc;
            }
        }
        return out;
    }

    function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }

    // 解析 + 重采样 + 量化的一站式入口：返回渲染器直接可上传的 32^3 RGBA8（R 最快）。
    function toRgba8(text) {
        var parsed = parse(text);
        var data32 = resample32(parsed);
        var rgba = new Uint8Array(TARGET_SIZE * TARGET_SIZE * TARGET_SIZE * 4);
        for (var i = 0, j = 0; i < data32.length; i += 3, j += 4) {
            rgba[j] = Math.round(clamp01(data32[i]) * 255);
            rgba[j + 1] = Math.round(clamp01(data32[i + 1]) * 255);
            rgba[j + 2] = Math.round(clamp01(data32[i + 2]) * 255);
            rgba[j + 3] = 255;
        }
        return {
            title: parsed.title,
            srcSize: parsed.size,
            size: TARGET_SIZE,
            domainMin: parsed.domainMin,
            domainMax: parsed.domainMax,
            rgba: rgba
        };
    }

    return { TARGET_SIZE: TARGET_SIZE, parse: parse, resample32: resample32, toRgba8: toRgba8 };
});
