var MapCanvasStageRenderer = (function() {
    'use strict';

    // ================================================================
    // 地图舞台 Canvas 渲染器 · 双画布 + 动画循环
    //
    //   bg canvas (静态层) : backdrop / 占用地层纹理 / 网格 / filter 覆膜 /
    //                        异常层 / 场景图 / NPC 头像。仅在状态变更或补间
    //                        进行时重绘，稳态下不动 — 还原旧 DOM GPU 合成成本。
    //   fg canvas (动态层) : 任务环 / 反馈标记 / 提示 / 未开放提示。逐帧重绘，
    //                        承载所有循环动画。
    //
    // 层序: bg(z2) < hotspot 命中层(z3) / 标签层(z5) < fg(z6)，
    // 还原旧 feedback-layer z6 高于 hotspot-label-layer z5 的关系。
    //
    // 动画: RAF 循环只在存在动画元素（标记/任务环/提示/异常层/补间/过渡）
    // 时运行；面板隐藏（画布尺寸为 0）时自动停。
    // ================================================================

    var SHARPEN_AMOUNT = 0.45;
    var SHARPEN_WORKER_URL = 'modules/workers/sharpen-worker.js';
    var TWO_PI = Math.PI * 2;
    var TWEEN_TAU = 0.052;          // 指数平滑时间常数 → ~0.14s 收敛 (旧 CSS transition 0.14s)
    var TWEEN_EPS = 0.005;
    var RETUNE_MS = 180;            // 频段重调过渡 (旧 @keyframes mapStageRetune)
    var PAGE_ENTER_MS = 220;        // 切页 filter-overlay 淡入 (旧 transition opacity 0.22s)
    var IDLE_FPS = 30;              // 仅环境动画(无交互)时的限帧目标 — 砍 idle 常驻成本
    var TASK_RING_GAP = 5;          // 任务环套住头像时, 环中线相对头像外缘的间距 (页面单位)

    function Renderer(bgCanvas, options) {
        options = options || {};
        this.canvas = bgCanvas || null;
        this.ctx = this.canvas && this.canvas.getContext ? this.canvas.getContext('2d') : null;
        this.fgCanvas = options.fgCanvas || null;
        this.fgCtx = this.fgCanvas && this.fgCanvas.getContext ? this.fgCanvas.getContext('2d') : null;
        // 任务环专用层 (z=3, 低于 hotspot/标签) — 与 fg(z=6) 分开, 任务环才不会盖住标签卡片
        this.ringCanvas = options.ringCanvas || null;
        this.ringCtx = this.ringCanvas && this.ringCanvas.getContext ? this.ringCanvas.getContext('2d') : null;
        this.resolveAssetUrl = options.resolveAssetUrl ? options.resolveAssetUrl : identity;
        this.state = null;
        this.raf = 0;
        // host 驱动关闭后置 true: ensureLoop 不再排程, 避免隐藏画布上 RAF 泄漏。
        this.stopped = false;
        this.imageCache = {};
        this.sharpenCache = {};
        this.sharpenWorker = null;
        this.sharpenWorkerInitFailed = false;
        this.sharpenPending = {};
        this.sharpenKeySeq = 0;
        this.drawCount = 0;
        this.frameCount = 0;        // RAF 回调累计数 — QA 探测循环是否已停 (map-ui25)
        this.pendingAssets = 0;
        this.missingAssets = [];
        this.lastDynamicAvatarUrl = '';
        this.lastDrawSummary = null;
        this.lastRevision = 0;
        // 动画 / 补间状态
        this.tweens = {};
        this.bakedCache = {};       // 预烤 filter+阴影 的离屏画布缓存 (切页清空)
        this._backdropCanvas = null; // backdrop 整层缓存 (按 页+filter+尺寸 复用)
        this._backdropKey = null;
        this._lastDrawTime = 0;     // idle 限帧用
        this.staticDirty = true;
        this.staticAnimating = false;
        this.retuneStart = 0;
        this.pageEnterStart = 0;
        this.lastFrameTime = 0;
        this.dt = 0;
        // prefers-reduced-motion: 命中时冻结所有循环动画 / 补间 / 过渡 (还原旧 CSS @media 降级)
        this._reduce = false;
        this.reduceMotionMql = (typeof window !== 'undefined' && window.matchMedia)
            ? window.matchMedia('(prefers-reduced-motion: reduce)')
            : null;
        bindReduceMotion(this);
    }

    function bindReduceMotion(self) {
        var mql = self.reduceMotionMql;
        if (!mql || !mql.addEventListener) return;
        mql.addEventListener('change', function() {
            self.staticDirty = true;
            self.ensureLoop();
        });
    }

    Renderer.prototype.isAvailable = function() {
        return !!(this.canvas && this.ctx && this.fgCanvas && this.fgCtx && this.ringCanvas && this.ringCtx);
    };

    Renderer.prototype.setState = function(state) {
        var prev = this.state;
        var t = nowMs();
        state = state || null;
        // setState = 面板重新活跃的合法信号 — 解除 stop() 的封停。
        this.stopped = false;
        if (state && state.page) {
            if (!prev || !prev.page || prev.page.id !== state.page.id) {
                // 切页: 清补间避免跨页焦点残留, 起 filter-overlay 淡入
                this.pageEnterStart = t;
                this.retuneStart = 0;
                this.tweens = {};
                this.bakedCache = {};   // 切页: 场景图全换, 旧烤图作废
            } else if ((prev.activeFilterId || '') !== (state.activeFilterId || '') && (prev.activeFilterId || '')) {
                // 同页真正切 filter → 频段重调瞬态
                this.retuneStart = t;
            }
        }
        this.state = state;
        this.staticDirty = true;
        this.ensureLoop();
    };

    Renderer.prototype.requestDraw = function() {
        // 图片异步就绪回调: 静态层需重绘
        this.staticDirty = true;
        this.ensureLoop();
    };

    Renderer.prototype.ensureLoop = function() {
        var self = this;
        if (this.stopped || !this.isAvailable() || this.raf) return;
        this.raf = requestFrame(function(ts) {
            self.raf = 0;
            self.frame(ts);
        });
    };

    // host 驱动关闭 / 面板隐藏: 立刻停 RAF 循环。必须显式调用 —
    // 隐藏画布 clientWidth 为 0, 但渲染器仍持上次 stage 尺寸快照, 循环不会自停。
    // stopped 标志同时挡住延迟的图片 onload / reduced-motion 回调重启循环。
    Renderer.prototype.stop = function() {
        if (this.raf && typeof cancelAnimationFrame === 'function') {
            cancelAnimationFrame(this.raf);
        }
        this.raf = 0;
        this.stopped = true;
        this.lastFrameTime = 0;
        this._lastDrawTime = 0;
    };

    Renderer.prototype.frame = function(timestamp) {
        var t = (typeof timestamp === 'number' && timestamp > 0) ? timestamp : nowMs();
        this.frameCount += 1;
        // idle 限帧 — 仅环境动画(marker/任务环/异常脉冲)在动、无交互时降到 ~IDLE_FPS;
        // 交互(hover 补间 / retune / 入场 / 状态变更)期间满帧, 不影响跟手。
        var interaction = this.retuneActive(t) || this.factionEntering(t)
            || this.staticAnimating || this.staticDirty;
        if (!interaction && this._lastDrawTime
            && (t - this._lastDrawTime) < (1000 / IDLE_FPS - 1)) {
            this.ensureLoop();
            return;
        }
        this._lastDrawTime = t;
        // 循环首帧用 1/60 估算 dt, 让补间从首帧就推进 (而非 snap)
        var dt = this.lastFrameTime ? (t - this.lastFrameTime) / 1000 : (1 / 60);
        if (dt < 0) dt = 0;
        if (dt > 0.1) dt = 0.1;          // 切后台/卡顿后避免补间瞬跳
        this.dt = dt;
        this.lastFrameTime = t;
        var rendered = this.composite(t);
        if (rendered && this.needsAnimation(t)) {
            this.ensureLoop();
        } else {
            this.lastFrameTime = 0;       // 循环停 → 下次启动重新计时
        }
    };

    Renderer.prototype.composite = function(t) {
        if (!this.isAvailable() || !this.state || !this.state.page) return false;
        var m = this.syncCanvasSize();
        if (!m) return false;             // 画布尺寸 0 (面板隐藏) → 循环自然停
        this._reduce = !!(this.reduceMotionMql && this.reduceMotionMql.matches);
        var staticNeeded = this.staticDirty
            || this.staticAnimating
            || this.retuneActive(t)
            || this.factionEntering(t)
            || (this.state.anomalyActive && !m.lowEffects && !this._reduce);
        if (staticNeeded) {
            this.renderStatic(t, m);
            this.staticDirty = false;
        }
        this.renderDynamic(t, m);
        return true;
    };

    Renderer.prototype.syncCanvasSize = function() {
        var state = this.state;
        var page = state.page;
        var dpr = getDpr();
        // 只认画布自身布局尺寸: 面板隐藏时 clientWidth 为 0 → 返回 null → 循环停。
        // 不回退 state.stageWidth (上次 setState 的快照) — 该值在面板隐藏后仍为非 0,
        // 会让隐藏画布的 RAF 循环一直转 (host 驱动关闭后的循环泄漏根因)。
        var cssW = Math.max(0, Math.round(this.canvas.clientWidth || 0));
        var cssH = Math.max(0, Math.round(this.canvas.clientHeight || 0));
        if (cssW <= 0 || cssH <= 0) return null;
        var backW = Math.max(1, Math.round(cssW * dpr));
        var backH = Math.max(1, Math.round(cssH * dpr));
        if (this.canvas.width !== backW) this.canvas.width = backW;
        if (this.canvas.height !== backH) this.canvas.height = backH;
        if (this.fgCanvas.width !== backW) this.fgCanvas.width = backW;
        if (this.fgCanvas.height !== backH) this.fgCanvas.height = backH;
        if (this.ringCanvas.width !== backW) this.ringCanvas.width = backW;
        if (this.ringCanvas.height !== backH) this.ringCanvas.height = backH;
        var stageScale = state.stageScale || (cssW / (page.width || 1)) || 1;
        var contentFitScale = state.contentFitScale || 1;
        return {
            dpr: dpr,
            cssW: cssW,
            cssH: cssH,
            stageScale: stageScale,
            contentScale: stageScale * contentFitScale,
            offsetX: state.contentFitOffsetX || 0,
            offsetY: state.contentFitOffsetY || 0,
            lowEffects: !!state.lowEffects
        };
    };

    Renderer.prototype.renderStatic = function(t, m) {
        var ctx = this.ctx;
        var state = this.state;
        var page = state.page;

        ctx.setTransform(m.dpr, 0, 0, m.dpr, 0, 0);
        ctx.clearRect(0, 0, m.cssW, m.cssH);
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = m.lowEffects ? 'medium' : 'high';

        this.pendingAssets = 0;
        this.missingAssets = [];
        this.lastDynamicAvatarUrl = '';
        this.staticAnimating = false;

        // backdrop + 底图 — 稳态走整层缓存; retune/入场时实时画。
        // 异常层已从 backdrop 拆出 (见下) — anomaly 活跃不再让 backdrop 缓存失效。
        var backdropLive = this.retuneActive(t) || this.factionEntering(t);
        var backdropCanvas = backdropLive ? null : this.getBackdropCanvas(m);
        if (backdropCanvas) {
            ctx.drawImage(backdropCanvas, 0, 0, m.cssW, m.cssH);
        } else {
            // 实时路径: retune skew/亮度 / 入场淡入 在动, 无法缓存
            ctx.save();
            this.applyRetune(ctx, t, m);
            ctx.scale(m.stageScale, m.stageScale);
            drawBackdrop(ctx, page, state.activeFilterId || '', m.lowEffects,
                this.overlayAlpha(t));
            ctx.restore();
            if (state.backgroundImageUrl) {
                ctx.save();
                ctx.scale(m.stageScale, m.stageScale);
                this.drawBackgroundImage(ctx, state.backgroundImageUrl, page);
                ctx.restore();
            }
        }

        // 禁区异常层 — 动画层, 实时画在 (已缓存的) backdrop 之上 / 场景之下。
        // 从 drawBackdrop 拆出后, anomaly 页的 backdrop 重回整层缓存 (省掉每帧
        // 渐变/网格/纹理重栅格)。retune 期跟随 backdrop 一起 skew;
        // reduced-motion 下 t=0 冻结首帧但仍显示 (还原旧 display 行为)。
        if (state.anomalyActive && !m.lowEffects) {
            ctx.save();
            this.applyRetune(ctx, t, m);
            ctx.scale(m.stageScale, m.stageScale);
            drawAnomaly(ctx, page.width || 1031, page.height || 608, this._reduce ? 0 : t);
            ctx.restore();
        }

        // 场景 + 头像 (content-fit 空间)
        ctx.save();
        ctx.translate(m.offsetX, m.offsetY);
        ctx.scale(m.contentScale, m.contentScale);
        drawScenes(this, ctx, state, m);
        drawAvatars(this, ctx, state, m.lowEffects);
        ctx.restore();

        ctx.filter = 'none';
        this.drawCount += 1;
        this.lastRevision = state.revision || 0;
        this.updateDrawSummary(state, m);
    };

    // backdrop 整层 (底纹/网格/纹理/派系覆膜/底图) 缓存进离屏画布。
    // 这一层在 页/filter/尺寸 不变时完全静止 — hover 补间触发的 renderStatic
    // 不必每帧重画它, 直接 drawImage 缓存即可。
    Renderer.prototype.getBackdropCanvas = function(m) {
        var state = this.state;
        var key = state.page.id + '|' + (state.activeFilterId || '') + '|'
            + m.cssW + 'x' + m.cssH + '|' + m.dpr + '|' + (m.lowEffects ? 'L' : 'N')
            + '|' + (state.backgroundImageUrl || '');
        if (this._backdropCanvas && this._backdropKey === key) return this._backdropCanvas;
        if (typeof document === 'undefined' || !document.createElement) return null;
        var cv = this._backdropCanvas || document.createElement('canvas');
        cv.width = Math.max(1, Math.round(m.cssW * m.dpr));
        cv.height = Math.max(1, Math.round(m.cssH * m.dpr));
        var c = cv.getContext('2d');
        if (!c) return null;
        c.setTransform(m.dpr, 0, 0, m.dpr, 0, 0);
        c.imageSmoothingEnabled = true;
        c.imageSmoothingQuality = m.lowEffects ? 'medium' : 'high';
        var pendBefore = this.pendingAssets;
        this.renderBackdropLayer(c, m);
        this._backdropCanvas = cv;
        // 底图未就绪 → 本次缓存不完整, 不定型 key, 下帧重建; 就绪后才定型复用
        this._backdropKey = (this.pendingAssets > pendBefore) ? null : key;
        return cv;
    };

    Renderer.prototype.renderBackdropLayer = function(targetCtx, m) {
        var state = this.state;
        var page = state.page;
        targetCtx.save();
        targetCtx.scale(m.stageScale, m.stageScale);
        drawBackdrop(targetCtx, page, state.activeFilterId || '', m.lowEffects, 1);
        targetCtx.restore();
        if (state.backgroundImageUrl) {
            targetCtx.save();
            targetCtx.scale(m.stageScale, m.stageScale);
            this.drawBackgroundImage(targetCtx, state.backgroundImageUrl, page);
            targetCtx.restore();
        }
    };

    Renderer.prototype.renderDynamic = function(t, m) {
        var state = this.state;
        var animT = this._reduce ? 0 : t;   // reduced-motion: 冻结循环动画相位
        var ringCtx = this.ringCtx;
        var ctx = this.fgCtx;

        // 任务环层 (ring canvas, z=3): 套住头像, 但低于 hotspot/标签 — 不遮"前往选关"卡片
        ringCtx.setTransform(m.dpr, 0, 0, m.dpr, 0, 0);
        ringCtx.clearRect(0, 0, m.cssW, m.cssH);
        ringCtx.imageSmoothingEnabled = true;
        ringCtx.save();
        ringCtx.translate(m.offsetX, m.offsetY);
        ringCtx.scale(m.contentScale, m.contentScale);
        drawTaskRings(ringCtx, state, m.lowEffects, animT);
        ringCtx.restore();

        // 反馈层 (fg canvas, z=6): 标记/提示/未开放提示仍在标签之上 (还原旧 feedback-layer 层序)
        ctx.setTransform(m.dpr, 0, 0, m.dpr, 0, 0);
        ctx.clearRect(0, 0, m.cssW, m.cssH);
        ctx.imageSmoothingEnabled = true;
        ctx.save();
        ctx.translate(m.offsetX, m.offsetY);
        ctx.scale(m.contentScale, m.contentScale);
        drawMarkers(ctx, state, m.lowEffects, animT);
        drawTips(ctx, state, animT);
        drawHints(ctx, state, animT);
        ctx.restore();
    };

    Renderer.prototype.applyRetune = function(ctx, t, m) {
        if (!this.retuneActive(t)) return;
        var p = clamp((t - this.retuneStart) / RETUNE_MS, 0, 1);
        var skew, bri;
        // 旧 keyframes: 0% skew0/bri1 · 20% skew-2.4/bri1.18 · 55% skew1.2/bri0.88 · 100% skew0/bri1
        if (p < 0.2) {
            skew = lerp(0, -2.4, p / 0.2);
            bri = lerp(1, 1.18, p / 0.2);
        } else if (p < 0.55) {
            skew = lerp(-2.4, 1.2, (p - 0.2) / 0.35);
            bri = lerp(1.18, 0.88, (p - 0.2) / 0.35);
        } else {
            skew = lerp(1.2, 0, (p - 0.55) / 0.45);
            bri = lerp(0.88, 1, (p - 0.55) / 0.45);
        }
        var cx = m.cssW / 2;
        var cy = m.cssH / 2;
        ctx.translate(cx, cy);
        ctx.transform(1, 0, Math.tan(skew * Math.PI / 180), 1, 0, 0);
        ctx.translate(-cx, -cy);
        ctx.filter = 'brightness(' + bri.toFixed(3) + ')';
    };

    Renderer.prototype.drawBackgroundImage = function(ctx, resolvedUrl, page) {
        var rec = this.loadRawImage(resolvedUrl);
        if (!rec || rec.status !== 'ready') return;
        var img = rec.image;
        var iw = img.naturalWidth || img.width;
        var ih = img.naturalHeight || img.height;
        if (!iw || !ih) return;
        var pw = page.width || 1031;
        var ph = page.height || 608;
        var scale = Math.max(pw / iw, ph / ih);
        var dw = iw * scale;
        var dh = ih * scale;
        // filter (contrast/saturate) 预烤进离屏画布, 免每次静态重绘走 ctx.filter 慢路径 (#15)
        var bgFilter = 'contrast(1.03) saturate(1.04)';
        var baked = getBaked(this, img, resolvedUrl + '|bg|' + bgFilter, iw, ih, bgFilter, null);
        ctx.save();
        if (baked) {
            ctx.drawImage(baked.canvas, (pw - dw) / 2, (ph - dh) / 2, dw, dh);
        } else {
            ctx.filter = bgFilter;
            ctx.drawImage(img, (pw - dw) / 2, (ph - dh) / 2, dw, dh);
        }
        ctx.restore();
    };

    Renderer.prototype.retuneActive = function(t) {
        if (this._reduce) return false;
        return this.retuneStart > 0 && (t - this.retuneStart) < RETUNE_MS;
    };

    Renderer.prototype.pageEnterActive = function(t) {
        return this.pageEnterStart > 0 && (t - this.pageEnterStart) < PAGE_ENTER_MS;
    };

    Renderer.prototype.factionEntering = function(t) {
        if (this._reduce) return false;
        return this.pageEnterActive(t)
            && !!(this.state && this.state.page && this.state.page.backdropTheme === 'faction');
    };

    Renderer.prototype.overlayAlpha = function(t) {
        if (this._reduce || !this.pageEnterActive(t)) return 1;
        var p = clamp((t - this.pageEnterStart) / PAGE_ENTER_MS, 0, 1);
        return 1 - (1 - p) * (1 - p);   // easeOut
    };

    Renderer.prototype.needsAnimation = function(t) {
        var s = this.state;
        if (!s) return false;
        if (this._reduce) return false;     // reduced-motion: 单帧静绘后停循环
        if (this.retuneActive(t) || this.factionEntering(t) || this.staticAnimating) return true;
        if (s.anomalyActive && !s.lowEffects) return true;
        if ((s.taskRings || []).length) return true;
        if ((s.flashHints || []).length) return true;
        if ((s.feedbackTips || []).length) return true;
        if ((s.feedbackMarkers || []).length && !s.lowEffects) return true;
        return false;
    };

    // 补间: 指数平滑逼近 target; 首见即 snap (初次渲染无过渡)。
    Renderer.prototype.tween = function(key, target) {
        var tw = this.tweens[key];
        if (!tw || this._reduce) {
            // 首见即 snap; reduced-motion 下永远 snap (无过渡)
            this.tweens[key] = { v: target };
            return target;
        }
        if (this.dt <= 0) return tw.v;
        var k = 1 - Math.exp(-this.dt / TWEEN_TAU);
        tw.v += (target - tw.v) * k;
        if (Math.abs(target - tw.v) > TWEEN_EPS) {
            this.staticAnimating = true;
        } else {
            tw.v = target;
        }
        return tw.v;
    };

    Renderer.prototype.updateDrawSummary = function(state, m) {
        this.lastDrawSummary = {
            pageId: state.page.id,
            filterId: state.activeFilterId || '',
            sceneCount: (state.sceneVisuals || []).length,
            avatarCount: (state.staticAvatars || []).length + (state.dynamicAvatars || []).length,
            staticAvatarCount: (state.staticAvatars || []).length,
            dynamicAvatarCount: (state.dynamicAvatars || []).length,
            taskRingCount: (state.taskRings || []).length,
            markerCount: (state.feedbackMarkers || []).length,
            tipCount: (state.feedbackTips || []).length,
            flashHintCount: (state.flashHints || []).length,
            anomalyActive: !!state.anomalyActive,
            lowEffects: !!m.lowEffects
        };
    };

    Renderer.prototype.getDebugState = function() {
        return {
            renderer: 'canvas',
            canvasReady: this.isAvailable(),
            canvasPendingAssets: this.pendingAssets,
            canvasMissingAssets: this.missingAssets.slice(),
            canvasDrawCount: this.drawCount,
            canvasFrameCount: this.frameCount,
            canvasStopped: this.stopped,
            canvasLastRevision: this.lastRevision,
            canvasLastDynamicAvatarUrl: this.lastDynamicAvatarUrl,
            canvasLastDrawSummary: this.lastDrawSummary
        };
    };

    // ================================================================
    // 图片加载 / 锐化 worker — 行为同重构前, 保持不变
    // ================================================================

    Renderer.prototype.loadImage = function(assetUrl, options) {
        var resolved = this.resolveAssetUrl(assetUrl || '');
        var rawRecord;
        var sharpenRecord;
        if (!resolved) return null;

        rawRecord = this.loadRawImage(resolved);
        if (!(options && options.sharpen)) return rawRecord;

        sharpenRecord = this.loadSharpenedImage(resolved);
        if (sharpenRecord && sharpenRecord.status === 'ready') return sharpenRecord;
        if (sharpenRecord && sharpenRecord.status === 'pending') this.pendingAssets += 1;
        return rawRecord;
    };

    Renderer.prototype.loadRawImage = function(resolved) {
        var cached;
        var img;
        var self = this;
        if (!resolved) return null;

        cached = this.imageCache[resolved];
        if (cached) {
            if (cached.status === 'pending') this.pendingAssets += 1;
            if (cached.status === 'error') this.missingAssets.push(resolved);
            return cached;
        }

        img = new Image();
        cached = {
            url: resolved,
            image: img,
            status: 'pending'
        };
        this.imageCache[resolved] = cached;
        this.pendingAssets += 1;

        img.onload = function() {
            cached.status = 'ready';
            self.requestDraw();
        };
        img.onerror = function() {
            cached.status = 'error';
            self.missingAssets.push(resolved);
            self.requestDraw();
        };
        img.src = resolved;
        if (img.decode) {
            img.decode().then(function() {
                if (cached.status === 'pending') {
                    cached.status = 'ready';
                    self.requestDraw();
                }
            })['catch'](function() {
                if (cached.status === 'pending' && img.complete && img.naturalWidth > 0) {
                    cached.status = 'ready';
                    self.requestDraw();
                }
            });
        }

        return cached;
    };

    Renderer.prototype.loadSharpenedImage = function(resolved) {
        var cached;
        var self = this;
        if (!resolved) return null;

        cached = this.sharpenCache[resolved];
        if (cached) return cached;

        cached = {
            url: resolved,
            image: null,
            status: 'pending'
        };
        this.sharpenCache[resolved] = cached;

        this.getSharpenedUrl(resolved).then(function(blobUrl) {
            var img;
            if (!blobUrl) {
                cached.status = 'error';
                self.requestDraw();
                return;
            }
            img = new Image();
            cached.image = img;
            img.onload = function() {
                cached.status = 'ready';
                self.requestDraw();
            };
            img.onerror = function() {
                cached.status = 'error';
                self.requestDraw();
            };
            img.src = blobUrl;
        });

        return cached;
    };

    Renderer.prototype.getSharpenedUrl = function(assetUrl) {
        var promise;
        var self = this;
        if (!assetUrl) return Promise.resolve(null);

        if (!this.ensureSharpenWorker()) return Promise.resolve(null);

        promise = fetch(assetUrl).then(function(res) {
            if (!res.ok) throw new Error('http ' + res.status);
            return res.blob();
        }).then(function(blob) {
            return createImageBitmap(blob);
        }).then(function(bitmap) {
            return new Promise(function(resolve) {
                var w = self.ensureSharpenWorker();
                var key;
                if (!w) {
                    try { if (bitmap && bitmap.close) bitmap.close(); } catch (err) {}
                    resolve(null);
                    return;
                }
                key = 'sk' + (++self.sharpenKeySeq);
                self.sharpenPending[key] = resolve;
                try {
                    w.postMessage({
                        key: key,
                        bitmap: bitmap,
                        amount: SHARPEN_AMOUNT
                    }, [bitmap]);
                } catch (err2) {
                    delete self.sharpenPending[key];
                    try { if (bitmap && bitmap.close) bitmap.close(); } catch (err3) {}
                    resolve(null);
                }
            });
        })['catch'](function() {
            return null;
        });

        return promise;
    };

    Renderer.prototype.isSharpenSupported = function() {
        return typeof Worker !== 'undefined'
            && typeof OffscreenCanvas !== 'undefined'
            && typeof createImageBitmap === 'function'
            && typeof URL !== 'undefined'
            && typeof URL.createObjectURL === 'function'
            && typeof fetch === 'function'
            && typeof Promise === 'function';
    };

    Renderer.prototype.ensureSharpenWorker = function() {
        var self = this;
        if (this.sharpenWorker || this.sharpenWorkerInitFailed) return this.sharpenWorker;
        if (!this.isSharpenSupported()) {
            this.sharpenWorkerInitFailed = true;
            return null;
        }
        try {
            this.sharpenWorker = new Worker(this.resolveAssetUrl(SHARPEN_WORKER_URL));
            this.sharpenWorker.onmessage = function(e) {
                var msg = e.data || {};
                var resolver = self.sharpenPending[msg.key];
                if (!resolver) return;
                delete self.sharpenPending[msg.key];
                if (msg.error || !msg.blob) {
                    resolver(null);
                    return;
                }
                try {
                    resolver(URL.createObjectURL(msg.blob));
                } catch (err) {
                    resolver(null);
                }
            };
            this.sharpenWorker.onerror = function() {
                self.disableSharpenWorker();
            };
        } catch (err2) {
            this.disableSharpenWorker();
        }
        return this.sharpenWorker;
    };

    Renderer.prototype.disableSharpenWorker = function() {
        var keys;
        var i;
        this.sharpenWorkerInitFailed = true;
        keys = Object.keys(this.sharpenPending || {});
        for (i = 0; i < keys.length; i += 1) {
            try { this.sharpenPending[keys[i]](null); } catch (err) {}
        }
        this.sharpenPending = {};
        this.sharpenWorker = null;
    };

    // ================================================================
    // Backdrop (静态层)
    // ================================================================

    // 禁区异常层 (drawAnomaly) 不在此处画 — 它是动画层, 由 renderStatic 单独实时
    // 绘制在 backdrop 之上 / 场景之下。并进来会让 anomaly 活跃时整层 backdrop
    // (渐变 / 网格 / 纹理) 每帧重栅格, getBackdropCanvas 缓存失效。
    function drawBackdrop(ctx, page, activeFilterId, lowEffects, overlayAlpha) {
        var w = page.width || 1031;
        var h = page.height || 608;
        var theme = page.backdropTheme || 'default';

        fillThemeBase(ctx, theme, w, h);
        drawThemeTextures(ctx, theme, w, h);          // 占用地层纹理 (C)
        drawGrid(ctx, theme, w, h, lowEffects);       // 网格 (#3/#16)
        if (theme === 'faction') {
            drawFactionFilter(ctx, activeFilterId, w, h, lowEffects ? 0.42 : overlayAlpha);
        } else {
            drawThemeWash(ctx, theme, w, h);
        }
    }

    function fillThemeBase(ctx, theme, w, h) {
        var g = ctx.createRadialGradient(w * 0.5, h * 0.56, 10, w * 0.5, h * 0.56, Math.max(w, h) * 0.72);
        if (theme === 'base') {
            g.addColorStop(0, '#222414');
            g.addColorStop(0.62, '#14160e');
            g.addColorStop(1, '#0a0c08');
        } else if (theme === 'faction') {
            g.addColorStop(0, '#162016');
            g.addColorStop(0.6, '#0e140e');
            g.addColorStop(1, '#080a08');
        } else if (theme === 'defense') {
            g.addColorStop(0, '#342412');
            g.addColorStop(0.62, '#1c140c');
            g.addColorStop(1, '#0c0a08');
        } else if (theme === 'school') {
            g.addColorStop(0, '#162636');
            g.addColorStop(0.6, '#0e1824');
            g.addColorStop(1, '#080e16');
        } else {
            g.addColorStop(0, '#10140f');
            g.addColorStop(1, '#070807');
        }
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, h);
    }

    // 网格透明度: 旧 CSS ::before opacity 默认 0.62 / base 0.46 / 低性能 0.34 → 相对系数
    function drawGrid(ctx, theme, w, h, lowEffects) {
        var alpha = lowEffects ? 0.55 : (theme === 'base' ? 0.74 : 1.0);
        ctx.save();
        ctx.globalAlpha = ctx.globalAlpha * alpha;
        ctx.lineWidth = 1;
        ctx.strokeStyle = theme === 'school' ? 'rgba(174,228,255,0.12)' : 'rgba(210,240,160,0.08)';
        drawGridLines(ctx, w, h, 148, 128);
        ctx.strokeStyle = theme === 'school' ? 'rgba(174,228,255,0.06)' : 'rgba(210,240,160,0.035)';
        drawGridLines(ctx, w, h, 74, 64);
        ctx.strokeStyle = theme === 'school' ? 'rgba(174,228,255,0.16)' : 'rgba(190,255,92,0.12)';
        ctx.beginPath();
        ctx.moveTo(w * 0.5, 0);
        ctx.lineTo(w * 0.5, h);
        ctx.moveTo(0, h * 0.5);
        ctx.lineTo(w, h * 0.5);
        ctx.stroke();
        ctx.restore();
    }

    function drawGridLines(ctx, w, h, xStep, yStep) {
        var x;
        var y;
        ctx.beginPath();
        if (xStep > 0) {
            for (x = 0; x <= w; x += xStep) {
                ctx.moveTo(x + 0.5, 0);
                ctx.lineTo(x + 0.5, h);
            }
        }
        if (yStep > 0) {
            for (y = 0; y <= h; y += yStep) {
                ctx.moveTo(0, y + 0.5);
                ctx.lineTo(w, y + 0.5);
            }
        }
        ctx.stroke();
    }

    // 各页占用地层纹理 (还原旧 .map-stage-backdrop--<page>::after 的条纹/切痕)
    function drawThemeTextures(ctx, theme, w, h) {
        ctx.save();
        if (theme === 'base') {
            stripes(ctx, w, h, 38, 2, 'rgba(150,118,50,0.05)', 2);            // 金属擦痕横纹
        } else if (theme === 'defense') {
            diagBand(ctx, w, h, 0.40, 118, 'rgba(200,148,86,0.16)', 3);       // 战壕切痕
            diagBand(ctx, w, h, 0.64, 122, 'rgba(186,124,64,0.13)', 2);
            diagStripes(ctx, w, h, 45, 42, 'rgba(230,180,60,0.05)', 2);       // 辐射告警斜纹
        } else if (theme === 'school') {
            ctx.strokeStyle = 'rgba(174,228,255,0.12)';                       // 档案索引细网
            ctx.lineWidth = 1;
            drawGridLines(ctx, w, h, 52, 0);
            ctx.strokeStyle = 'rgba(174,228,255,0.10)';
            drawGridLines(ctx, w, h, 0, 64);
        } else if (theme === 'faction') {
            diagBand(ctx, w, h, 0.5, 136, 'rgba(255,255,255,0.04)', 4);       // 派系边界斜线
        }
        ctx.restore();
    }

    function drawThemeWash(ctx, theme, w, h) {
        if (theme === 'base') {
            radial(ctx, w * 0.84, h * 0.14, 260, 'rgba(255,190,90,0.14)');
            radial(ctx, w * 0.1, h * 0.92, 320, 'rgba(82,58,26,0.28)');
            radial(ctx, w * 0.5, h * 0.62, 500, 'rgba(140,108,42,0.08)');
        } else if (theme === 'defense') {
            radial(ctx, w * 0.24, h * 0.84, 340, 'rgba(198,82,26,0.22)');
            radial(ctx, w * 0.5, h * 0.22, 720, 'rgba(206,174,118,0.08)');
        } else if (theme === 'school') {
            radial(ctx, w * 0.5, h * 0.5, 640, 'rgba(72,146,196,0.13)');
            radial(ctx, w * 0.14, h * 0.86, 240, 'rgba(255,202,128,0.09)');
        }
    }

    // faction 四派系占用痕覆膜 (还原旧 .map-stage-filter-overlay 的扇形射界/共振环/节点)
    function drawFactionFilter(ctx, activeFilterId, w, h, alpha) {
        var diag = Math.max(w, h);
        ctx.save();
        ctx.globalAlpha = ctx.globalAlpha * (alpha == null ? 1 : clamp(alpha, 0, 1));
        if (activeFilterId === 'warlord') {
            // 锈红扇形射界 ×2 + 军绿底覆盖 + 钢印细条纹
            conicArc(ctx, w * 0.22, h * 0.26, diag * 0.62, 190, 34, 'rgba(168,48,28,0.30)');
            conicArc(ctx, w * 0.76, h * 0.72, diag * 0.52, 330, 42, 'rgba(152,42,22,0.24)');
            overlay(ctx, 'rgba(78,96,50,0.14)', w, h);
            stripes(ctx, w, h, 44, 1, 'rgba(220,86,56,0.055)', 2);
        } else if (activeFilterId === 'rock') {
            // 紫洋红大光晕 + 共振双环 (紫 / 毒物绿)
            radial(ctx, w * 0.66, h * 0.36, 300, 'rgba(220,60,210,0.24)');
            strokeCircle(ctx, w * 0.70, h * 0.42, diag * 0.142, 'rgba(220,60,210,0.18)', 3);
            strokeCircle(ctx, w * 0.70, h * 0.42, diag * 0.184, 'rgba(110,240,160,0.14)', 3);
        } else if (activeFilterId === 'blackiron') {
            // 墨底压印 + 朱砂主节点 + 铜接口点 + 铜经络线
            overlay(ctx, 'rgba(24,16,20,0.34)', w, h);
            radial(ctx, w * 0.20, h * 0.72, 72, 'rgba(216,56,38,0.50)');
            radial(ctx, w * 0.26, h * 0.88, 60, 'rgba(216,56,38,0.42)');
            radial(ctx, w * 0.14, h * 0.80, 22, 'rgba(220,158,72,0.40)');
            radial(ctx, w * 0.22, h * 0.82, 20, 'rgba(220,158,72,0.36)');
            diagBand(ctx, w, h, 0.42, 14, 'rgba(200,148,68,0.18)', 1);
            diagBand(ctx, w, h, 0.66, -28, 'rgba(200,148,68,0.14)', 1);
        } else if (activeFilterId === 'fallen') {
            // 琥珀暖雾 + 酒红点缀 + 招牌水迹倒影
            radial(ctx, w * 0.72, h * 0.70, 360, 'rgba(224,142,54,0.26)');
            radial(ctx, w * 0.78, h * 0.74, 190, 'rgba(220,62,80,0.12)');
            radial(ctx, w * 0.64, h * 0.82, 70, 'rgba(255,190,110,0.40)');
        } else {
            // all / 无 group: 中性轻散光
            radial(ctx, w * 0.5, h * 0.5, 560, 'rgba(80,110,68,0.10)');
        }
        ctx.restore();
    }

    // 禁区异常层 · 静态等高线坍缩 + 0.77Hz 三段式呼吸脉冲 + 双环扩散
    function drawAnomaly(ctx, w, h, t) {
        var x = w * 0.72;
        var y = h * 0.22;
        var cph;
        var coreScale;
        var coreOp;
        ctx.save();
        // 静态等高线坍缩底
        radial(ctx, x, y, 170, 'rgba(150,72,220,0.26)');
        strokeCircle(ctx, x, y, 110, 'rgba(180,92,240,0.16)', 2);
        strokeCircle(ctx, x, y, 180, 'rgba(160,76,220,0.11)', 2);
        strokeCircle(ctx, x, y, 260, 'rgba(120,52,180,0.08)', 2);
        // 核心脉冲 1.3s
        cph = phase(t, 1300);
        coreScale = kf(cph, [0, 0.7, 1], [0.65, 1.0, 1.2]);
        coreOp = kf(cph, [0, 0.7, 1], [0.7, 0.14, 0]);
        radialA(ctx, x, y, 9 * coreScale, 'rgba(186,96,240,1)', coreOp);
        // 扩散环 ×2 (第二环相位 -0.43s)
        drawAnomalyRing(ctx, x, y, t, 0);
        drawAnomalyRing(ctx, x, y, t, 430);
        ctx.restore();
    }

    function drawAnomalyRing(ctx, x, y, t, delayMs) {
        var ph = phase(t + delayMs, 1300);
        var s = kf(ph, [0, 0.8, 1], [0.8, 3.4, 4]);
        var op = kf(ph, [0, 0.8, 1], [0.7, 0.08, 0]);
        strokeCircleA(ctx, x, y, 9 * s, 'rgba(186,96,240,1)', 1, op * 0.58);
    }

    // ================================================================
    // 场景 (静态层)
    // ================================================================

    // 取/建预烤离屏画布: 把 filter + 阴影一次性烤进 canvas, 之后每帧只 drawImage。
    // key 唯一标识 (图源, filter, 阴影, 目标像素尺寸); 切页时 bakedCache 整体清空。
    // 阴影按目标设备分辨率烤 (shadowBlur 不受变换矩阵缩放), 才能与旧逐帧路径 1:1 一致。
    function getBaked(renderer, image, key, targetW, targetH, filterStr, shadow) {
        if (!image) return null;
        if (typeof document === 'undefined' || !document.createElement) return null;
        var cached = renderer.bakedCache[key];
        if (cached) return cached;
        var tw = Math.max(1, Math.round(targetW));
        var th = Math.max(1, Math.round(targetH));
        var pad = shadow ? Math.ceil(shadow.blur + Math.abs(shadow.offsetY || 0) + 2) : 0;
        var cv = document.createElement('canvas');
        cv.width = tw + pad * 2;
        cv.height = th + pad * 2;
        var c = cv.getContext('2d');
        if (!c) return null;
        c.imageSmoothingEnabled = true;
        c.imageSmoothingQuality = 'high';
        if (shadow) {
            c.shadowColor = shadow.color;
            c.shadowBlur = shadow.blur;
            c.shadowOffsetY = shadow.offsetY || 0;
        }
        if (filterStr && filterStr !== 'none') c.filter = filterStr;
        try {
            c.drawImage(image, pad, pad, tw, th);
        } catch (err) {
            return null;
        }
        var entry = { canvas: cv, pad: pad };
        renderer.bakedCache[key] = entry;
        return entry;
    }

    function drawScenes(renderer, ctx, state, m) {
        var scenes = state.sceneVisuals || [];
        var i;
        for (i = 0; i < scenes.length; i += 1) {
            drawScene(renderer, ctx, scenes[i], state, m);
        }
    }

    function drawScene(renderer, ctx, scene, state, m) {
        var rect = scene && scene.rect;
        if (!rect) return;
        var lowEffects = m.lowEffects;

        var theme = (state.page && state.page.backdropTheme) || 'default';
        var hotspotIds = scene.hotspotIds || [];
        var isCurrent = hasAny(hotspotIds, [state.currentHotspotId]);
        var isFocus = isCurrent
            || hasAny(hotspotIds, [state.hoverHotspotId])
            || hasBusy(hotspotIds, state.busyLookup);
        var hierarchy = state.activeViewMode === 'hierarchy';
        var focusId = state.focusHotspotId;
        var muted = !isFocus && !!focusId && !hasAny(hotspotIds, [focusId]);

        // 透明度过渡 (旧 .map-scene-node transition 含 opacity)
        var alphaTarget = isFocus ? 1 : (hierarchy ? 0.74 : (muted ? 0.42 : 1));
        var alpha = renderer.tween('sa:' + scene.id, alphaTarget);
        var focusAmt = renderer.tween('sf:' + scene.id, isFocus ? 1 : 0);

        // 亮度/饱和瞬切 (旧 transition 不含 filter)
        var bri = 1;
        var sat = 1;
        if (isFocus) {
            bri = isCurrent ? 1.06 : 1.08;
            sat = 1.08;
        } else if (hierarchy) {
            bri = 0.74;
            sat = 0.8;
        } else if (muted) {
            bri = 0.58;
            sat = 0.7;
        }
        var baseC = theme === 'base' ? 1.05 : 1.02;     // .map-scene-layer filter (#15)
        var baseS = theme === 'base' ? 1.03 : 1.04;

        var lift = -2 * focusAmt;                       // translateY(-2px)
        var scaleAmt = 1 + 0.012 * focusAmt;            // scale(1.012)
        var dw = rect.w * scaleAmt;
        var dh = rect.h * scaleAmt;
        var dx = rect.x + rect.w / 2 - dw / 2;
        var dy = rect.y + rect.h / 2 - dh / 2 + lift;

        ctx.save();
        ctx.globalAlpha = clamp(alpha, 0, 1);

        // 可读性衬底 (仅 base 页, 还原 .map-scene-node::before)
        if (!lowEffects && theme === 'base') {
            drawReadabilityPlate(ctx, rect, lift);
        }

        var rec = renderer.loadImage(scene.assetUrl, { sharpen: !lowEffects });
        var ready = rec && rec.status === 'ready';

        ctx.save();
        if (ready && lowEffects) {
            ctx.drawImage(rec.image, dx, dy, dw, dh);
        } else if (ready) {
            // filter + 阴影预烤进离屏画布: 每帧只 drawImage, 不走 ctx.filter / shadowBlur 慢路径
            var filterStr = 'contrast(' + baseC + ') saturate('
                + (baseS * sat).toFixed(3) + ') brightness(' + bri.toFixed(3) + ')';
            var shadow = {
                color: theme === 'base' ? 'rgba(0,0,0,0.38)' : 'rgba(0,0,0,0.34)',
                blur: theme === 'base' ? 20 : 16,
                offsetY: theme === 'base' ? 12 : 10
            };
            var resolved = renderer.resolveAssetUrl(scene.assetUrl);
            var sharpEntry = renderer.sharpenCache[resolved];
            // 从终图 (锐化就绪 / 锐化永久失败回退原图) 烤; 锐化 pending 时先走老路径
            var canBake = !!(sharpEntry
                && (sharpEntry.status === 'ready' || sharpEntry.status === 'error'));
            var es = Math.min(3, m.dpr * m.contentScale);
            var tw = rect.w * es;
            var th = rect.h * es;
            var shKey = shadow ? (shadow.blur + '_' + shadow.offsetY) : 'no';
            var bakeKey = resolved + '|sc|' + filterStr + '|' + shKey + '|'
                + Math.round(tw) + 'x' + Math.round(th);
            var baked = canBake ? getBaked(renderer, rec.image, bakeKey, tw, th, filterStr, shadow) : null;
            if (baked) {
                var bw = (baked.canvas.width / es) * scaleAmt;
                var bh = (baked.canvas.height / es) * scaleAmt;
                ctx.drawImage(baked.canvas,
                    rect.x + rect.w / 2 - bw / 2,
                    rect.y + rect.h / 2 + lift - bh / 2, bw, bh);
            } else {
                // 锐化未就绪的过渡帧 / bake 失败兜底: 老的逐帧路径
                if (shadow) {
                    ctx.shadowColor = shadow.color;
                    ctx.shadowBlur = shadow.blur;
                    ctx.shadowOffsetY = shadow.offsetY;
                }
                ctx.filter = filterStr;
                ctx.drawImage(rec.image, dx, dy, dw, dh);
            }
        } else {
            ctx.fillStyle = 'rgba(200,255,76,0.06)';
            ctx.fillRect(dx, dy, dw, dh);
        }
        ctx.restore();

        // 发光层 (hover=绿 / current=青, 还原 .map-scene-node-glow)
        if (!lowEffects && focusAmt > 0.01) {
            drawSceneGlow(
                ctx, rect, lift,
                isCurrent ? '114,230,255' : '200,255,76',
                (isCurrent ? 0.94 : 0.82) * focusAmt
            );
        }
        ctx.restore();
    }

    function drawReadabilityPlate(ctx, rect, lift) {
        var pad = 7;
        var x = rect.x - pad;
        var y = rect.y - pad + lift;
        var w = rect.w + pad * 2;
        var h = rect.h + pad * 2;
        var lg;
        var rg;
        ctx.save();
        ctx.globalAlpha = ctx.globalAlpha * 0.88;
        lg = ctx.createLinearGradient(0, y, 0, y + h);
        lg.addColorStop(0, 'rgba(12,15,10,0.12)');
        lg.addColorStop(1, 'rgba(9,11,8,0.20)');
        ctx.fillStyle = lg;
        ctx.fillRect(x, y, w, h);
        rg = ctx.createRadialGradient(x + w / 2, y + h * 0.44, 0, x + w / 2, y + h * 0.44, Math.max(w, h) * 0.6);
        rg.addColorStop(0, 'rgba(18,22,14,0.34)');
        rg.addColorStop(0.58, 'rgba(10,12,9,0.14)');
        rg.addColorStop(1, 'rgba(10,12,9,0)');
        ctx.fillStyle = rg;
        ctx.fillRect(x, y, w, h);
        ctx.restore();
    }

    function drawSceneGlow(ctx, rect, lift, rgb, opacity) {
        var cx = rect.x + rect.w / 2;
        var cy = rect.y + rect.h / 2 + lift;
        var r = Math.max(rect.w, rect.h) / 2 + 6;
        var g;
        ctx.save();
        ctx.globalAlpha = ctx.globalAlpha * clamp(opacity, 0, 1);
        g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, 'rgba(' + rgb + ',0.26)');
        g.addColorStop(0.38, 'rgba(' + rgb + ',0.08)');
        g.addColorStop(0.72, 'rgba(' + rgb + ',0)');
        ctx.fillStyle = g;
        ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
        ctx.restore();
    }

    // ================================================================
    // 头像 (静态层)
    // ================================================================

    function drawAvatars(renderer, ctx, state, lowEffects) {
        var statics = state.staticAvatars || [];
        var dynamics = state.dynamicAvatars || [];
        var i;
        for (i = 0; i < statics.length; i += 1) {
            drawAvatar(renderer, ctx, statics[i],
                'static:' + (statics[i].id || statics[i].hotspotId || ('s' + i)), state, lowEffects);
        }
        for (i = 0; i < dynamics.length; i += 1) {
            if (!renderer.lastDynamicAvatarUrl) renderer.lastDynamicAvatarUrl = dynamics[i].assetUrl || '';
            drawAvatar(renderer, ctx, dynamics[i],
                'dynamic:' + (dynamics[i].id || dynamics[i].hotspotId || ('d' + i)), state, lowEffects);
        }
    }

    function drawAvatar(renderer, ctx, avatar, key, state, lowEffects) {
        var rect = avatar && avatar.rect;
        if (!rect) return;

        var focusId = state.focusHotspotId;
        var isFocus = !!avatar.hotspotId
            && (avatar.hotspotId === state.currentHotspotId || avatar.hotspotId === focusId);
        var muted = !isFocus && !!focusId && !!avatar.hotspotId && avatar.hotspotId !== focusId;

        var alpha = renderer.tween('aa:' + key, muted ? 0.34 : 1);
        var focusAmt = renderer.tween('af:' + key, isFocus ? 1 : 0);

        var scaleAmt = 1 + 0.04 * focusAmt;
        var lift = -1 * focusAmt;
        var cx = rect.x + rect.w / 2;
        var cy = rect.y + rect.h / 2 + lift;
        var r = (Math.max(rect.w, rect.h) / 2) * scaleAmt;
        var rec;
        var fg;

        if (r <= 0) return;

        ctx.save();
        ctx.globalAlpha = clamp(alpha, 0, 1);

        // 投影 + 环境辉光 (还原 .map-avatar box-shadow)
        if (!lowEffects) {
            // 投影: 径向渐变软盘替代 shadowBlur (免每帧 shadowBlur 慢路径)
            radialA(ctx, cx, cy, r + 12, 'rgba(0,0,0,1)', 0.5);
            radialA(ctx, cx, cy, r + 8 + 6 * focusAmt, 'rgba(190,255,64,1)', 0.12 + 0.10 * focusAmt);
            if (focusAmt > 0.01) {
                radialA(ctx, cx, cy, r + 10, 'rgba(114,230,255,1)', 0.16 * focusAmt);
            }
        }

        // 圆形裁剪 + 底色 + 头像图 / fallback
        ctx.save();
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, TWO_PI);
        ctx.clip();
        ctx.fillStyle = 'rgba(6,8,6,0.82)';
        ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
        rec = renderer.loadImage(avatar.assetUrl);
        if (rec && rec.status === 'ready') {
            if (muted && !lowEffects) ctx.filter = 'saturate(0.65) brightness(0.72)';
            ctx.drawImage(rec.image, cx - r, cy - r, r * 2, r * 2);
            ctx.filter = 'none';
        } else {
            fg = ctx.createLinearGradient(0, cy - r, 0, cy + r);
            fg.addColorStop(0, 'rgba(18,22,18,0.96)');
            fg.addColorStop(1, 'rgba(8,10,8,0.92)');
            ctx.fillStyle = fg;
            ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
            ctx.fillStyle = '#dff3b8';
            ctx.font = 'bold 16px "Microsoft YaHei",sans-serif';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(fallbackChar(avatar.label), cx, cy);
        }
        ctx.restore();

        // 边框 (focus 时由 0.25 → 0.58)
        ctx.strokeStyle = 'rgba(220,255,128,' + (0.25 + 0.33 * focusAmt).toFixed(3) + ')';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, TWO_PI);
        ctx.stroke();

        ctx.restore();
    }

    // ================================================================
    // 任务环 / 反馈标记 / 提示 / 未开放提示 (动态层)
    // ================================================================

    function drawTaskRings(ctx, state, lowEffects, t) {
        var rings = state.taskRings || [];
        var i;
        var p;
        var ph;
        var avR;
        var ringR;
        var ringOp;
        var waveR;
        var waveOp;
        for (i = 0; i < rings.length; i += 1) {
            p = rings[i].point;
            if (!p) continue;
            // avatarRadius>0 = 命中目标 NPC 头像 → 环套住头像 (半径 = 头像半径 + 间距);
            // 0 = 未命中头像 → 回退旧固定小环 (radius 11 / wave 25)
            avR = rings[i].avatarRadius || 0;
            ph = phase(t, 1450);
            ringOp = kf(ph, [0, 0.7, 1], [0.92, 0.86, 0.76]);
            if (avR > 0) {
                // 套头像: 呼吸用加性微幅, 不让大半径把脉冲整体放大 (等价旧 11*[.92..1.22] 的振幅)
                ringR = avR + TASK_RING_GAP + kf(ph, [0, 0.7, 1], [-0.9, 2.0, 2.4]);
                // 扩散波从环外缘向外涟漪
                waveR = avR + TASK_RING_GAP + kf(ph, [0, 0.7, 1], [0, 16, 22]);
            } else {
                // 旧固定环: scale .92→1.22 / wave .82→2.1
                ringR = 11 * kf(ph, [0, 0.7, 1], [0.92, 1.18, 1.22]);
                waveR = 25 * kf(ph, [0, 0.7, 1], [0.82, 1.9, 2.1]);
            }
            // 扩散波 (低性能隐藏): opacity .78→0
            if (!lowEffects) {
                waveOp = kf(ph, [0, 0.7, 1], [0.78, 0.08, 0]);
                strokeCircleA(ctx, p.x, p.y, waveR, 'rgba(255,128,128,1)', 2, waveOp * 0.42);
            }
            // 环本体
            ctx.save();
            ctx.globalAlpha = ringOp;
            ctx.strokeStyle = 'rgba(255,77,77,0.92)';
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.arc(p.x, p.y, ringR, 0, TWO_PI);
            if (avR <= 0) {
                // 旧固定小环保留淡红心; 套头像的大环只描边, 不给 NPC 头像蒙一层红
                ctx.fillStyle = 'rgba(255,77,77,0.10)';
                ctx.fill();
            }
            ctx.stroke();
            ctx.restore();
        }
    }

    function drawMarkers(ctx, state, lowEffects, t) {
        var markers = state.feedbackMarkers || [];
        var i;
        for (i = 0; i < markers.length; i += 1) {
            drawMarker(ctx, markers[i], lowEffects, t);
        }
    }

    function drawMarker(ctx, marker, lowEffects, t) {
        var p = marker && marker.point;
        var isCurrent = marker && marker.kind === 'currentLocation';
        var r;
        var ph;
        var pulseScale;
        var pulseOp;
        if (!p) return;
        r = isCurrent ? 8 : 7;
        ctx.save();
        // 雷达扫针 (仅 currentLocation, 非低性能) — conic 6s
        if (isCurrent && !lowEffects) {
            drawRadarSweep(ctx, p.x, p.y, r + 18, t);
        }
        if (!lowEffects) {
            // 外发光 (box-shadow 近似)
            radialA(ctx, p.x, p.y, r + (isCurrent ? 13 : 11), 'rgba(114,230,255,1)', isCurrent ? 0.30 : 0.26);
            // 脉冲环 ::after 1.8s: scale .8→1.8, opacity .8→0
            ph = phase(t, 1800);
            pulseScale = kf(ph, [0, 0.7, 1], [0.8, 1.8, 1.8]);
            pulseOp = kf(ph, [0, 0.7, 1], [0.8, 0, 0]);
            strokeCircleA(ctx, p.x, p.y, (r + 7) * pulseScale, 'rgba(114,230,255,1)', 1, pulseOp * 0.42);
        }
        // marker 本体: 青色环 (亮边 + 淡心)
        ctx.fillStyle = 'rgba(114,230,255,0.18)';
        ctx.strokeStyle = 'rgba(114,230,255,0.94)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(p.x, p.y, r, 0, TWO_PI);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
    }

    function drawRadarSweep(ctx, x, y, radius, t) {
        var ang = phase(t, 6000) * TWO_PI;
        var g;
        ctx.save();
        ctx.globalAlpha = 0.82;
        if (typeof ctx.createConicGradient === 'function') {
            g = ctx.createConicGradient(ang, x, y);
            g.addColorStop(0, 'rgba(114,230,255,0.45)');
            g.addColorStop(30 / 360, 'rgba(114,230,255,0.18)');
            g.addColorStop(60 / 360, 'rgba(114,230,255,0)');
            g.addColorStop(1, 'rgba(114,230,255,0)');
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(x, y, radius, 0, TWO_PI);
            ctx.fill();
        } else {
            ctx.fillStyle = 'rgba(114,230,255,0.22)';
            ctx.beginPath();
            ctx.moveTo(x, y);
            ctx.arc(x, y, radius, ang, ang + Math.PI / 6);
            ctx.closePath();
            ctx.fill();
        }
        ctx.restore();
    }

    function drawTips(ctx, state, t) {
        var tips = state.feedbackTips || [];
        var i;
        for (i = 0; i < tips.length; i += 1) {
            drawTip(ctx, tips[i], t);
        }
    }

    // 提示气泡: 锚点正上方居中 + 朝下箭头 + 1.8s 上下浮动 (还原 .map-feedback-tip)
    function drawTip(ctx, tip, t) {
        var p = tip && tip.point;
        var text = tip && tip.label ? String(tip.label) : '';
        var accent = tip && tip.tone === 'accent';
        var floatY;
        var boxW;
        var boxH = 18;
        var bx;
        var by;
        if (!p || !text) return;
        floatY = -10 - 3 * (0.5 - 0.5 * Math.cos(phase(t, 1800) * TWO_PI));
        ctx.save();
        ctx.font = '10px "Consolas","Microsoft YaHei",monospace';
        boxW = ctx.measureText(text).width + 16;
        bx = p.x - boxW / 2;
        by = p.y + floatY - boxH;
        ctx.fillStyle = accent ? 'rgba(8,16,22,0.92)' : 'rgba(10,14,8,0.92)';
        ctx.strokeStyle = accent ? 'rgba(114,230,255,0.34)' : 'rgba(200,255,76,0.32)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.rect(bx, by, boxW, boxH);
        ctx.fill();
        // 朝下箭头
        ctx.beginPath();
        ctx.moveTo(p.x - 5, by + boxH);
        ctx.lineTo(p.x + 5, by + boxH);
        ctx.lineTo(p.x, by + boxH + 6);
        ctx.closePath();
        ctx.fill();
        ctx.beginPath();
        ctx.rect(bx, by, boxW, boxH);
        ctx.stroke();
        ctx.fillStyle = accent ? '#b7f1ff' : '#e7ffb2';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(text, p.x, by + boxH / 2);
        ctx.restore();
    }

    function drawHints(ctx, state, t) {
        var hints = state.flashHints || [];
        var i;
        for (i = 0; i < hints.length; i += 1) {
            drawHint(ctx, hints[i], t);
        }
    }

    // 未开放提示: 暖橙警示样式 + 1.6s 闪烁 (还原 .map-feedback-hint)
    function drawHint(ctx, hint, t) {
        var p = hint && hint.point;
        var text = hint && hint.label ? String(hint.label) : '未开放';
        var blink;
        var boxW;
        var boxH = 20;
        var bx;
        var by;
        if (!p) return;
        blink = 0.5 - 0.5 * Math.cos(phase(t, 1600) * TWO_PI);
        ctx.save();
        ctx.globalAlpha = 0.84 + 0.16 * blink;
        ctx.font = '10px "Consolas","Microsoft YaHei",monospace';
        boxW = ctx.measureText(text).width + 16;
        bx = p.x - boxW / 2;
        by = p.y - boxH - 2 * blink;
        ctx.fillStyle = 'rgba(31,10,7,0.92)';
        ctx.strokeStyle = 'rgba(255,142,96,0.46)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.rect(bx, by, boxW, boxH);
        ctx.fill();
        ctx.beginPath();
        ctx.moveTo(p.x - 4, by + boxH);
        ctx.lineTo(p.x + 4, by + boxH);
        ctx.lineTo(p.x, by + boxH + 5);
        ctx.closePath();
        ctx.fill();
        ctx.beginPath();
        ctx.rect(bx, by, boxW, boxH);
        ctx.stroke();
        ctx.fillStyle = '#ffd3bf';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(text, p.x, by + boxH / 2);
        ctx.restore();
    }

    // ================================================================
    // 绘制原语
    // ================================================================

    function radial(ctx, x, y, radius, color) {
        radialA(ctx, x, y, radius, color, 1);
    }

    function radialA(ctx, x, y, radius, color, alpha) {
        var g;
        if (radius <= 0) return;
        ctx.save();
        ctx.globalAlpha = ctx.globalAlpha * clamp(alpha == null ? 1 : alpha, 0, 1);
        g = ctx.createRadialGradient(x, y, 0, x, y, radius);
        g.addColorStop(0, color);
        g.addColorStop(1, toTransparent(color));
        ctx.fillStyle = g;
        ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2);
        ctx.restore();
    }

    function overlay(ctx, color, w, h) {
        ctx.fillStyle = color;
        ctx.fillRect(0, 0, w, h);
    }

    function strokeCircle(ctx, x, y, radius, color, width) {
        strokeCircleA(ctx, x, y, radius, color, width, 1);
    }

    function strokeCircleA(ctx, x, y, radius, color, width, alpha) {
        if (radius <= 0) return;
        ctx.save();
        ctx.globalAlpha = ctx.globalAlpha * clamp(alpha == null ? 1 : alpha, 0, 1);
        ctx.strokeStyle = color;
        ctx.lineWidth = width || 1;
        ctx.beginPath();
        ctx.arc(x, y, radius, 0, TWO_PI);
        ctx.stroke();
        ctx.restore();
    }

    // 锥形扇区 (扇形射界): 从 fromDeg 起 spanDeg 度内可见, 之后透明
    function conicArc(ctx, x, y, radius, fromDeg, spanDeg, color) {
        var g;
        var a0;
        ctx.save();
        if (typeof ctx.createConicGradient === 'function') {
            g = ctx.createConicGradient(fromDeg * Math.PI / 180, x, y);
            g.addColorStop(0, color);
            g.addColorStop(Math.min(0.999, spanDeg / 360), toTransparent(color));
            g.addColorStop(1, toTransparent(color));
            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(x, y, radius, 0, TWO_PI);
            ctx.fill();
        } else {
            a0 = fromDeg * Math.PI / 180;
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.moveTo(x, y);
            ctx.arc(x, y, radius, a0, a0 + spanDeg * Math.PI / 180);
            ctx.closePath();
            ctx.fill();
        }
        ctx.restore();
    }

    // 近水平重复条纹 (deg ~= 与水平夹角)
    function stripes(ctx, w, h, gap, thick, color, deg) {
        var slope = Math.tan(deg * Math.PI / 180);
        var span = Math.abs(w * slope);
        var y;
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth = thick;
        ctx.beginPath();
        for (y = -span; y <= h + span; y += gap) {
            ctx.moveTo(0, y);
            ctx.lineTo(w, y + w * slope);
        }
        ctx.stroke();
        ctx.restore();
    }

    // 单条贯穿斜带 (pos: 0..1 经过点比例; deg: 角度)
    function diagBand(ctx, w, h, pos, deg, color, thick) {
        var rad = deg * Math.PI / 180;
        var cx = w * pos;
        var cy = h * pos;
        var len = w + h;
        var dx = Math.cos(rad) * len;
        var dy = Math.sin(rad) * len;
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth = thick;
        ctx.beginPath();
        ctx.moveTo(cx - dx, cy - dy);
        ctx.lineTo(cx + dx, cy + dy);
        ctx.stroke();
        ctx.restore();
    }

    // 等距斜向重复条纹 (告警斜纹)
    function diagStripes(ctx, w, h, deg, gap, color, thick) {
        var rad = deg * Math.PI / 180;
        var nx = Math.cos(rad);
        var ny = Math.sin(rad);
        var diag = w + h;
        var d;
        var px;
        var py;
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth = thick;
        ctx.beginPath();
        for (d = -diag; d <= diag; d += gap) {
            px = d * nx;
            py = d * ny;
            ctx.moveTo(px + ny * diag, py - nx * diag);
            ctx.lineTo(px - ny * diag, py + nx * diag);
        }
        ctx.stroke();
        ctx.restore();
    }

    // ================================================================
    // 工具函数
    // ================================================================

    function hasAny(ids, needles) {
        var i;
        if (!ids || !ids.length || !needles || !needles.length) return false;
        for (i = 0; i < ids.length; i += 1) {
            if (needles.indexOf(ids[i]) >= 0) return true;
        }
        return false;
    }

    function hasBusy(ids, lookup) {
        var i;
        if (!ids || !ids.length || !lookup) return false;
        for (i = 0; i < ids.length; i += 1) {
            if (lookup[ids[i]]) return true;
        }
        return false;
    }

    // 周期相位 [0,1)
    function phase(t, periodMs) {
        var p = (t % periodMs) / periodMs;
        if (p < 0) p += 1;
        return p;
    }

    // 关键帧分段线性插值
    function kf(ph, stops, vals) {
        var i;
        var k;
        if (ph <= stops[0]) return vals[0];
        for (i = 1; i < stops.length; i += 1) {
            if (ph <= stops[i]) {
                k = (ph - stops[i - 1]) / (stops[i] - stops[i - 1]);
                return vals[i - 1] + (vals[i] - vals[i - 1]) * k;
            }
        }
        return vals[vals.length - 1];
    }

    function lerp(a, b, k) {
        return a + (b - a) * k;
    }

    function clamp(v, lo, hi) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    }

    function toTransparent(color) {
        return String(color).replace(/rgba?\(([^)]+)\)/, function(m, body) {
            var parts = body.split(',');
            return 'rgba(' + parts[0] + ',' + parts[1] + ',' + parts[2] + ',0)';
        });
    }

    function fallbackChar(label) {
        var s = label ? String(label).replace(/^\s+/, '') : '';
        return s ? s.charAt(0) : '?';
    }

    function getDpr() {
        if (typeof window === 'undefined') return 1;
        return Math.max(1, Math.min(3, Number(window.devicePixelRatio) || 1));
    }

    function nowMs() {
        return (typeof performance !== 'undefined' && performance.now)
            ? performance.now()
            : Date.now();
    }

    function requestFrame(cb) {
        return (typeof requestAnimationFrame === 'function')
            ? requestAnimationFrame(cb)
            : setTimeout(function() { cb(nowMs()); }, 16);
    }

    function identity(value) {
        return value;
    }

    return Renderer;
})();
