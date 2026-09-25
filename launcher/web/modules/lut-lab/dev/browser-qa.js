/**
 * LUT 实验室 v2 harness 页面内 QA（?qa=1 时运行）。
 *
 * 覆盖：WebGL2 可用性、XML 集合 10 档加载、胶片条十格渲染、identity 逐像素恒等、
 * 已知 17³ LUT GPU vs CPU 对照、样品清单合并、A==B 差值纯黑、peek/锁定切换渲染正确集合、
 * 胶片条逐档与单独渲染一致（±1/255）、扫动启停、帮助开关、抽屉退化集合载入、
 * 布局无横向滚动/溢出、入场帧缺省回退、重开回归（生产 close 契约）、双降级路径。
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

    window.addEventListener('DOMContentLoaded', function() {
        (async function() {
            try {
                await phaseA();
                await phaseReopen();
                await phaseB();
                await phasePersist();
            } catch (e) {
                record('qa-fatal', false, e && e.message ? e.message : String(e));
            }
            window.__LUTLAB_QA_RESULTS__ = results;
            var passed = results.length > 0 && results.every(function(r) { return r.pass; });
            document.documentElement.setAttribute('data-lutlab-qa', passed ? 'passed' : 'failed');
        })();
    });
})();
