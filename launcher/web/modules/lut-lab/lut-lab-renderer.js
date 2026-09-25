/**
 * LUT 实验室 · WebGL2 3D LUT 渲染器
 *
 * 单个离屏 WebGL2 画布服务整个面板：setSource 上传图像，32^3 RGBA8 3D 纹理
 *（硬件三线性，LINEAR + CLAMP_TO_EDGE），render 后 drawImage 到各对比格。
 * 采样坐标映射 c*(31/32)+0.5/32 使硬件三线性精确等价于体素空间 c*31 的三线性插值。
 * WebGL2 不可用或初始化失败时 create 抛错，由面板显示明确错误（不静默回退 CPU）。
 *
 * v2：双集合双档采样。setDualLut(A0,A1,B0,B1) 上传「集合 A/B × 等级 floor/ceil」四张 3D 纹理，
 * setLevelMix(t) 在相邻档间 mix（生产 350ms 过渡的语义预览），setView 切换
 * 单图(A/B)/差值 |A-B|×4/分屏(uSplitX)。旧 setLut(lut) ≡ setDualLut(lut,lut,null,null)
 * + 单图 A，QA 基线（identity 逐像素恒等）不受影响。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LutLabRenderer = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var LUT_SIZE = 32;

    var VERT = '#version 300 es\n'
        + 'layout(location=0) in vec2 aPos;\n'
        + 'out vec2 vUv;\n'
        + 'void main() { vUv = vec2(aPos.x * 0.5 + 0.5, 0.5 - aPos.y * 0.5); gl_Position = vec4(aPos, 0.0, 1.0); }';

    // uView：0=单图（uViewB 选 A/B），1=差值 |A-B|x4，2=分屏（vUv.x < uSplitX 显 A 否则显 B）
    var FRAG = '#version 300 es\n'
        + 'precision highp float;\n'
        + 'precision highp sampler3D;\n'
        + 'uniform sampler2D uImage;\n'
        + 'uniform sampler3D uLutA0;\n'
        + 'uniform sampler3D uLutA1;\n'
        + 'uniform sampler3D uLutB0;\n'
        + 'uniform sampler3D uLutB1;\n'
        + 'uniform vec3 uDomainMin;\n'
        + 'uniform vec3 uDomainRange;\n'
        + 'uniform float uMixT;\n'
        + 'uniform int uView;\n'
        + 'uniform float uViewB;\n'
        + 'uniform float uSplitX;\n'
        + 'in vec2 vUv;\n'
        + 'out vec4 outColor;\n'
        + 'void main() {\n'
        + '    vec4 c = texture(uImage, vUv);\n'
        + '    vec3 t = clamp((c.rgb - uDomainMin) / uDomainRange, 0.0, 1.0);\n'
        + '    vec3 coord = t * (' + (LUT_SIZE - 1) + '.0 / ' + LUT_SIZE + '.0) + vec3(0.5 / ' + LUT_SIZE + '.0);\n'
        + '    vec3 a = mix(texture(uLutA0, coord).rgb, texture(uLutA1, coord).rgb, uMixT);\n'
        + '    vec3 b = mix(texture(uLutB0, coord).rgb, texture(uLutB1, coord).rgb, uMixT);\n'
        + '    vec3 single = uViewB > 0.5 ? b : a;\n'
        + '    vec3 diffv = clamp(abs(a - b) * 4.0, 0.0, 1.0);\n'
        + '    vec3 splitv = vUv.x < uSplitX ? a : b;\n'
        + '    vec3 outRgb = uView == 1 ? diffv : (uView == 2 ? splitv : single);\n'
        + '    outColor = vec4(outRgb, c.a);\n'
        + '}';

    function compile(gl, type, source) {
        var shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            var log = gl.getShaderInfoLog(shader);
            gl.deleteShader(shader);
            throw new Error('LUT shader 编译失败: ' + log);
        }
        return shader;
    }

    function create(options) {
        options = options || {};
        if (typeof document === 'undefined') throw new Error('LUT 渲染器需要浏览器环境');
        var canvas = options.canvas || document.createElement('canvas');
        var gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, premultipliedAlpha: false });
        if (!gl) throw new Error('当前环境不支持 WebGL2（需要 3D 纹理做硬件三线性 LUT 采样）');

        var program = gl.createProgram();
        gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
        gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG));
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
            throw new Error('LUT shader 链接失败: ' + gl.getProgramInfoLog(program));
        }
        gl.useProgram(program);

        var quad = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, quad);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

        var imageTex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, imageTex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        function makeLutTexture() {
            var tex = gl.createTexture();
            gl.bindTexture(gl.TEXTURE_3D, tex);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
            return tex;
        }
        var lutTexA0 = makeLutTexture();
        var lutTexA1 = makeLutTexture();
        var lutTexB0 = makeLutTexture();
        var lutTexB1 = makeLutTexture();

        gl.uniform1i(gl.getUniformLocation(program, 'uImage'), 0);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutA0'), 1);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutA1'), 2);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutB0'), 3);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutB1'), 4);
        var uDomainMin = gl.getUniformLocation(program, 'uDomainMin');
        var uDomainRange = gl.getUniformLocation(program, 'uDomainRange');
        gl.uniform3f(uDomainMin, 0, 0, 0);
        gl.uniform3f(uDomainRange, 1, 1, 1);
        var uMixT = gl.getUniformLocation(program, 'uMixT');
        var uView = gl.getUniformLocation(program, 'uView');
        var uViewB = gl.getUniformLocation(program, 'uViewB');
        var uSplitX = gl.getUniformLocation(program, 'uSplitX');
        gl.uniform1f(uMixT, 0);
        gl.uniform1i(uView, 0);
        gl.uniform1f(uViewB, 0);
        gl.uniform1f(uSplitX, 0.5);

        var width = 0, height = 0;

        function setSource(source, sourceWidth, sourceHeight) {
            width = sourceWidth || source.width;
            height = sourceHeight || source.height;
            if (!width || !height) throw new Error('源图像尺寸非法');
            canvas.width = width;
            canvas.height = height;
            gl.viewport(0, 0, width, height);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, imageTex);
            gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, source);
        }

        // lut: {rgba:Uint8Array(32^3*4), domainMin?, domainMax?}（R 分量变化最快）
        function checkLut(lut) {
            if (!lut || !lut.rgba || lut.rgba.length !== LUT_SIZE * LUT_SIZE * LUT_SIZE * 4) {
                throw new Error('LUT 必须是 32^3 RGBA8（' + LUT_SIZE * LUT_SIZE * LUT_SIZE * 4 + ' 字节）');
            }
        }
        var identity = null; // 懒建：B 侧缺省/单 LUT 兼容路径用
        function identityLut() {
            if (!identity) identity = { rgba: identityRgba8(), domainMin: [0, 0, 0], domainMax: [1, 1, 1] };
            return identity;
        }
        function uploadLut(unit, tex, lut) {
            gl.activeTexture(gl.TEXTURE0 + unit);
            gl.bindTexture(gl.TEXTURE_3D, tex);
            gl.texImage3D(gl.TEXTURE_3D, 0, gl.RGBA8, LUT_SIZE, LUT_SIZE, LUT_SIZE, 0,
                gl.RGBA, gl.UNSIGNED_BYTE, lut.rgba);
        }
        function applyDomain(lut) {
            var min = lut.domainMin || [0, 0, 0];
            var max = lut.domainMax || [1, 1, 1];
            gl.uniform3f(uDomainMin, min[0], min[1], min[2]);
            gl.uniform3f(uDomainRange, max[0] - min[0], max[1] - min[1], max[2] - min[2]);
        }
        // v2 主 API：A/B 集合 x 等级 floor/ceil。null 侧回退恒等；domain 取 a0（集合内应同域）。
        function setDualLut(a0, a1, b0, b1) {
            a0 = a0 || identityLut(); a1 = a1 || a0;
            b0 = b0 || identityLut(); b1 = b1 || b0;
            checkLut(a0); checkLut(a1); checkLut(b0); checkLut(b1);
            uploadLut(1, lutTexA0, a0);
            uploadLut(2, lutTexA1, a1);
            uploadLut(3, lutTexB0, b0);
            uploadLut(4, lutTexB1, b1);
            applyDomain(a0);
        }
        // 旧单 LUT 路径（QA 基线/胶片条整档）：A0=A1=lut，B 侧恒等，mix=0。
        function setLut(lut) {
            checkLut(lut);
            setDualLut(lut, lut, null, null);
            gl.uniform1f(uMixT, 0);
        }
        // 等级小数部分 0..1（相邻档 mix）
        function setLevelMix(t) {
            gl.uniform1f(uMixT, Math.max(0, Math.min(1, t)));
        }
        // view: 'A' | 'B' | 'diff' | 'split'；splitX 仅 split 用（0..1）
        function setView(view, splitX) {
            gl.uniform1i(uView, view === 'diff' ? 1 : (view === 'split' ? 2 : 0));
            gl.uniform1f(uViewB, view === 'B' ? 1 : 0);
            gl.uniform1f(uSplitX, typeof splitX === 'number' ? Math.max(0, Math.min(1, splitX)) : 0.5);
        }

        function render() {
            if (!width || !height) throw new Error('尚未设置源图像');
            gl.drawArrays(gl.TRIANGLES, 0, 3);
            return canvas;
        }

        // 顶行在前（readPixels 原始结果为底行在前，此处翻回图像坐标系）
        function readPixels() {
            var raw = new Uint8Array(width * height * 4);
            gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, raw);
            var out = new Uint8Array(raw.length);
            var stride = width * 4;
            for (var y = 0; y < height; y++) {
                out.set(raw.subarray((height - 1 - y) * stride, (height - y) * stride), y * stride);
            }
            return out;
        }

        return {
            canvas: canvas,
            gl: gl,
            setSource: setSource,
            setLut: setLut,
            setDualLut: setDualLut,
            setLevelMix: setLevelMix,
            setView: setView,
            render: render,
            readPixels: readPixels,
            size: function() { return { width: width, height: height }; }
        };
    }

    // 32^3 恒等 LUT（RGBA8，R 最快）：identity 输出 == 输入的 QA 基线也用它。
    function identityRgba8() {
        var rgba = new Uint8Array(LUT_SIZE * LUT_SIZE * LUT_SIZE * 4);
        var i = 0;
        for (var b = 0; b < LUT_SIZE; b++) for (var g = 0; g < LUT_SIZE; g++) for (var r = 0; r < LUT_SIZE; r++) {
            rgba[i++] = Math.round(r / (LUT_SIZE - 1) * 255);
            rgba[i++] = Math.round(g / (LUT_SIZE - 1) * 255);
            rgba[i++] = Math.round(b / (LUT_SIZE - 1) * 255);
            rgba[i++] = 255;
        }
        return rgba;
    }

    return { create: create, LUT_SIZE: LUT_SIZE, identityRgba8: identityRgba8 };
});
