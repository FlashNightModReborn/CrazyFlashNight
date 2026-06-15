var MapHittestEngine = (function() {
    'use strict';

    // ================================================================
    // 地图面板像素级 hittest 引擎 · color picking buffer
    //
    //   每页一张 1031x608 OffscreenCanvas (或回退 HTMLCanvas), 不上屏。
    //   对每个 sceneVisual: 临时 OffscreenCanvas (rect 大小) → drawImage →
    //   Uint32Array 二值化 (alpha > ALPHA_THRESHOLD 的像素写纯 ID-color),
    //   再 putImageData 到主 hitmap; 后 visual 覆盖前 visual。
    //
    //   query(pageId, pageX, pageY): getImageData(1x1) → 解码 RGB → byColor 查表。
    //   返回 { visualId, hotspotIds, filterIds } — 调用方负责按 visible/enabled 过滤。
    //
    //   坐标契约 (铁律):
    //     - 临时 canvas 尺寸: Math.ceil(rect.w/h)
    //     - 写入主 hitmap 偏移: Math.round(rect.x/y)
    //     - query: Math.round(pageX/Y)
    //     - 命中阈值: alpha > ALPHA_THRESHOLD (抗锯齿边缘忽略)
    //
    //   hitmap 按 (page, filter 可见 visual 子集) 维度构建 — 只放当前 filter 可见的
    //   sceneVisuals。pageId 由调用方传入复合键 = page.id + '::' + 子集内容签名 (visual id
    //   按 z 顺序拼接, 见 map-panel.js hitmapKeyFor)。产生相同 visual 子集的 filter 自动复用
    //   同一张 hitmap (如 'all' 与 'hierarchy' 都是整页全集 → 同键, 不重复占 LRU 槽)。
    //   缘由 (2026-06-15 修): hitmap 单层 color-picking 每像素只记一个归属, 后画覆盖先画。
    //   若整页全部 visuals 共用一张, 楼层重叠处只剩"最后画的"那个可点; 屋顶 (index 0 最先画)
    //   被其后 9 个楼层 visual (大厅占 67%/酒吧 25%…) 覆盖, 切屋顶 filter 时这些像素归属被
    //   过滤掉 → 屋顶只剩独占的左下角可点。改为子集维度建图后判定区与显示精确一致。
    //   filter 仍由调用方在 query 后用 visible/enabled 兜底 (锁关等), 但不再承担"切楼层"职责。
    //   切层构建窗口: 查询键同步切到新子集键, 未就绪时 query 返回 null; 调用方 (map-panel.js +
    //   hitcapture) 用 isReady 把窗口内点击暂存、就绪后重放 → 切层首点不失效。不做"回退旧图":
    //   旧整页图里目标楼层像素多被其它楼层占据, 回退命不中 (见上)。
    // ================================================================

    var ALPHA_THRESHOLD = 32;
    var MAX_VISUALS = 0xFFFFFE;     // 16M-2, 远超实际 36/page 需求

    // LRU 槽位上限. 键现为内容签名复合键 (page.id + '::' + visual 子集签名), 每张 hitmap
    // ImageData ~2.5MB; 仍保持 slot=2 兜内存 (典型流: 整页全集图 → 点楼层 filter → 选关, 两键即够).
    // 调用方按 LRU 最近用顺序保活当前查询键: 切层 ensurePage 新键时, 当前键是上一个 ensure 的
    // 最近项 → 必随新键一起留在 2 槽内, 构建窗口内可继续 query (零失效窗口靠它兜底)。
    // 同 page 反复切 3+ 楼层会让最旧的子集图 evict 后重建, 但 DOM visual 层开页时已把全部
    // PNG 预载入浏览器缓存, 暖重建 (仅 drawImage + getImageData, 不走网络) 很廉价 → slot=2 足够。
    var MAX_PAGES = 2;

    // cache[pageId] = {
    //     ready: bool,
    //     promise: Promise<void>,
    //     width: int, height: int,
    //     canvas: OffscreenCanvas|HTMLCanvasElement,
    //     ctx: CanvasRenderingContext2D,
    //     byColor: Object<colorKey:number, { visualId, hotspotIds, filterIds }>,
    //     visualCount: int,
    //     buildMs: number
    // }
    var cache = {};
    // _lru 末尾 = 最近用. ensurePage 命中或新建都把 pageId 上移到末尾,
    // 新建后 cache.size > MAX_PAGES 时 shift 最旧的 evict.
    var _lru = [];
    var lastError = null;

    function packPixel(r, g, b) {
        // 小端机器 Uint32Array: 内存字节序 [R,G,B,A] -> uint32 = A<<24 | B<<16 | G<<8 | R
        return (0xff << 24) | ((b & 0xff) << 16) | ((g & 0xff) << 8) | (r & 0xff);
    }

    function colorKeyFor(i) {
        // i = sceneVisuals 索引, color = i+1 (避免 0 = 空像素歧义)
        return i + 1;
    }

    function unpackKey(r, g, b) {
        return ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff);
    }

    function createOffscreen(w, h) {
        if (typeof OffscreenCanvas !== 'undefined') {
            try { return new OffscreenCanvas(w, h); } catch (e) { /* fallthrough */ }
        }
        if (typeof document !== 'undefined' && document.createElement) {
            var cv = document.createElement('canvas');
            cv.width = w;
            cv.height = h;
            return cv;
        }
        return null;
    }

    function loadImage(url) {
        return new Promise(function(resolve, reject) {
            var img = new Image();
            img.onload = function() { resolve(img); };
            img.onerror = function() { reject(new Error('hittest: failed to load ' + url)); };
            img.src = url;
        });
    }

    function decodeImage(img) {
        if (img && typeof img.decode === 'function') {
            return img.decode().then(function() { return img; }, function() { return img; });
        }
        return Promise.resolve(img);
    }

    // 把单个 visual 的 PNG 形状用 ID-color 二值化写入主 hitmap。
    // 后 visual 覆盖前 visual (与 drawScenes z 顺序一致)。
    function renderVisualToHitmap(pageEntry, index, img, visual) {
        var rect = visual && visual.rect;
        if (!rect) return;
        var tw = Math.ceil(rect.w);
        var th = Math.ceil(rect.h);
        if (tw <= 0 || th <= 0) return;

        var tmp = createOffscreen(tw, th);
        if (!tmp) return;
        // willReadFrequently: 此临时画布 drawImage 后立刻 getImageData 二值化, 强制 CPU 后端,
        // 避免 GPU 纹理上传 + 逐 visual readback 的往返 (与主 hitmap 同策略)。
        var tc = tmp.getContext('2d', { willReadFrequently: true });
        if (!tc) return;
        try {
            tc.drawImage(img, 0, 0, tw, th);
        } catch (e) {
            // 跨域 / decode 失败 — 跳过此 visual, 但不阻塞其它
            lastError = String((e && e.message) || e);
            return;
        }

        var vData;
        try {
            vData = tc.getImageData(0, 0, tw, th);
        } catch (e2) {
            lastError = String((e2 && e2.message) || e2);
            return;
        }
        var v32 = new Uint32Array(vData.data.buffer);

        var dx = Math.round(rect.x);
        var dy = Math.round(rect.y);
        var ctx = pageEntry.ctx;

        // 钳到主 hitmap 范围 (rect 可能伸出边界)
        var sx = 0;
        var sy = 0;
        var copyW = tw;
        var copyH = th;
        if (dx < 0) { sx = -dx; copyW += dx; dx = 0; }
        if (dy < 0) { sy = -dy; copyH += dy; dy = 0; }
        if (dx + copyW > pageEntry.width) copyW = pageEntry.width - dx;
        if (dy + copyH > pageEntry.height) copyH = pageEntry.height - dy;
        if (copyW <= 0 || copyH <= 0) return;

        var mData;
        try {
            mData = ctx.getImageData(dx, dy, copyW, copyH);
        } catch (e3) {
            lastError = String((e3 && e3.message) || e3);
            return;
        }
        var m32 = new Uint32Array(mData.data.buffer);

        var key = colorKeyFor(index);
        var idPx = packPixel((key >> 16) & 0xff, (key >> 8) & 0xff, key & 0xff);

        var row;
        var col;
        var srcOff;
        var dstOff;
        for (row = 0; row < copyH; row += 1) {
            srcOff = (sy + row) * tw + sx;
            dstOff = row * copyW;
            for (col = 0; col < copyW; col += 1) {
                // 取 alpha (Uint32 高 8 位)
                if ((v32[srcOff + col] >>> 24) > ALPHA_THRESHOLD) {
                    m32[dstOff + col] = idPx;
                }
            }
        }
        ctx.putImageData(mData, dx, dy);
    }

    function buildPage(page, resolveAssetUrl) {
        var visuals = (page && page.sceneVisuals) || [];
        var w = (page && page.width) || 1031;
        var h = (page && page.height) || 608;

        if (visuals.length > MAX_VISUALS) {
            return Promise.reject(new Error('hittest: too many visuals (' + visuals.length + ' > ' + MAX_VISUALS + ')'));
        }

        var canvas = createOffscreen(w, h);
        if (!canvas) return Promise.reject(new Error('hittest: cannot create offscreen canvas'));
        // willReadFrequently: 告知浏览器后续会大量 getImageData (query 每次命中 + build 整层写入),
        // 避免 GPU-backed canvas 反复 readback 的 perf 警告。
        var ctx = canvas.getContext('2d', { willReadFrequently: true });
        if (!ctx) return Promise.reject(new Error('hittest: cannot get 2d context'));

        var byColor = {};
        var i;
        for (i = 0; i < visuals.length; i += 1) {
            byColor[colorKeyFor(i)] = {
                visualId: visuals[i].id || ('v' + i),
                hotspotIds: (visuals[i].hotspotIds || []).slice(),
                filterIds: (visuals[i].filterIds || []).slice()
            };
        }

        var pageEntry = {
            ready: false,
            promise: null,
            width: w,
            height: h,
            canvas: canvas,
            ctx: ctx,
            byColor: byColor,
            visualCount: visuals.length,
            buildMs: 0
        };
        cache[page.id] = pageEntry;

        var t0 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();

        // 顺序 drawImage (源于 z 顺序), decode 并行
        var loaders = visuals.map(function(v) {
            var resolved = resolveAssetUrl ? resolveAssetUrl(v.assetUrl) : v.assetUrl;
            return loadImage(resolved).then(decodeImage, function(err) {
                lastError = String((err && err.message) || err);
                return null;
            });
        });

        pageEntry.promise = Promise.all(loaders).then(function(images) {
            var idx;
            for (idx = 0; idx < visuals.length; idx += 1) {
                if (images[idx]) {
                    renderVisualToHitmap(pageEntry, idx, images[idx], visuals[idx]);
                }
            }
            pageEntry.ready = true;
            var t1 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
            pageEntry.buildMs = t1 - t0;
        });

        return pageEntry.promise;
    }

    function touchLru(pageId) {
        var idx = _lru.indexOf(pageId);
        if (idx >= 0) _lru.splice(idx, 1);
        _lru.push(pageId);
    }

    // 新建后驱逐多余条目. 命中既有 entry 不需驱逐 (size 不变).
    // building 中的 entry (ready=false) 同样可被 evict — 其 Promise 不取消, 写入 detached entry,
    // cache[id] 已删, 下次 ensurePage 会重建; 浪费一次 build 但不卡命中路径.
    function evictIfNeeded() {
        while (_lru.length > MAX_PAGES) {
            var evictId = _lru.shift();
            if (cache[evictId]) delete cache[evictId];
        }
    }

    function ensurePage(page, resolveAssetUrl) {
        if (!page || !page.id) return Promise.reject(new Error('hittest: page or page.id missing'));
        var entry = cache[page.id];
        if (entry && entry.promise) {
            touchLru(page.id);
            return entry.promise;
        }
        touchLru(page.id);
        var promise = buildPage(page, resolveAssetUrl);
        evictIfNeeded();
        return promise;
    }

    function query(pageId, pageX, pageY) {
        var entry = cache[pageId];
        if (!entry || !entry.ready) return null;
        var px = Math.round(pageX);
        var py = Math.round(pageY);
        if (px < 0 || px >= entry.width || py < 0 || py >= entry.height) return null;
        var data;
        try {
            data = entry.ctx.getImageData(px, py, 1, 1).data;
        } catch (e) {
            lastError = String((e && e.message) || e);
            return null;
        }
        if (data[3] <= ALPHA_THRESHOLD) return null;
        var key = unpackKey(data[0], data[1], data[2]);
        return entry.byColor[key] || null;
    }

    // 该键对应 hitmap 是否已构建就绪 (可被 query 命中). 调用方据此决定是否需要
    // 等待异步构建完成, 还是可立即原子切换查询键 (零失效窗口)。
    function isReady(pageId) {
        var entry = cache[pageId];
        return !!(entry && entry.ready);
    }

    // 释放全部缓存 hitmap. 内容签名复合键无法靠真实 pageId 列表逐个 discard,
    // 关面板回收时统一清空 (下次 ensurePage 按需重建)。
    function discardAll() {
        cache = {};
        _lru = [];
    }

    function debugState() {
        var pages = {};
        var k;
        for (k in cache) {
            if (Object.prototype.hasOwnProperty.call(cache, k)) {
                pages[k] = {
                    ready: cache[k].ready,
                    width: cache[k].width,
                    height: cache[k].height,
                    visualCount: cache[k].visualCount,
                    byColorEntries: Object.keys(cache[k].byColor).length,
                    buildMs: Math.round(cache[k].buildMs * 100) / 100
                };
            }
        }
        return {
            pages: pages,
            alphaThreshold: ALPHA_THRESHOLD,
            lastError: lastError,
            lruOrder: _lru.slice(),   // 末尾 = 最近用
            maxPages: MAX_PAGES
        };
    }

    return {
        ensurePage: ensurePage,
        query: query,
        isReady: isReady,
        discardAll: discardAll,
        debugState: debugState
    };
})();

if (typeof window !== 'undefined') {
    window.MapHittestEngine = MapHittestEngine;
}
