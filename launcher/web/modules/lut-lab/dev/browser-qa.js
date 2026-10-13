/**
 * LUT 实验室 v2 harness 页面内 QA（?qa=1 时运行）。
 *
 * 覆盖：WebGL2 可用性、XML 集合 10 档加载、胶片条十格渲染、identity 逐像素恒等、
 * 已知 17³ LUT GPU vs CPU 对照、样品清单合并、A==B 差值纯黑、peek/锁定切换渲染正确集合、
 * 胶片条逐档与单独渲染一致（±1/255）、扫动启停、帮助开关、抽屉退化集合载入、
 * 布局无横向滚动/溢出、入场帧缺省回退、重开回归（生产 close 契约）、双降级路径。
 * 荧光：A 恒等、B 旁路、轮廓方向/光晕、真实底图混合、分屏/差值、尺寸与源代际、
 * 快捷参数、胶片/主图/检视一致性、参数跨重开恢复及旧字段兼容。
 *
 * 结果：window.__LUTLAB_QA_RESULTS__ = [{id, pass, detail}]，
 * 终态写 documentElement[data-lutlab-qa] = passed|failed。
 */
(function() {
    'use strict';

    var params = new URLSearchParams(location.search);
    if (params.get('qa') !== '1') return;

    var results = [];
    function record(id, pass, detail) {
        results.push({ id: id, pass: !!pass, detail: detail == null ? '' : String(detail) });
        var host = document.getElementById('qa-results');
        if (host) {
            var row = document.createElement('div');
            row.setAttribute('data-pass', pass ? 'true' : 'false');
            row.textContent = (pass ? '✓ ' : '✗ ') + id + (detail ? ' — ' + detail : '');
            host.appendChild(row);
        }
    }

    function delay(ms) { return new Promise(function(resolve) { setTimeout(resolve, ms); }); }

    function waitFor(check, timeoutMs, label) {
        var started = Date.now();
        return new Promise(function(resolve, reject) {
            (function poll() {
                var value;
                try { value = check(); } catch (e) { value = null; }
                if (value) { resolve(value); return; }
                if (Date.now() - started > (timeoutMs || 10000)) {
                    reject(new Error('waitFor 超时: ' + (label || 'condition')));
                    return;
                }
                setTimeout(poll, 40);
            })();
        });
    }

    // ===== 测试专用：CPU 三线性参考施加器（QA test double，非生产代码路径）=====
    function qaParseCube(text) {
        var size = 0, values = [];
        text.split(/\r\n|\r|\n/).forEach(function(line) {
            line = line.trim();
            if (!line || line.charAt(0) === '#') return;
            var parts = line.split(/\s+/);
            if (parts[0].toUpperCase() === 'LUT_3D_SIZE') { size = parseInt(parts[1], 10); return; }
            if (/^[A-Z]/.test(parts[0])) return;
            values.push(Number(parts[0]), Number(parts[1]), Number(parts[2]));
        });
        if (!size || values.length !== size * size * size * 3) throw new Error('qaParseCube: 数据不符');
        return { size: size, data: values };
    }
    function qaResampleQuantize32(src) {
        var n = src.size, out = new Uint8Array(32 * 32 * 32 * 3);
        function at(r, g, b, c) { return src.data[((b * n + g) * n + r) * 3 + c]; }
        for (var b = 0; b < 32; b++) for (var g = 0; g < 32; g++) for (var r = 0; r < 32; r++) {
            var o = ((b * 32 + g) * 32 + r) * 3;
            var cr = r / 31 * (n - 1), cg = g / 31 * (n - 1), cb = b / 31 * (n - 1);
            var r0 = Math.floor(cr), g0 = Math.floor(cg), b0 = Math.floor(cb);
            var r1 = Math.min(n - 1, r0 + 1), g1 = Math.min(n - 1, g0 + 1), b1 = Math.min(n - 1, b0 + 1);
            var fr = cr - r0, fg = cg - g0, fb = cb - b0;
            for (var c = 0; c < 3; c++) {
                var acc = 0;
                for (var k = 0; k < 8; k++) {
                    var w = ((k & 1) ? fr : 1 - fr) * ((k & 2) ? fg : 1 - fg) * ((k & 4) ? fb : 1 - fb);
                    acc += w * at((k & 1) ? r1 : r0, (k & 2) ? g1 : g0, (k & 4) ? b1 : b0, c);
                }
                out[o + c] = Math.round(Math.max(0, Math.min(1, acc)) * 255);
            }
        }
        return out;
    }
    function qaApplyLut3D(pixels, lut32) {
        var out = new Uint8Array(pixels.length);
        for (var i = 0; i < pixels.length; i += 4) {
            var cr = pixels[i] / 255 * 31, cg = pixels[i + 1] / 255 * 31, cb = pixels[i + 2] / 255 * 31;
            var r0 = Math.floor(cr), g0 = Math.floor(cg), b0 = Math.floor(cb);
            var r1 = Math.min(31, r0 + 1), g1 = Math.min(31, g0 + 1), b1 = Math.min(31, b0 + 1);
            var fr = cr - r0, fg = cg - g0, fb = cb - b0;
            for (var c = 0; c < 3; c++) {
                var acc = 0;
                for (var k = 0; k < 8; k++) {
                    var ri = (k & 1) ? r1 : r0, gi = (k & 2) ? g1 : g0, bi = (k & 4) ? b1 : b0;
                    var w = ((k & 1) ? fr : 1 - fr) * ((k & 2) ? fg : 1 - fg) * ((k & 4) ? fb : 1 - fb);
                    acc += w * lut32[((bi * 32 + gi) * 32 + ri) * 3 + c];
                }
                out[i + c] = Math.round(acc);
            }
            out[i + 3] = pixels[i + 3];
        }
        return out;
    }
    // ===== 测试专用结束 =====

    function makeQaImage() {
        var w = 96, h = 64;
        var data = new Uint8Array(w * h * 4);
        for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
            var i = (y * w + x) * 4;
            if (x < 72) {
                var v = Math.round(x / 71 * 80);
                data[i] = Math.max(0, Math.min(255, v + (y % 3) - 1));
                data[i + 1] = v;
                data[i + 2] = Math.max(0, Math.min(255, v + (y % 2)));
            } else {
                var t = Math.round(y / (h - 1) * 255);
                data[i] = t; data[i + 1] = t; data[i + 2] = t;
            }
            data[i + 3] = 255;
        }
        return { width: w, height: h, data: data };
    }

    function imageDataOf(pixels, w, h) {
        var img = new ImageData(w, h);
        img.data.set(pixels);
        return img;
    }

    function comparePixels(actual, expected, tolerance) {
        var maxDiff = 0, diffs = 0;
        for (var i = 0; i < expected.length; i += 4) {
            for (var c = 0; c < 3; c++) {
                var d = Math.abs(actual[i + c] - expected[i + c]);
                if (d > maxDiff) maxDiff = d;
                if (d > tolerance) diffs++;
            }
        }
        return { maxDiff: maxDiff, overTolerance: diffs };
    }

    function spec() { return window.__lutLabHarness.spec(); }
    function dbg() { return spec()._debugState(); }
    function root() { return document.getElementById('lut-lab-panel'); }
    function readMain() { return spec()._debugReadMain(); }
    function readSource() { return spec()._debugReadSource(); }

    function cellCanvasesNonblank(selector, minCount) {
        var cells = root().querySelectorAll(selector + ' canvas');
        if (cells.length < minCount) return null;
        for (var i = 0; i < cells.length; i++) {
            var ctx = cells[i].getContext('2d');
            var d = ctx.getImageData(0, 0, cells[i].width, cells[i].height).data;
            var distinct = {};
            for (var p = 0; p < d.length; p += 16) distinct[d[p] + ',' + d[p + 1] + ',' + d[p + 2]] = 1;
            if (Object.keys(distinct).length < 4) return null;
        }
        return cells.length;
    }

    function selectSet(side, predicate) {
        var select = root().querySelector(side === 'A' ? '#lut-lab-set-a' : '#lut-lab-set-b');
        var option = Array.prototype.find.call(select.options, function(o) { return predicate(o); });
        if (!option) throw new Error('集合选择器里找不到匹配项（' + side + '）');
        select.value = option.value;
        select.dispatchEvent(new Event('change', { bubbles: true }));
    }

    async function phaseA() {
        // 1. WebGL2 可用（面板不允许静默回退，QA 先直接证明渲染器可建）
        var rendererOk = false, rendererErr = '';
        try {
            var probe = CF7.LutLabRenderer.create();
            probe.gl.getExtension('WEBGL_lose_context').loseContext();
            rendererOk = true;
        } catch (e) { rendererErr = e.message; }
        record('webgl2-available', rendererOk, rendererErr || 'WebGL2 上下文创建成功');
        if (!rendererOk) throw new Error('WebGL2 不可用，终止 QA');

        window.__lutLabHarness.open();

        // 2. XML 集合加载：mock 桥 bakeXmlSet → 10 档齐
        await waitFor(function() {
            var s = dbg();
            var xml = s && s.sets.filter(function(x) { return x.id === 'xml:光照'; })[0];
            return xml && xml.loaded && xml.levelsReady === 10;
        }, 10000, 'XML 集合加载');
        record('xml-set-loads', true, 'xml:光照 levelsReady=10（lutlab.bakeXmlSet）');

        // 3. 胶片条：十格同帧并排且非全黑；无 entryFrameUrl 时源图回退内置测试图
        var openedSourceLabel = '';
        await waitFor(function() {
            var s = dbg();
            if (s && s.source && s.source.label) openedSourceLabel = s.source.label;
            return cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, '胶片条渲染');
        record('panel-open-filmstrip', true,
            '胶片条 cells=' + root().querySelectorAll('.lut-lab-film-cell').length);
        record('entry-frame-fallback', openedSourceLabel.indexOf('内置测试图') >= 0,
            '无 entryFrameUrl 回退源图=' + openedSourceLabel);

        // 4. identity LUT 输出 == 原图（逐像素精确，独立渲染器基线）
        var qa = makeQaImage();
        var renderer = CF7.LutLabRenderer.create();
        renderer.setSource(imageDataOf(qa.data, qa.width, qa.height));
        renderer.setLut({ rgba: CF7.LutLabRenderer.identityRgba8() });
        renderer.render();
        var identityCmp = comparePixels(renderer.readPixels(), qa.data, 0);
        record('identity-pixel-exact', identityCmp.maxDiff === 0,
            'maxDiff=' + identityCmp.maxDiff + '（96×64 暗部渐变，identity 必须逐像素恒等）');

        // 5. 已知 17³ 非线性 LUT：GPU 硬件三线性 vs CPU 参考（容差 ≤1/255）
        var cubeText = await fetch('/vhost/samples/generated/qa-nonlin-17.cube', { cache: 'no-store' })
            .then(function(r) { return r.text(); });
        var panelLut = CF7.LutLabCube.toRgba8(cubeText);
        renderer.setLut({ rgba: panelLut.rgba, domainMin: panelLut.domainMin, domainMax: panelLut.domainMax });
        renderer.render();
        var gpuOut = renderer.readPixels();
        var cpuOut = qaApplyLut3D(qa.data, qaResampleQuantize32(qaParseCube(cubeText)));
        var cmp = comparePixels(gpuOut, cpuOut, 1);
        record('known-lut-cpu-match', cmp.overTolerance === 0,
            'maxDiff=' + cmp.maxDiff + '/255，超容差像素=' + cmp.overTolerance + '（srcSize=' + panelLut.srcSize + '）');
        renderer.gl.getExtension('WEBGL_lose_context').loseContext();

        // 6. 样品清单合并（generated+free 成功，xml-regression 畸形 JSON 不拖垮整表）
        await waitFor(function() { return root().getAttribute('data-vhost') === 'ok'; }, 10000, 'vhost ok');
        var s6 = dbg();
        record('manifest-merge', s6.samples >= 5 && s6.manifestErrors.length >= 1,
            'samples=' + s6.samples + '（generated 1 + free 1 + fixture 3）；manifestErrors=' + s6.manifestErrors.length);

        // 7. A==B 差值必须纯黑
        selectSet('B', function(o) { return o.value === dbg().setA; });
        await waitFor(function() {
            var s = dbg();
            return s.setA === s.setB && s.setA === 'xml:光照';
        }, 5000, 'B 设为 A 同集合');
        root().querySelector('.lut-lab-view button[data-view="diff"]').click();
        var diffOut = readMain();
        var nonBlack = 0;
        for (var i = 0; i < diffOut.length; i += 4) {
            if (diffOut[i] !== 0 || diffOut[i + 1] !== 0 || diffOut[i + 2] !== 0) nonBlack++;
        }
        record('ab-diff-pure-black', nonBlack === 0, 'A==B 差值非黑像素=' + nonBlack + '（必须 0）');

        // 8. peek（空格按住）渲染 B、松开回 A；锁定切换主显集合
        //    先把 B 换成与 A 不同的集合（fixture 绿夜视退化集合）
        selectSet('B', function(o) { return o.textContent.indexOf('绿夜视') >= 0; });
        await waitFor(function() {
            var s = dbg();
            return s.setB !== s.setA && s.sets.filter(function(x) { return x.id === s.setB && x.loaded; }).length === 1;
        }, 10000, 'B 集合加载');
        root().querySelector('.lut-lab-view button[data-view="single"]').click();
        var mainA = readMain().slice();
        window.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }));
        await waitFor(function() { return dbg().peekB === true; }, 3000, 'peekB 置位');
        var mainPeek = readMain().slice();
        window.dispatchEvent(new KeyboardEvent('keyup', { key: ' ', bubbles: true }));
        var mainBack = readMain().slice();
        var peekDiffers = comparePixels(mainPeek, mainA, 0).maxDiff > 0;
        var backSame = comparePixels(mainBack, mainA, 0).maxDiff === 0;
        // 锁定切 B：主预览应等于刚才 peek 到的 B 画面
        root().querySelector('#lut-lab-lock').click();
        var mainLockedB = readMain().slice();
        var lockMatchesPeek = comparePixels(mainLockedB, mainPeek, 0).maxDiff === 0;
        root().querySelector('#lut-lab-lock').click(); // 还原 A
        record('peek-and-lock', peekDiffers && backSame && lockMatchesPeek,
            'peek≠A=' + peekDiffers + '；松开回A=' + backSame + '；锁定B==peek(B)=' + lockMatchesPeek);

        // 9. 胶片条逐档 == 该档单独渲染（±1/255）：mock 集合确定性重取
        var mockSet = await new Promise(function(resolve, reject) {
            window.Bridge.task('lutlab.bakeXmlSet', { mode: '光照' }, function(resp) { resp ? resolve(resp) : reject(new Error('mock bakeXmlSet 无回包')); });
        });
        var filmOk = true;
        var filmMaxDiff = 0;
        var directRenderer = CF7.LutLabRenderer.create();
        var sourcePixels = readSource();
        var sw = dbg().source.width, sh = dbg().source.height;
        for (var lv = 0; lv <= 9; lv++) {
            var bin = atob(mockSet.levels[lv].rgbaBase64);
            var rgba = new Uint8Array(bin.length);
            for (var bi = 0; bi < bin.length; bi++) rgba[bi] = bin.charCodeAt(bi);
            directRenderer.setSource(imageDataOf(sourcePixels, sw, sh));
            directRenderer.setLut({ rgba: rgba });
            directRenderer.render();
            var direct = directRenderer.readPixels();
            var cellCanvas = root().querySelector('.lut-lab-film-cell[data-level="' + lv + '"] canvas');
            var cellCtx = cellCanvas.getContext('2d');
            var cellPixels = cellCtx.getImageData(0, 0, cellCanvas.width, cellCanvas.height).data;
            var cellCmp = comparePixels(cellPixels, direct, 1);
            if (cellCmp.overTolerance > 0) filmOk = false;
            if (cellCmp.maxDiff > filmMaxDiff) filmMaxDiff = cellCmp.maxDiff;
        }
        directRenderer.gl.getExtension('WEBGL_lose_context').loseContext();
        record('filmstrip-matches-levels', filmOk, '胶片条 10 档逐档对照 maxDiff=' + filmMaxDiff + '/255（容差 1）');

        // 10. 扫动启停：等级随时间推进，停止后静止
        var levelBefore = dbg().level;
        root().querySelector('#lut-lab-sweep').click();
        await waitFor(function() { return dbg().level > levelBefore + 0.3; }, 3000, '扫动推进');
        var sweepingLevel = dbg().level;
        root().querySelector('#lut-lab-sweep').click();
        await delay(350);
        var stoppedLevel = dbg().level;
        record('sweep-toggle', Math.abs(stoppedLevel - sweepingLevel) < 0.001 && !dbg().sweeping,
            '扫动推进至 L' + sweepingLevel.toFixed(1) + '，停止后稳定 L' + stoppedLevel.toFixed(1));

        // 11. 帮助界面开关
        root().querySelector('.lut-lab-help-btn').click();
        var helpVisible = root().querySelector('.lut-lab-help').style.display !== 'none'
            && root().querySelector('.lut-lab-help').textContent.indexOf('遮挡策略') >= 0;
        root().querySelector('.lut-lab-help .lut-lab-overlay-close').click();
        var helpClosed = root().querySelector('.lut-lab-help').style.display === 'none';
        record('help-toggle', helpVisible && helpClosed, '帮助开=' + helpVisible + ' 关=' + helpClosed);

        // 12. mock 桥抓帧：源图切换为游戏抓帧，且最近帧入库（持久化链路完整走通）
        root().querySelector('#lut-lab-grab').click();
        await waitFor(function() {
            return root().querySelector('.lut-lab-source-info').textContent.indexOf('游戏抓帧') >= 0;
        }, 10000, '抓帧载入');
        record('grab-mock-loads-frame', !!dbg().lastFrameUrl,
            root().querySelector('.lut-lab-source-info').textContent
            + '；lastFrameUrl 已入库=' + !!dbg().lastFrameUrl);

        // 13. 抽屉：载入 vhost 样品为退化集合 A
        root().querySelector('#lut-lab-drawer-toggle').click();
        var firstSampleAction = await waitFor(function() {
            var btn = root().querySelector('.lut-lab-sample-actions .lut-lab-btn');
            return btn || null;
        }, 5000, '抽屉样品行');
        firstSampleAction.click();
        await waitFor(function() {
            var s = dbg();
            return s.setA && s.setA.indexOf('sample:') === 0
                && s.sets.filter(function(x) { return x.id === s.setA && x.loaded; }).length === 1;
        }, 10000, '退化集合 A 载入');
        record('drawer-select-sample', dbg().drawerOpen === true,
            '抽屉展开 + 退化集合 A=' + dbg().setA.slice(0, 40));

        // 14. 三段式预设工作流：空白 → 恒等锚 L0 + 17³ 锚 L8 → 中点 50/50
        root().querySelector('#lut-lab-preset-new-blank').click();
        await waitFor(function() {
            var s = dbg();
            return s.preset && s.preset.anchors && s.preset.anchors[0] && s.setA === 'preset:edit';
        }, 5000, '空白预设创建');
        // L8 指派 17³ 样品锚：胶片格 [⚓] 武装 → 抽屉点该样品的 [⚓L8]
        root().querySelectorAll('.lut-lab-film-cell[data-level="8"] .lut-lab-film-ops .lut-lab-btn')[1].click();
        var anchorPickBtn = await waitFor(function() {
            var rows = Array.prototype.slice.call(root().querySelectorAll('.lut-lab-sample'));
            var row = null;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].textContent.indexOf('非线性 17³') >= 0) { row = rows[i]; break; }
            }
            return row ? row.querySelector('.lut-lab-sample-actions .lut-lab-btn') : null;
        }, 5000, '17³ 样品锚点按钮');
        anchorPickBtn.click();
        await waitFor(function() {
            var s = dbg();
            return s.preset && s.preset.anchors[8] && s.anchorPickLevel === -1;
        }, 10000, 'L8 锚点指派');
        // 中点 L4 = round((identity + 17³)/2)（节点级，与面板 blendRgba 同语义）
        var lut17 = CF7.LutLabCube.toRgba8(cubeText);
        var identityRgba = CF7.LutLabRenderer.identityRgba8();
        var expectedBlend = new Uint8Array(identityRgba.length);
        for (var bi2 = 0; bi2 < expectedBlend.length; bi2 += 4) {
            expectedBlend[bi2] = Math.round((identityRgba[bi2] + lut17.rgba[bi2]) / 2);
            expectedBlend[bi2 + 1] = Math.round((identityRgba[bi2 + 1] + lut17.rgba[bi2 + 1]) / 2);
            expectedBlend[bi2 + 2] = Math.round((identityRgba[bi2 + 2] + lut17.rgba[bi2 + 2]) / 2);
            expectedBlend[bi2 + 3] = 255;
        }
        var blendRenderer = CF7.LutLabRenderer.create();
        var srcPixelsNow = readSource();
        var srcW = dbg().source.width, srcH = dbg().source.height;
        function renderWithLut(rgba) {
            blendRenderer.setSource(imageDataOf(srcPixelsNow, srcW, srcH));
            blendRenderer.setLut({ rgba: rgba });
            blendRenderer.render();
            return blendRenderer.readPixels();
        }
        var expectedL4 = renderWithLut(expectedBlend);
        var cell4Canvas = root().querySelector('.lut-lab-film-cell[data-level="4"] canvas');
        var cell4Pixels = cell4Canvas.getContext('2d').getImageData(0, 0, cell4Canvas.width, cell4Canvas.height).data;
        var midCmp = comparePixels(cell4Pixels, expectedL4, 0);
        blendRenderer.gl.getExtension('WEBGL_lose_context').loseContext();
        record('preset-anchor-blend-midpoint', midCmp.maxDiff === 0,
            'L0 恒等 + L8 17³ → L4=50/50：胶片格 vs 期望混合 maxDiff=' + midCmp.maxDiff);

        // 15. 边缘 hold：清除 L8 锚后只剩 L0 恒等锚 → 所有等级 hold 恒等（cell1 == cell9 逐像素）
        root().querySelectorAll('.lut-lab-film-cell[data-level="8"] .lut-lab-film-ops .lut-lab-btn')[2].click();
        await waitFor(function() {
            var s = dbg();
            return s.preset && s.preset.anchors.filter(Boolean).length === 1
                && root().querySelector('.lut-lab-film-cell[data-level="9"] canvas');
        }, 5000, 'L8 锚点清除');
        await waitFor(function() {
            return cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, 'hold 后胶片条重渲');
        var cell1Canvas = root().querySelector('.lut-lab-film-cell[data-level="1"] canvas');
        var cell9Canvas = root().querySelector('.lut-lab-film-cell[data-level="9"] canvas');
        var holdCmp = comparePixels(
            cell1Canvas.getContext('2d').getImageData(0, 0, cell1Canvas.width, cell1Canvas.height).data,
            cell9Canvas.getContext('2d').getImageData(0, 0, cell9Canvas.width, cell9Canvas.height).data, 0);
        record('preset-edge-hold', holdCmp.maxDiff === 0,
            '仅 L0 恒等锚 → L1 与 L9 均 hold 恒等（maxDiff=' + holdCmp.maxDiff + '）');

        // 16. 保存 → mock 回包入选择器 → 重载与预览逐像素一致（L4 主预览 vs 期望混合）
        root().querySelector('#lut-lab-preset-name').value = 'qa预设';
        // 恢复 L8 锚点再保存（覆盖混合路径；字节断言直接对 payload）
        root().querySelectorAll('.lut-lab-film-cell[data-level="8"] .lut-lab-film-ops .lut-lab-btn')[1].click();
        var anchorPickBtn2 = await waitFor(function() {
            var rows = Array.prototype.slice.call(root().querySelectorAll('.lut-lab-sample'));
            var row = null;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].textContent.indexOf('非线性 17³') >= 0) { row = rows[i]; break; }
            }
            return row ? row.querySelector('.lut-lab-sample-actions .lut-lab-btn') : null;
        }, 5000, '17³ 样品锚点按钮（二次）');
        anchorPickBtn2.click();
        await waitFor(function() {
            var s = dbg();
            return s.preset && s.preset.anchors[8] && s.anchorPickLevel === -1;
        }, 10000, 'L8 锚点二次指派');
        root().querySelector('#lut-lab-preset-save').click();
        await waitFor(function() {
            return root().querySelector('.lut-lab-statusbar').textContent.indexOf('已保存并进入集合选择器') >= 0;
        }, 10000, '预设保存');
        var savedOk = false;
        var savedBytesOk = false;
        if (window.__lutLabSavedPreset && window.__lutLabSavedPreset.payload) {
            var savedLevels = window.__lutLabSavedPreset.payload.levels;
            if (savedLevels && savedLevels.length === 10) {
                var bin4 = atob(savedLevels[4].rgbaBase64);
                savedBytesOk = bin4.length === expectedBlend.length;
                for (var sb = 0; savedBytesOk && sb < bin4.length; sb++) {
                    if (bin4.charCodeAt(sb) !== expectedBlend[sb]) savedBytesOk = false;
                }
                savedOk = true;
            }
        }
        var savedOption = Array.prototype.find.call(
            root().querySelector('#lut-lab-set-a').options,
            function(o) { return o.textContent.indexOf('预设 · qa预设') >= 0; });
        record('preset-save-reload', savedOk && savedBytesOk && !!savedOption,
            'mock 保存回包 L4 字节==期望混合=' + savedBytesOk + '；选择器含「预设 · qa预设」=' + !!savedOption);

        // 17. 主预览缩放显示切换（320×180 测试图放大的平滑/最近邻）
        var viewCanvas = root().querySelector('.lut-lab-view-canvas');
        root().querySelector('#lut-lab-pixel-toggle').click();
        var pixelOn = viewCanvas.classList.contains('pixelated');
        root().querySelector('#lut-lab-pixel-toggle').click();
        var pixelOff = !viewCanvas.classList.contains('pixelated');
        record('display-scaling-toggle', pixelOn && pixelOff,
            '缩放切换 平滑→最近邻=' + pixelOn + ' →平滑=' + pixelOff);

        // 18. 布局：无横向滚动条、面板不溢出、胶片条十格可见
        var de = document.documentElement;
        var panelEl = root();
        var filmCells = panelEl.querySelectorAll('.lut-lab-film-cell');
        var minCellW = 9999;
        filmCells.forEach(function(c2) { minCellW = Math.min(minCellW, c2.clientWidth); });
        var noHScroll = de.scrollWidth <= window.innerWidth + 1;
        var noVOverflow = panelEl.scrollHeight <= panelEl.clientHeight + 1;
        record('layout-no-overflow', noHScroll && noVOverflow && filmCells.length === 10 && minCellW >= 30,
            'viewport=' + window.innerWidth + '×' + window.innerHeight
            + '；scrollWidth=' + de.scrollWidth + '；panelScrollH=' + panelEl.scrollHeight + '/' + panelEl.clientHeight
            + '；胶片格 minW=' + minCellW);
    }

    async function phaseReopen() {
        // 重开循环（2026-09-24 真机事故回归：二次 open 黑壳 + 关闭按钮失效）。
        // harness Panels 桩与生产同契约：close 保留 _el/DOM，reopen 跳过 create 直跑 onOpen。
        var elBefore = spec()._el;
        window.__lutLabHarness.close();
        record('reopen-retains-dom', spec()._el === elBefore && !!spec()._el,
            'close 后 _el ' + (spec()._el === elBefore && spec()._el ? '保留（生产 panels.js 契约）' : '被拆除（偏离生产契约）'));

        for (var round = 1; round <= 2; round++) {
            window.__lutLabHarness.open();
            await waitFor(function() {
                var s = dbg();
                var xml = s && s.sets.filter(function(x) { return x.id === 'xml:光照'; })[0];
                return xml && xml.loaded && cellCanvasesNonblank('.lut-lab-film-cell', 10);
            }, 10000, '第 ' + round + ' 次重开胶片条渲染');
            if (round === 1) window.__lutLabHarness.close();
        }
        record('reopen-grid-renders', true,
            '两轮重开后胶片条 cells=' + root().querySelectorAll('.lut-lab-film-cell').length + ' 且像素抽样非全黑');

        // 重开后恒等集合主预览 == 源图逐像素（渲染器 GL 重建后真的工作）
        selectSet('A', function(o) { return o.textContent.indexOf('恒等') >= 0; });
        await waitFor(function() {
            var s = dbg();
            return s.setA && s.setA.indexOf('恒等') >= 0
                && s.sets.filter(function(x) { return x.id === s.setA && x.loaded; }).length === 1;
        }, 10000, '重开后恒等集合载入');
        var reopenCmp = comparePixels(readMain(), readSource(), 0);
        record('reopen-identity-exact', reopenCmp.maxDiff === 0,
            '重开后恒等集合 主预览 vs 源图 maxDiff=' + reopenCmp.maxDiff);

        // 重开后关闭按钮仍发 {type:'panel',cmd:'close'}（事故时该按钮失效）
        window.__lutLabSent = [];
        root().querySelector('.lut-lab-close').click();
        await waitFor(function() {
            return (window.__lutLabSent || []).some(function(m) {
                return m && m.type === 'panel' && m.cmd === 'close' && m.panel === 'lut-lab';
            });
        }, 5000, '重开后关闭按钮发 close 消息');
        record('reopen-close-button', true, '关闭按钮仍发 panel close（Host 可关闭面板）');

        // 第三次打开：WebGL 徽章恢复 ok（渲染器被重建，而非沿用 close 时 lose 的死 context）
        window.__lutLabHarness.open();
        await waitFor(function() {
            return root() && root().getAttribute('data-webgl') === 'ok'
                && cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, '第三次打开 WebGL 重建');
        record('reopen-webgl-rebuilt', true, 'data-webgl=' + root().getAttribute('data-webgl'));
    }

    async function phaseB() {
        // 降级路径：桥 off + vhost 不可达 → 重新打开面板
        window.__lutLabHarness.setBridgeMode('off');
        window.__lutLabHarness.setVhostBase('/vhost-missing');
        window.__lutLabHarness.reopen();

        await waitFor(function() {
            return root() && root().getAttribute('data-vhost') === 'degraded';
        }, 10000, '降级状态到位');

        var s = dbg();
        var fixtureOnly = s.samples === 3;
        record('degraded-vhost-fixtures', fixtureOnly,
            'samples=' + s.samples + ' 全 fixture=' + fixtureOnly + '；data-vhost=' + root().getAttribute('data-vhost'));

        // XML 集合：桥 off 且 vhost 预烘焙也不可达 → 标记不可用并回退 fixture 集合
        await waitFor(function() {
            return dbg().xmlSet === 'unavailable';
        }, 10000, 'XML 集合降级');
        var sB = dbg();
        record('degraded-xml-set-unavailable', sB.xmlSet === 'unavailable'
                && sB.setA && sB.setA.indexOf('sample:fixture:') === 0,
            'xmlSet=' + sB.xmlSet + '；A 回退=' + sB.setA);

        var grabBtn = root().querySelector('#lut-lab-grab');
        var grabHint = root().querySelector('#lut-lab-grab-hint').textContent;
        record('degraded-bridge-disabled',
            grabBtn.disabled && grabHint.length > 0,
            '抓帧已禁用并给出原因');

        await waitFor(function() {
            return cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, '降级态胶片条渲染');
        record('degraded-grid-renders', true,
            '降级态胶片条 cells=' + root().querySelectorAll('.lut-lab-film-cell').length);
    }

    async function phasePersist() {
        // 工作台持久化三件套（localStorage：cf7.lutlab.workbench.v1）
        // 恢复桥与 vhost 后重开面板
        window.__lutLabHarness.setBridgeMode('mock');
        window.__lutLabHarness.setVhostBase('/vhost');
        window.__lutLabHarness.reopen();
        await waitFor(function() {
            return root().getAttribute('data-vhost') === 'ok'
                && cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, '持久化用例前置：面板恢复可用');

        // ① 配置状态 → 关闭 → 重开 → 逐字段恢复
        root().querySelector('#lut-lab-preset-name').value = 'persist-预设';
        root().querySelector('.lut-lab-mode button[data-mode="夜视"]').click();
        root().querySelector('#lut-lab-level').value = '3.7';
        root().querySelector('#lut-lab-level').dispatchEvent(new Event('input', { bubbles: true }));
        root().querySelector('.lut-lab-view button[data-view="split"]').click();
        if (!dbg().drawerOpen) root().querySelector('#lut-lab-drawer-toggle').click();
        // 集合 B 经抽屉 [→B] 换为 17³ 样品退化集合（同时验证样品引用的跨关闭重建路径）
        var sampleRowBtn = await waitFor(function() {
            var rows = Array.prototype.slice.call(root().querySelectorAll('.lut-lab-sample'));
            var row = null;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].textContent.indexOf('非线性 17³') >= 0) { row = rows[i]; break; }
            }
            if (!row) return null;
            var btns = row.querySelectorAll('.lut-lab-sample-actions .lut-lab-btn');
            return btns.length >= 2 ? btns[1] : null;
        }, 5000, '17³ 样品 [→B] 按钮');
        sampleRowBtn.click();
        await waitFor(function() {
            return dbg().setB && dbg().setB.indexOf('sample:generated') === 0;
        }, 10000, '集合 B 换样品');
        root().querySelector('#lut-lab-grab').click();
        await waitFor(function() {
            return root().querySelector('.lut-lab-source-info').textContent.indexOf('游戏抓帧') >= 0;
        }, 10000, '手动抓帧入库');
        window.__lutLabHarness.close();
        window.__lutLabHarness.open();
        // restoreSetSelection 在 Promise.all(集合/样品清单) 后异步执行；
        // restoredSelection 是恢复完成的确定性信号，避免与胶片条渲染竞态
        await waitFor(function() {
            var s = dbg();
            var xml = s && s.sets.filter(function(x) { return x.id === 'xml:夜视'; })[0];
            return xml && xml.loaded && s.restoredSelection === true
                && cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 15000, '持久化重开后渲染+恢复完成');
        var s1 = dbg();
        var nameInput = root().querySelector('#lut-lab-preset-name');
        record('persist-restore-cycle',
            s1.mode === '夜视'
            && Math.abs(s1.level - 3.7) < 0.001
            && s1.view === 'split'
            && s1.drawerOpen === true
            && s1.setB.indexOf('sample:generated') === 0
            && nameInput.value === 'persist-预设',
            '恢复字段：mode=' + s1.mode + ' level=' + s1.level + ' view=' + s1.view
            + ' drawer=' + s1.drawerOpen + ' setB=' + String(s1.setB).slice(0, 30)
            + ' preset=' + nameInput.value);

        // ② 上次抓帧恢复显示（入场帧为异步加载，等标签到位再断言）
        await waitFor(function() {
            var s = dbg();
            return s.source && s.source.label && s.source.label.indexOf('抓帧') >= 0;
        }, 10000, '上次抓帧异步载入');
        s1 = dbg();
        record('persist-last-frame',
            s1.source && s1.source.label.indexOf('抓帧') >= 0 && s1.source.label.indexOf('内置测试图') < 0,
            '重开后源图=' + (s1.source ? s1.source.label : '(无)'));

        // ③ 失效引用回退：写坏持久化引用后重开，应回退默认并提示
        localStorage.setItem('cf7.lutlab.workbench.v1', JSON.stringify({
            schemaVersion: 1,
            setAId: 'set:不存在-A',
            setBId: 'set:不存在-B',
            mode: '光照',
            level: 5,
            view: 'single',
            drawerOpen: false,
            presetName: '',
            lastFrameUrl: null,
            lastFrameLabel: ''
        }));
        window.__lutLabHarness.close();
        window.__lutLabHarness.open();
        await waitFor(function() {
            var s = dbg();
            var xml = s && s.sets.filter(function(x) { return x.id === 'xml:光照'; })[0];
            return xml && xml.loaded && s.restoredSelection === true
                && cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 15000, '失效回退重开后渲染+恢复完成');
        // restoreSetSelection 经 Promise.all 链在渲染后才执行，回退警告异步到达；
        // 等警告出现再读状态（waitFor 返回命中时刻的文本，避免后续状态消息覆盖）
        var warnText = await waitFor(function() {
            var t = root().querySelector('.lut-lab-statusbar').textContent;
            return /已删除|回退/.test(t) ? t : null;
        }, 15000, '失效引用回退提示');
        var s2 = dbg();
        record('persist-invalid-fallback',
            s2.setA === 'xml:光照'
            && s2.setB !== 'set:不存在-B'
            && /已删除|回退/.test(warnText),
            '失效引用回退：setA=' + s2.setA + ' setB=' + String(s2.setB).slice(0, 30)
            + '；提示=' + warnText.slice(0, 50));
    }

    // Spatial fluorescence cannot be encoded by a colour LUT. Verify its GPU
    // properties independently, then exercise the actual workbench controls.
    async function phaseFluorescent() {
        var renderer = CF7.LutLabRenderer.create();
        var w = 128, h = 96;
        var image = new ImageData(w, h);
        for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
            var i = (y * w + x) * 4;
            var v = x >= 22 && x < 74 && y >= 8 && y < 34 ? 230 : 30;
            image.data[i] = image.data[i + 1] = image.data[i + 2] = v;
            image.data[i + 3] = 255;
        }
        var identity = { rgba: CF7.LutLabRenderer.identityRgba8() };
        renderer.setSource(image, w, h, 1);
        renderer.setDualLut(identity, identity, identity, identity);
        renderer.setView('B');
        renderer.render();
        var plainB = renderer.readPixels();
        renderer.setFluorescent({ enabled: true, strength: 0 });
        renderer.render();
        record('fluorescent-zero-bypass', comparePixels(renderer.readPixels(), plainB, 0).maxDiff === 0,
            '强度 0 与未启用 B 逐像素相同');
        renderer.setFluorescent({ enabled: true, only: true, width: 1, halo: 0 });
        renderer.setView('A');
        renderer.render();
        record('fluorescent-preserves-a', comparePixels(renderer.readPixels(), image.data, 0).maxDiff === 0,
            '启用荧光后 A 仍为恒等输出');
        renderer.setView('B');
        renderer.render();
        var core = renderer.readPixels();
        function greenSum(pixels, fromY, toY) {
            var sum = 0;
            for (var yy = fromY; yy < toY; yy++) for (var xx = 16; xx < 80; xx++)
                sum += Math.max(0, pixels[(yy * w + xx) * 4 + 1] - 8);
            return sum;
        }
        var top = greenSum(core, 3, 40), mirrored = greenSum(core, 56, 93);
        record('fluorescent-contour-orientation', top > 10000 && mirrored < top / 10,
            '上方物体轮廓=' + top + '；镜像空白=' + mirrored);
        renderer.setView('split', .5);
        renderer.render();
        var splitExpected = plainB.slice();
        for (var sy = 0; sy < h; sy++) for (var sx = w / 2; sx < w; sx++) {
            var si = (sy * w + sx) * 4;
            splitExpected.set(core.subarray(si, si + 4), si);
        }
        var splitCmp = comparePixels(renderer.readPixels(), splitExpected, 1);
        renderer.setView('diff');
        renderer.render();
        var diffExpected = plainB.slice();
        for (var di = 0; di < diffExpected.length; di += 4) for (var dc = 0; dc < 3; dc++)
            diffExpected[di + dc] = Math.min(255, Math.abs(plainB[di + dc] - core[di + dc]) * 4);
        var diffCmp = comparePixels(renderer.readPixels(), diffExpected, 3);
        record('fluorescent-ab-views', splitCmp.overTolerance === 0 && diffCmp.overTolerance === 0,
            '分屏左右与单图一致，差值×4 与 CPU 对照一致；maxDiff=' + splitCmp.maxDiff + '/' + diffCmp.maxDiff);
        renderer.setView('B');
        renderer.setFluorescent({ enabled: true, only: true, width: 1, halo: 1, radius: 4 });
        renderer.render();
        var glowing = renderer.readPixels(), haloPixels = 0;
        for (var p = 0; p < core.length; p += 4)
            if (core[p + 1] <= 9 && glowing[p + 1] >= 15) haloPixels++;
        record('fluorescent-halo-surrounds-core', haloPixels > 100,
            '核心线外新增光晕像素=' + haloPixels);
        renderer.setFluorescent({ enabled: true, retention: 0 });
        renderer.render();
        var zeroUnderlay = renderer.readPixels();
        renderer.setFluorescent({ enabled: true, only: true, retention: 1 });
        renderer.render();
        record('fluorescent-only-equals-zero-underlay',
            comparePixels(renderer.readPixels(), zeroUnderlay, 0).maxDiff === 0,
            '只看荧光与底图 0% 逐像素相同');

        // A flat field has no structural edge; its centre should be the stated
        // mixture of the dark floor and the chosen B LUT, without a false glow.
        var flat = new ImageData(81, 53), constant = identity.rgba.slice();
        for (var f = 0; f < flat.data.length; f += 4) {
            flat.data[f] = flat.data[f + 1] = flat.data[f + 2] = 80;
            flat.data[f + 3] = 255;
        }
        for (var c = 0; c < constant.length; c += 4) {
            constant[c] = 20; constant[c + 1] = 160; constant[c + 2] = 60;
        }
        renderer.setSource(flat, 81, 53, 2);
        renderer.setDualLut(identity, identity, { rgba: constant }, { rgba: constant });
        renderer.setFluorescent({ enabled: true, retention: .15 });
        renderer.render();
        var flatLut = renderer.readPixels();
        var expected = [.016 * 255 * .85 + 20 * .15, .032 * 255 * .85 + 160 * .15, .029 * 255 * .85 + 60 * .15];
        var mixtureDiff = Math.max.apply(null, expected.map(function(v, n) { return Math.abs(flatLut[n] - Math.round(v)); }));
        record('fluorescent-selected-lut-underlay', mixtureDiff <= 1,
            '无边缘色块使用 B LUT 的 15% 底色，maxDiff=' + mixtureDiff);
        renderer.setFluorescent({ enabled: true, retention: .15, base: 'original' });
        renderer.render();
        var original = renderer.readPixels();
        var originalDiff = Math.max.apply(null, [.016, .032, .029].map(function(v, n) {
            return Math.abs(original[n] - Math.round(v * 255 * .85 + 80 * .15));
        }));
        record('fluorescent-original-underlay', originalDiff <= 1 && comparePixels(original, flatLut, 0).maxDiff > 5,
            '切换原图底色生效，maxDiff=' + originalDiff);
        renderer.setFluorescent({ enabled: true, only: true });
        renderer.render();
        var flatOnly = renderer.readPixels(), maxFlat = 0;
        for (var fp = 0; fp < flatOnly.length; fp += 4)
            maxFlat = Math.max(maxFlat, flatOnly[fp], flatOnly[fp + 1], flatOnly[fp + 2]);
        record('fluorescent-flat-field-and-resize', maxFlat <= 9 && renderer.gl.getError() === renderer.gl.NO_ERROR,
            '换尺寸后无假边缘/GL 错误；平场最大值=' + maxFlat);
        for (var rp = 0; rp < flat.data.length; rp += 4)
            flat.data[rp] = flat.data[rp + 1] = flat.data[rp + 2] = 120;
        renderer.setSource(flat, 81, 53, 3);
        renderer.setFluorescent({ enabled: true, retention: 1, base: 'original' });
        renderer.render();
        record('fluorescent-source-revision', comparePixels(renderer.readPixels(), flat.data, 0).maxDiff === 0,
            '同一源对象的新代际可刷新，不误复用旧像素');
        renderer.dispose();

        var oldEnabled = root().querySelector('#lut-lab-fx-enabled').checked;
        record('fluorescent-old-state-default-off', !oldEnabled,
            '旧版持久化字段缺少荧光参数时默认关闭');
        var level = dbg().level;
        root().querySelector('#lut-lab-fluorescent-preset').click();
        await waitFor(function() {
            var s = dbg();
            return s.mode === '夜视' && s.setA === 'xml:夜视' && s.setB === 'xml:夜视'
                && s.sets.some(function(set) { return set.id === 'xml:夜视' && set.loaded; })
                && cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, '荧光夜视预设加载');
        record('fluorescent-quick-preset', dbg().level === level && dbg().locked === 'B'
            && root().getAttribute('data-fluorescent') === 'on'
            && root().querySelector('#lut-lab-fx-retention').value === '0.15'
            && root().querySelector('#lut-lab-fx-width').value === '2.2',
            '现有 XML 夜视 A/B；B 荧光；底图 15%、线宽 2.2；保留 L' + level);
        root().querySelector('.lut-lab-view button[data-view="single"]').click();
        var mainB = readMain().slice();
        var cell = root().querySelector('.lut-lab-film-cell[data-level="' + level + '"] canvas');
        var filmPixels = cell.getContext('2d').getImageData(0, 0, cell.width, cell.height).data;
        var filmCmp = comparePixels(mainB, filmPixels, 1);
        record('fluorescent-main-film-consistency', filmCmp.overTolerance === 0,
            '主预览保留所选 L' + level + '，与对应荧光胶片格 maxDiff=' + filmCmp.maxDiff);
        root().querySelector('#lut-lab-lock').click();
        var mainA = readMain().slice();
        record('fluorescent-visible-on-b', comparePixels(mainB, mainA, 0).maxDiff > 20,
            'A/B 画面有显著差异');
        root().querySelector('#lut-lab-lock').click();
        root().querySelector('.lut-lab-stage').dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
        root().querySelector('.lut-lab-stage').dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
        var surfaces = root().querySelectorAll('.lut-lab-inspect-target canvas');
        var inspectOk = dbg().inspectOpen && surfaces.length === 2;
        if (inspectOk) {
            var a = surfaces[0], b = surfaces[1];
            inspectOk = comparePixels(a.getContext('2d').getImageData(0, 0, a.width, a.height).data, mainA, 0).maxDiff === 0
                && comparePixels(b.getContext('2d').getImageData(0, 0, b.width, b.height).data, mainB, 0).maxDiff === 0
                && comparePixels(readMain(), mainB, 0).maxDiff === 0;
        }
        record('fluorescent-inspector-consistency', inspectOk,
            '联动检视 A/B 与主预览逐像素一致，检视烘焙后主预览恢复');
        root().querySelector('.lut-lab-inspect .lut-lab-overlay-close').click();
        var retention = root().querySelector('#lut-lab-fx-retention');
        retention.value = '.23'; retention.dispatchEvent(new Event('input', { bubbles: true }));
        window.__lutLabHarness.reopen();
        await waitFor(function() {
            return dbg().restoredSelection && root().getAttribute('data-fluorescent') === 'on'
                && cellCanvasesNonblank('.lut-lab-film-cell', 10);
        }, 10000, '荧光参数重开恢复');
        record('fluorescent-persistence', root().querySelector('#lut-lab-fx-retention').value === '0.23'
            && root().querySelector('#lut-lab-fx-enabled').checked,
            '关闭再重开后荧光开启及底图 23% 恢复');
        root().querySelector('.lut-lab-mode button[data-mode="光照"]').click();
        record('fluorescent-inactive-in-lighting', root().getAttribute('data-fluorescent') === 'off',
            '光照模式不应用夜视荧光层');
    }

    async function phaseStructureEdges() {
        var renderer=CF7.LutLabRenderer.create(),w=384,h=256,image=new ImageData(w,h),seed=12345;
        for(var y=0;y<h;y++)for(var x=0;x<w;x++){
            seed=(Math.imul(seed,1664525)+1013904223)>>>0;
            var value=x<128?40+((seed>>>24)%100):(x<256?((x%8<2||y%8<2)?185:35):(x<310?35:150));
            if(x>=266&&x<299&&Math.abs(y-60-(x-266)/2)<2)value=210;
            var i=(y*w+x)*4;
            image.data[i]=image.data[i+1]=image.data[i+2]=value;image.data[i+3]=255;
        }
        var identity={rgba:CF7.LutLabRenderer.identityRgba8()};
        renderer.setSource(image,w,h,1);renderer.setDualLut(identity,identity,identity,identity);renderer.setView('B');
        renderer.setFluorescent({enabled:true,only:true,strength:1,width:1,halo:0,suppression:0});renderer.render();
        var raw=renderer.readPixels();
        renderer.setFluorescent({enabled:true,only:true,strength:1,width:1,halo:0,suppression:.72});renderer.render();
        var structure=renderer.readPixels();
        function region(pixels,x0,y0,rw,rh){
            var sum=0;for(var yy=y0;yy<y0+rh;yy++)for(var xx=x0;xx<x0+rw;xx++)sum+=Math.max(0,pixels[(yy*w+xx)*4+1]-8);
            return sum/(rw*rh);
        }
        var gravel=region(structure,16,16,96,220)/region(raw,16,16,96,220);
        var mesh=region(structure,144,16,96,220)/region(raw,144,16,96,220);
        record('structure-gravel-suppression',gravel<.12,'碎石边缘能量保留='+gravel.toFixed(3));
        record('structure-connected-mesh-suppression',mesh<.20,'连通网格边缘能量保留='+mesh.toFixed(3));
        var boundaryRows=0;
        for(y=20;y<236;y++){
            var peak=0;for(x=308;x<313;x++)peak=Math.max(peak,structure[(y*w+x)*4+1]);
            if(peak>80)boundaryRows++;
        }
        record('structure-boundary-continuity',boundaryRows>=211,'大结构连续行='+boundaryRows+'/216');
        record('structure-thin-stroke',region(structure,266,55,33,30)>4,'细斜线仍可见');
        renderer.setFluorescent({enabled:true,only:true,strength:1,width:1,halo:0,suppression:0});renderer.render();
        record('structure-zero-restores-raw',comparePixels(raw,renderer.readPixels(),0).maxDiff===0&&renderer.gl.getError()===renderer.gl.NO_ERROR,
            '抑制归零恢复原始细节检测，未产生 GL 错误');
        function deviation(pixels){
            var sum=0,squares=0,n=96*220;
            for(var yy=16;yy<236;yy++)for(var xx=16;xx<112;xx++){
                var value=pixels[(yy*w+xx)*4+1];sum+=value;squares+=value*value;
            }
            return Math.sqrt(Math.max(0,squares/n-(sum/n)*(sum/n)));
        }
        renderer.setFluorescent({enabled:true,denoise:true,strength:0,retention:.96,suppression:0,color:'#ffffff'});renderer.render();
        var rawUnderlay=renderer.readPixels();
        renderer.setFluorescent({enabled:true,denoise:true,strength:0,retention:.96,suppression:.9,color:'#ffffff'});renderer.render();
        var filteredUnderlay=renderer.readPixels(),noiseRatio=deviation(filteredUnderlay)/deviation(rawUnderlay);
        record('underlay-grain-suppression',noiseRatio<.40,'无环境描边时底图噪点标准差保留='+noiseRatio.toFixed(3));
        renderer.setView('A');renderer.render();
        record('underlay-preserves-a',comparePixels(image.data,renderer.readPixels(),0).maxDiff===0,'底图去纹理仍只改变 B');
        renderer.setView('B');renderer.setFluorescent({enabled:true,denoise:true,strength:0,retention:.96,suppression:0,color:'#ffffff'});renderer.render();
        record('underlay-zero-restores-texture',comparePixels(rawUnderlay,renderer.readPixels(),0).maxDiff===0,'纹理抑制归零恢复底图');
        record('underlay-gl-clean',renderer.gl.getError()===renderer.gl.NO_ERROR,'填色型去纹理路径没有 GL 错误');
        renderer.dispose();
    }

    async function phaseInstrument() {
        var canvas=document.createElement('canvas');canvas.width=512;canvas.height=576;
        var context=canvas.getContext('2d');context.fillStyle='#808080';context.fillRect(0,0,512,576);
        var original=context.getImageData(0,0,512,576).data;
        var renderer=CF7.LutLabRenderer.create();renderer.setSource(canvas);renderer.setDualLut(null,null,null,null);renderer.setView('B');
        renderer.setFluorescent({enabled:true,strength:0,retention:1,suppression:0,scanStrength:.065});renderer.setScanPhase(0);renderer.render();
        var first=renderer.readPixels(),minimum=255,maximum=0,rows=true;
        for(var y=0;y<576;y++)for(var x=0;x<512;x++){
            var value=first[(y*512+x)*4];minimum=Math.min(minimum,value);maximum=Math.max(maximum,value);
            rows=rows && value===first[(y*512)*4];
        }
        record('instrument-bounded-contrast',maximum-minimum>=6 && minimum>=123 && maximum<=133,'扫描细纹明暗范围='+minimum+'..'+maximum);
        record('instrument-regular-rows',rows,'规整水平细纹，不生成随机颗粒');
        record('instrument-shared-cycle',CF7.LutLabRenderer.scanCycleMs===7000,'工具台从原生 Stage 生成七秒扫描周期');
        renderer.setScanPhase(.5/7);renderer.render();var drifted=renderer.readPixels(),drift=0;
        for(var y=400;y<450;y++)drift=Math.max(drift,Math.abs(drifted[y*512*4]-first[y*512*4]));
        record('instrument-drifting-rows',drift>=2,'扫描带之外的细纹也缓慢移动，差值='+drift);
        renderer.setScanPhase(2/7);renderer.render();var swept=renderer.readPixels(),peak=0,peakY=0,trail=0,ahead=0;
        for(var y=0;y<576;y++)if(swept[y*512*4]>peak){peak=swept[y*512*4];peakY=y;}
        for(var y=peakY-65;y<peakY-25;y++)trail+=swept[y*512*4]/40;
        for(var y=peakY+25;y<peakY+65;y++)ahead+=swept[y*512*4]/40;
        record('instrument-descending-front',peak>=147 && peak<=163 && peakY>=166 && peakY<=184,'两秒时扫描前沿 y='+peakY+'，局部峰值='+peak);
        record('instrument-soft-trail',trail>ahead+3 && trail<140 && ahead>=127 && ahead<=129,'拖尾柔和渐淡='+trail.toFixed(2)+'，前方='+ahead.toFixed(2));
        renderer.setScanPhase(1);renderer.render();
        record('instrument-seamless-wrap',comparePixels(first,renderer.readPixels(),0).maxDiff===0,'完整周期回到起点，没有全屏亮度跳变');
        renderer.setView('A');renderer.render();
        record('instrument-preserves-a',comparePixels(original,renderer.readPixels(),0).maxDiff===0,'A 原画参考保持不变');
        renderer.setView('B');renderer.setFluorescent({enabled:true,strength:0,retention:1,scanStrength:0});renderer.render();
        record('instrument-zero-bypass',comparePixels(original,renderer.readPixels(),0).maxDiff===0,'扫描归零逐像素恢复原画');
        canvas.width=128;canvas.height=96;context=canvas.getContext('2d');context.fillStyle='#808080';context.fillRect(0,0,128,96);
        renderer.setSource(canvas);renderer.setScanPhase(0);renderer.setFluorescent({enabled:true,strength:0,retention:1,scanStrength:.065});renderer.render();
        record('instrument-small-view-antialias',comparePixels(context.getImageData(0,0,128,96).data,renderer.readPixels(),0).maxDiff===0,'细纹低于采样极限时平滑淡出');
        context.fillStyle='#000000';context.fillRect(0,0,128,96);renderer.setSource(canvas,undefined,undefined,'black-ink');
        renderer.setScanPhase(2/7);renderer.setFluorescent({enabled:true,strength:0,retention:1,scanStrength:.08});renderer.render();
        record('instrument-preserves-ink',comparePixels(context.getImageData(0,0,128,96).data,renderer.readPixels(),0).maxDiff===0,'强扫描前沿也不向纯黑线稿添加亮点');
        record('instrument-gl-clean',renderer.gl.getError()===renderer.gl.NO_ERROR,'共享仪器纹理 GLSL 编译与执行无错误');
        renderer.dispose();
    }
    async function phaseVisionPresets() {
        var select = root().querySelector('#lut-lab-vision-preset');
        await waitFor(function() {return select.options.length===8;},5000,'七档设备预设');
        record('night-presets-catalog', !select.disabled && select.options.length===8,'七档源 XML 预设＋手动调节');
        select.value='浅红夜视仪';select.dispatchEvent(new Event('change',{bubbles:true}));
        await waitFor(function() {return dbg().setB==='xml:浅红夜视仪' && root().querySelector('#lut-lab-fx-strength').value==='0';},10000,'红外目标预设');
        record('night-preset-target-role', root().querySelector('#lut-lab-fx-retention').value==='0.96','白热目标型不加环境轮廓');
        select.value='高级夜视仪';select.dispatchEvent(new Event('change',{bubbles:true}));
        await waitFor(function() {return dbg().setB==='xml:高级夜视仪' && root().querySelector('#lut-lab-fx-strength').value==='0';},10000,'冷青扫描预设');
        record('night-preset-balanced-role',root().querySelector('#lut-lab-fx-retention').value==='0.98','自然型保留配色和暗部层次，不加环境线');
        record('night-preset-instrument',root().querySelector('#lut-lab-fx-scanStrength').value==='0.065','幻影读取 XML 中的 6.5% 仪器扫描强度');
        await waitFor(function(){return dbg().instrumentAnimating && dbg().scanPhase>0;},5000,'幻影扫描动画');
        record('night-preset-instrument-animation',dbg().instrumentAnimating && dbg().scanPhase>0,'扫描单独刷新主预览，不重烘胶片条或调色集合');
        window.__lutLabHarness.reopen();
        await waitFor(function() {return dbg().restoredSelection && root().querySelector('#lut-lab-vision-preset').value==='高级夜视仪';},10000,'设备预设重开恢复');
        record('night-preset-persistence',dbg().setB==='xml:高级夜视仪'
            && root().querySelector('.lut-lab-mode button[data-mode="夜视"]').getAttribute('aria-pressed')==='true'
            && root().querySelector('#lut-lab-fx-scanStrength').value==='0.065',
            '命名 XML 集合、模式标记与参数跨关闭恢复');
        select=root().querySelector('#lut-lab-vision-preset');select.value='剑圣视觉四阶';select.dispatchEvent(new Event('change',{bubbles:true}));
        await waitFor(function() {return dbg().setB==='xml:剑圣视觉四阶' && root().querySelector('#lut-lab-fx-strength').value==='0';},10000,'真实视觉');
        record('night-preset-true-vision',root().querySelector('#lut-lab-fx-retention').value==='1'
            && root().querySelector('#lut-lab-fx-scanStrength').value==='0' && !dbg().instrumentAnimating,'真实视觉不加轮廓或扫描纹理');
        var strength=root().querySelector('#lut-lab-fx-strength');strength.value='.3';strength.dispatchEvent(new Event('input',{bubbles:true}));
        record('night-preset-manual-override',select.value==='','人工调节清除预设名称');
    }
    window.addEventListener('DOMContentLoaded', function() {
        (async function() {
            try {
                // Only this explicitly requested test page resets its own state.
                localStorage.removeItem('cf7.lutlab.workbench.v1');
                await phaseA();
                await phaseReopen();
                await phaseB();
                await phasePersist();
                await phaseFluorescent();
                await phaseStructureEdges();
                await phaseInstrument();
                await phaseVisionPresets();
            } catch (e) {
                record('qa-fatal', false, e && e.message ? e.message : String(e));
            }
            window.__LUTLAB_QA_RESULTS__ = results;
            var passed = results.length > 0 && results.every(function(r) { return r.pass; });
            document.documentElement.setAttribute('data-lutlab-qa', passed ? 'passed' : 'failed');
        })();
    });
})();
