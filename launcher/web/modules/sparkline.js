/**
 * SparklineRenderer - 帧率迷你图 + 展开详细图
 *
 * 职责：
 * - DPR-aware canvas 管理（含运行时 DPI 切换）
 * - 光照离屏缓存
 * - FPS 曲线绘制（分段着色 / 渐变填充 / 末端光晕 / 危险区 / 参考线）
 * - LOD 降级（L3 简化模式）
 * - 曲线过渡动画（lerp 旧→新）
 * - 悬停 tooltip 命中测试
 * - 展开大图渲染（含 P1/P5 low 标注）
 * - 面积分区着色（绿/黄/红）
 */
var SparklineRenderer = (function() {
    'use strict';

    // ── 常量 ──
    var DANGER_FPS = 18;
    var TARGET_FPS = 26;
    var MIN_DIFF   = 5;
    var MAX_LIGHT  = 9;
    var ANIM_FRAMES = 1; // 高频 FPS 推送下只做 1 帧过渡，避免 rAF 常驻

    // ── DPR-aware canvas 工具 ──
    function currentDpr() { return window.devicePixelRatio || 1; }

    function setupHiDpi(canvas, cssW, cssH) {
        var dpr = currentDpr();
        canvas.width  = cssW * dpr;
        canvas.height = cssH * dpr;
        canvas.style.width  = cssW + 'px';
        canvas.style.height = cssH + 'px';
        var ctx = canvas.getContext('2d');
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        return ctx;
    }

    // ── FPS 颜色插值 ──
    function fpsColor(fps, alpha) {
        var r, g, b;
        if (fps >= 25) { r = 100; g = 255; b = 100; }
        else if (fps >= DANGER_FPS) {
            var t = (fps - DANGER_FPS) / 7;
            r = Math.round(255 - 155 * t);
            g = Math.round(200 + 55 * t);
            b = Math.round(100 * t);
        } else {
            var t2 = Math.max(0, fps / DANGER_FPS);
            r = 255; g = Math.round(200 * t2); b = 0;
        }
        return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
    }

    // ── 坐标计算 ──
    function calcYScale(pts) {
        var n = pts.length;
        var minV = pts[0], maxV = pts[0];
        for (var i = 1; i < n; i++) {
            if (pts[i] < minV) minV = pts[i];
            if (pts[i] > maxV) maxV = pts[i];
        }
        if (maxV - minV < MIN_DIFF) {
            var delta = (MIN_DIFF - (maxV - minV)) / 2;
            minV -= delta; maxV += delta;
        }
        var range = maxV - minV;
        if (range < 1) range = 1;
        return { minV: minV, maxV: maxV, range: range };
    }

    function yOf(fps, h, scale) {
        return h - ((fps - scale.minV) / scale.range) * h;
    }

    // ── 统计工具 ──
    function computeStats(pts) {
        var n = pts.length;
        var sum = 0, lo = pts[0], hi = pts[0];
        for (var i = 0; i < n; i++) {
            sum += pts[i];
            if (pts[i] < lo) lo = pts[i];
            if (pts[i] > hi) hi = pts[i];
        }
        var avg = sum / n;

        // P1 / P5 low（取排序后最低 1% / 5% 的平均值）
        var sorted = pts.slice().sort(function(a, b) { return a - b; });
        var p1Count = Math.max(1, Math.floor(n * 0.01));
        var p5Count = Math.max(1, Math.floor(n * 0.05));
        var p1Sum = 0, p5Sum = 0;
        for (var i = 0; i < p5Count; i++) {
            p5Sum += sorted[i];
            if (i < p1Count) p1Sum += sorted[i];
        }
        return {
            lo: lo, hi: hi, avg: avg,
            p1Low: p1Sum / p1Count,
            p5Low: p5Sum / p5Count
        };
    }

    // ── lerp 工具 ──
    function lerpArrays(from, to, t) {
        var n = to.length;
        var out = new Array(n);
        if (from.length !== n) return to; // 长度不同直接跳到目标
        for (var i = 0; i < n; i++) {
            out[i] = from[i] + (to[i] - from[i]) * t;
        }
        return out;
    }

    // ── 绘制：危险区 + 参考线 ──
    function drawZones(ctx, w, h, scale) {
        var dangerY = yOf(DANGER_FPS, h, scale);
        if (dangerY < h) {
            ctx.fillStyle = 'rgba(255,50,50,0.10)';
            ctx.fillRect(0, dangerY, w, h - dangerY);
            ctx.strokeStyle = 'rgba(255,80,80,0.25)';
            ctx.lineWidth = 0.5;
            ctx.setLineDash([2, 3]);
            ctx.beginPath(); ctx.moveTo(0, dangerY); ctx.lineTo(w, dangerY); ctx.stroke();
            ctx.setLineDash([]);
        }
        var targetY = yOf(TARGET_FPS, h, scale);
        if (targetY > 0 && targetY < h) {
            ctx.strokeStyle = 'rgba(102,255,102,0.18)';
            ctx.lineWidth = 0.5;
            ctx.setLineDash([3, 4]);
            ctx.beginPath(); ctx.moveTo(0, targetY); ctx.lineTo(w, targetY); ctx.stroke();
            ctx.setLineDash([]);
        }
    }

    // ── 绘制：面积渐变（分区着色：绿/黄/红按高度） ──
    function drawAreaFill(ctx, xs, ys, w, h, scale) {
        var n = xs.length;
        ctx.beginPath();
        ctx.moveTo(xs[0], ys[0]);
        for (var i = 1; i < n; i++) {
            var cpx = (xs[i - 1] + xs[i]) / 2;
            var cpy = (ys[i - 1] + ys[i]) / 2;
            ctx.quadraticCurveTo(xs[i - 1], ys[i - 1], cpx, cpy);
        }
        ctx.lineTo(xs[n - 1], ys[n - 1]);
        ctx.lineTo(xs[n - 1], h);
        ctx.lineTo(xs[0], h);
        ctx.closePath();

        // 三段色带渐变（canvas y=0 是顶部=高FPS，y=h 是底部=低FPS）
        var grad = ctx.createLinearGradient(0, 0, 0, h);
        var dangerY = yOf(DANGER_FPS, h, scale) / h; // 18fps 线在 canvas 中的归一化 y 位置
        var targetY = yOf(TARGET_FPS, h, scale) / h;  // 26fps 线
        // 从顶(0)=高FPS 到底(1)=低FPS: 绿→黄→红
        grad.addColorStop(0, 'rgba(100,255,100,0.25)');
        if (targetY > 0 && targetY < 1) {
            grad.addColorStop(Math.min(1, targetY), 'rgba(100,255,100,0.15)');
        }
        if (dangerY > 0 && dangerY < 1) {
            grad.addColorStop(Math.min(1, dangerY), 'rgba(255,200,0,0.08)');
        }
        grad.addColorStop(1, 'rgba(255,50,50,0.02)');
        ctx.fillStyle = grad;
        ctx.fill();
    }

    // ── 绘制：分段着色曲线 ──
    function drawSegmentedCurve(ctx, xs, ys, pts) {
        var n = xs.length;
        for (var i = 1; i < n; i++) {
            ctx.beginPath();
            ctx.moveTo(xs[i - 1], ys[i - 1]);
            var cpx = (xs[i - 1] + xs[i]) / 2;
            var cpy = (ys[i - 1] + ys[i]) / 2;
            ctx.quadraticCurveTo(xs[i - 1], ys[i - 1], cpx, cpy);
            ctx.lineTo(xs[i], ys[i]);
            ctx.strokeStyle = fpsColor((pts[i - 1] + pts[i]) / 2, 0.9);
            ctx.lineWidth = 1.5;
            ctx.stroke();
        }
    }

    // ── 绘制：简化单色折线（L3） ──
    function drawSimpleLine(ctx, xs, ys, avgFps) {
        var n = xs.length;
        ctx.beginPath();
        ctx.moveTo(xs[0], ys[0]);
        for (var i = 1; i < n; i++) ctx.lineTo(xs[i], ys[i]);
        ctx.strokeStyle = fpsColor(avgFps, 0.8);
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    // ── 绘制：末端光晕 ──
    function drawEndGlow(ctx, x, y, fps) {
        var glow = ctx.createRadialGradient(x, y, 0, x, y, 4);
        glow.addColorStop(0, fpsColor(fps, 0.6));
        glow.addColorStop(1, fpsColor(fps, 0));
        ctx.fillStyle = glow;
        ctx.fillRect(x - 4, y - 4, 8, 8);
        ctx.beginPath();
        ctx.arc(x, y, 1.5, 0, Math.PI * 2);
        ctx.fillStyle = fpsColor(fps, 1);
        ctx.fill();
    }

    // ── 绘制：光照背景 ──
    function drawLightBg(cacheCtx, w, h, lightLevels, startHour) {
        cacheCtx.clearRect(0, 0, w, h);
        var lightPts = 30;
        var stepX = w / lightPts;
        var stepH = h / MAX_LIGHT;
        cacheCtx.beginPath();
        cacheCtx.moveTo(0, h);
        for (var i = 0; i < lightPts; i++) {
            var hourIdx = (startHour + i) % 24;
            cacheCtx.lineTo(i * stepX, h - lightLevels[hourIdx] * stepH);
        }
        cacheCtx.lineTo((lightPts - 1) * stepX, h);
        cacheCtx.closePath();
        cacheCtx.fillStyle = 'rgba(180,160,60,0.35)';
        cacheCtx.fill();
        cacheCtx.beginPath();
        for (var i = 0; i < lightPts; i++) {
            var hourIdx2 = (startHour + i) % 24;
            var ly = h - lightLevels[hourIdx2] * stepH;
            if (i === 0) cacheCtx.moveTo(0, ly);
            else cacheCtx.lineTo(i * stepX, ly);
        }
        cacheCtx.strokeStyle = 'rgba(200,180,70,0.5)';
        cacheCtx.lineWidth = 0.8;
        cacheCtx.stroke();
    }

    // ══════════════════════════════════════════════
    //  create() — 创建迷你图渲染器实例
    // ══════════════════════════════════════════════
    function create(canvas, cssW, cssH) {
        var ctx = setupHiDpi(canvas, cssW, cssH);
        var w = cssW, h = cssH;

        // 光照离屏缓存
        var lightCache = document.createElement('canvas');
        var lightCacheCtx;
        (function initLightCache() {
            var dpr = currentDpr();
            lightCache.width = w * dpr;
            lightCache.height = h * dpr;
            lightCacheCtx = lightCache.getContext('2d');
            lightCacheCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        })();
        var lightCacheHour = -1;

        // 动画状态
        var prevPts = null;
        var animFrame = 0;
        var animRafId = null;
        var renderPts = null; // 当前帧实际绘制的点

        // tooltip 状态
        var tooltipIdx = -1;

        // DPR 变化监听
        var lastDpr = currentDpr();
        function checkDpr() {
            var newDpr = currentDpr();
            if (newDpr !== lastDpr) {
                lastDpr = newDpr;
                ctx = setupHiDpi(canvas, w, h);
                // 重建离屏缓存
                lightCache.width = w * newDpr;
                lightCache.height = h * newDpr;
                lightCacheCtx = lightCache.getContext('2d');
                lightCacheCtx.setTransform(newDpr, 0, 0, newDpr, 0, 0);
                lightCacheHour = -1; // 强制重绘
            }
        }
        // matchMedia 精确监听 DPR 变化
        function watchDpr() {
            var mql = window.matchMedia('(resolution: ' + currentDpr() + 'dppx)');
            var handler = function() {
                checkDpr();
                watchDpr(); // 重新注册（resolution 值已变）
            };
            if (mql.addEventListener) mql.addEventListener('change', handler, { once: true });
            else if (mql.addListener) mql.addListener(function f() { mql.removeListener(f); handler(); });
        }
        watchDpr();

        // ── render(pts, perfLevel, gameHour, lightLevels) ──
        function render(pts, perfLevel, gameHour, lightLevels) {
            checkDpr(); // 防御性检查
            ctx.clearRect(0, 0, w, h);

            // 光照背景
            if (lightLevels && lightLevels.length >= 24) {
                var curHour = Math.floor(gameHour);
                if (curHour !== lightCacheHour) {
                    lightCacheHour = curHour;
                    drawLightBg(lightCacheCtx, w, h, lightLevels, curHour);
                }
                ctx.drawImage(lightCache, 0, 0, w, h);
            }

            if (!pts || pts.length < 2) return;

            // 动画：如果有旧数据，启动 lerp 过渡
            if (prevPts && prevPts.length === pts.length && animFrame < ANIM_FRAMES) {
                animFrame++;
                var t = animFrame / ANIM_FRAMES;
                // ease-out
                t = 1 - (1 - t) * (1 - t);
                renderPts = lerpArrays(prevPts, pts, t);
                if (animFrame < ANIM_FRAMES) {
                    animRafId = requestAnimationFrame(function() {
                        render(pts, perfLevel, gameHour, lightLevels);
                    });
                } else {
                    renderPts = pts;
                    prevPts = pts;
                }
            } else {
                // 首帧或长度变化 → 无过渡
                if (!prevPts || prevPts.length !== pts.length) {
                    prevPts = pts;
                }
                renderPts = pts;
                prevPts = pts;
            }

            var rp = renderPts;
            var n = rp.length;
            var isSimple = (perfLevel >= 3);
            var scale = calcYScale(rp);

            // 坐标
            var xs = new Array(n), ys = new Array(n);
            for (var i = 0; i < n; i++) {
                xs[i] = (i / (n - 1)) * w;
                ys[i] = yOf(rp[i], h, scale);
            }

            var avgFps = 0;
            for (var i = 0; i < n; i++) avgFps += rp[i];
            avgFps /= n;

            // 绘制层
            drawZones(ctx, w, h, scale);

            if (isSimple) {
                drawSimpleLine(ctx, xs, ys, avgFps);
            } else {
                drawAreaFill(ctx, xs, ys, w, h, scale);
                drawSegmentedCurve(ctx, xs, ys, rp);
                drawEndGlow(ctx, xs[n - 1], ys[n - 1], rp[n - 1]);
            }

            // tooltip 高亮点
            if (tooltipIdx >= 0 && tooltipIdx < n) {
                var ti = tooltipIdx;
                ctx.beginPath();
                ctx.arc(xs[ti], ys[ti], 2.5, 0, Math.PI * 2);
                ctx.fillStyle = fpsColor(rp[ti], 1);
                ctx.fill();
                ctx.beginPath();
                ctx.setLineDash([1, 2]);
                ctx.moveTo(xs[ti], 0); ctx.lineTo(xs[ti], h);
                ctx.strokeStyle = 'rgba(255,255,255,0.25)';
                ctx.lineWidth = 0.5;
                ctx.stroke();
                ctx.setLineDash([]);
            }
        }

        function startAnim(pts, perfLevel, gameHour, lightLevels) {
            if (animRafId) { cancelAnimationFrame(animRafId); animRafId = null; }
            animFrame = 0;
            render(pts, perfLevel, gameHour, lightLevels);
        }

        // ── 命中测试：鼠标 CSS 坐标 → 最近点索引 ──
        function hitTest(mouseX) {
            if (!renderPts || renderPts.length < 2) return -1;
            var n = renderPts.length;
            var idx = Math.round((mouseX / w) * (n - 1));
            return Math.max(0, Math.min(n - 1, idx));
        }

        function setTooltipIdx(idx) { tooltipIdx = idx; }

        function getPointData(idx) {
            if (!renderPts || idx < 0 || idx >= renderPts.length) return null;
            return {
                index: idx,
                fps: renderPts[idx],
                x: (idx / (renderPts.length - 1)) * w,
                y: yOf(renderPts[idx], h, calcYScale(renderPts))
            };
        }

        // ══════════════════════════════════════════════
        //  renderExpanded() — 展开大图
        // ══════════════════════════════════════════════
        function renderExpanded(expCanvas, fullHistory, gameHour, lightLevels, perfLevel) {
            var ew = expCanvas.clientWidth || 400;
            var eh = expCanvas.clientHeight || 120;
            var ectx = setupHiDpi(expCanvas, ew, eh);

            ectx.clearRect(0, 0, ew, eh);

            if (!fullHistory || fullHistory.length < 2) {
                ectx.fillStyle = 'rgba(255,255,255,0.3)';
                ectx.font = '11px Consolas, monospace';
                ectx.textAlign = 'center';
                ectx.fillText('等待数据...', ew / 2, eh / 2);
                return;
            }

            var pts = fullHistory;
            var n = pts.length;
            var scale = calcYScale(pts);
            var stats = computeStats(pts);

            // 光照背景（复用主缓存 blit）
            if (lightLevels && lightLevels.length >= 24) {
                var curHour = Math.floor(gameHour);
                // 直接绘制（展开图尺寸不同，不用缓存）
                drawLightBg(ectx, ew, eh, lightLevels, curHour);
            }

            // 坐标
            var xs = new Array(n), ys = new Array(n);
            for (var i = 0; i < n; i++) {
                xs[i] = (i / (n - 1)) * ew;
                ys[i] = yOf(pts[i], eh, scale);
            }

            var avgFps = stats.avg;

            // 绘制层
            drawZones(ectx, ew, eh, scale);
            drawAreaFill(ectx, xs, ys, ew, eh, scale);
            drawSegmentedCurve(ectx, xs, ys, pts);
            drawEndGlow(ectx, xs[n - 1], ys[n - 1], pts[n - 1]);

            // ── 标注线：P1 low / P5 low / avg ──
            var annotations = [
                { label: 'avg ' + avgFps.toFixed(1), fps: avgFps, color: 'rgba(180,180,180,0.6)', dash: [4, 4] },
                { label: '5% low ' + stats.p5Low.toFixed(1), fps: stats.p5Low, color: 'rgba(255,180,0,0.5)', dash: [3, 3] },
                { label: '1% low ' + stats.p1Low.toFixed(1), fps: stats.p1Low, color: 'rgba(255,80,80,0.5)', dash: [2, 2] }
            ];

            ectx.font = '9px Consolas, monospace';
            ectx.textBaseline = 'bottom';
            for (var ai = 0; ai < annotations.length; ai++) {
                var a = annotations[ai];
                var ay = yOf(a.fps, eh, scale);
                if (ay < 2 || ay > eh - 2) continue;
                ectx.strokeStyle = a.color;
                ectx.lineWidth = 0.8;
                ectx.setLineDash(a.dash);
                ectx.beginPath();
                ectx.moveTo(0, ay);
                ectx.lineTo(ew, ay);
                ectx.stroke();
                ectx.setLineDash([]);
                // 标签
                ectx.fillStyle = a.color;
                ectx.textAlign = 'left';
                ectx.fillText(a.label, 3, ay - 2);
            }

            // 右下角统计
            ectx.textAlign = 'right';
            ectx.textBaseline = 'bottom';
            ectx.fillStyle = 'rgba(255,255,255,0.5)';
            ectx.font = '10px Consolas, monospace';
            ectx.fillText(
                n + ' samples | lo:' + stats.lo.toFixed(1) + ' hi:' + stats.hi.toFixed(1),
                ew - 4, eh - 3
            );
        }

        return {
            render: render,
            startAnim: startAnim,
            hitTest: hitTest,
            setTooltipIdx: setTooltipIdx,
            getPointData: getPointData,
            renderExpanded: renderExpanded,
            checkDpr: checkDpr
        };
    }

    return {
        create: create,
        fpsColor: fpsColor,
        computeStats: computeStats,
        setupHiDpi: setupHiDpi,
        currentDpr: currentDpr
    };
})();
