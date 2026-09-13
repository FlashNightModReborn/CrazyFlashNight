/**
 * LiveDialoguePortraits — 动态人物表情的对话立绘渲染入口。
 *
 * 输入是独立 appearance 对象 {gender,face,hair,mask,head,body,leg,hand,foot,neck,
 * keyMap?} + 显式 expression；输出是基于 DressupDollRenderer 的可渲染 state、
 * 稳定 cache identity 与 768 档 PNG dataURL。表情选帧走
 * DressupDollRenderer 的显式表情路径（skin.expressions 标签帧），
 * 不把 static-first-frame 脸型当普通时间轴动画播放。
 *
 * 边界：scene / request 归属在调用方（live-portrait-bake.js / dialogue-view）；
 * 本模块不重写主角模板为当前玩家，不碰 doll-bake 的 256 图标协议。
 */
var LiveDialoguePortraits = (function() {
    'use strict';

    var browserWindow = typeof window !== 'undefined' ? window : {};
    var browserDocument = typeof document !== 'undefined' ? document : null;
    var MANIFEST_URL = browserWindow.CF7_DRESSUP_MANIFEST_URL || 'assets/dressup/manifest.json';
    var DATA_URL_PREFIX = 'data:image/png;base64,';
    var DEFAULT_EXPRESSION = '普通';
    var DEFAULT_SIZE = 768;
    var DEFAULT_TIMEOUT_MS = 10000;
    var DEFAULT_POLL_MS = 40;
    var DEFAULT_MIN_ALPHA_PIXELS = 64;
    // appearance 白名单字段（与 doll tuple / C# 归一化键同序）
    var APPEARANCE_FIELDS = ['face', 'hair', 'mask', 'head', 'body', 'leg', 'hand', 'foot', 'neck', 'gender'];
    var EQUIPMENT_SLOTS = ['head', 'body', 'leg', 'hand', 'foot', 'neck'];
    var FIELD_FACE = '脸型';
    var FIELD_HAIR = '发型';
    var FIELD_MASK = '面具';
    var BUST_FIT_FIELDS = ['脸型', '发型', '面具', '身体', '上臂'];
    var FACE_BY_ID_FALLBACK = {
        '0': '女变装-基本脸型',
        '1': '男变装-基本脸型'
    };
    // 与 merc-portrait-renderer.js 的 HAIR_COMPAT_ALIASES 同源（两边保持逐字节一致；
    // 该文件不可改，故在此复制而非引入 MercPortraits 依赖）。
    var HAIR_COMPAT_ALIASES = {
        '发型-女式-红马尾': '发型-女式-玫红色马尾',
        '发型-女式-白长发': '发型-女式-银色清爽直发',
        '发型-男式-黑尖长发': '发型-男式-黑长发',
        '发型-男式-黑短发': '发型-男式-精武短发'
    };

    var _manifest = null;
    var _manifestPromise = null;
    var _dataUrlCache = {};
    var _dataUrlCacheOrder = [];
    var _maxCacheEntries = 64;

    function loadManifest() {
        if (_manifest) return Promise.resolve(_manifest);
        if (typeof DressupDollRenderer === 'undefined' || !DressupDollRenderer) {
            return Promise.reject(new Error('DressupDollRenderer is not loaded'));
        }
        if (!_manifestPromise) {
            _manifestPromise = DressupDollRenderer.loadManifest(MANIFEST_URL).then(function(manifest) {
                _manifest = manifest;
                return manifest;
            }).catch(function(error) {
                _manifestPromise = null;
                throw error;
            });
        }
        return _manifestPromise;
    }

    function manifestOf(options) {
        return (options && options.manifest) || _manifest || null;
    }

    function normalizeGender(value) {
        var raw = value === undefined || value === null ? '' : String(value);
        return (raw === '男' || raw === '主角-男' || raw === '1') ? '男' : '女';
    }

    function stripEquipName(value) {
        if (value === undefined || value === null) return '';
        return String(value).split('#', 1)[0];
    }

    function skinCovered(manifest, key) {
        return !!(key && manifest && manifest.skinKeys && manifest.skinKeys[key]
            && manifest.skinKeys[key].covered);
    }

    function normalizeFace(manifest, raw, gender) {
        var appearance = manifest && manifest.appearance ? manifest.appearance : {};
        raw = raw === undefined || raw === null ? '' : String(raw);
        if (raw !== '') {
            if (appearance.faceById && appearance.faceById[raw]) {
                return appearance.faceById[raw];
            }
            if (skinCovered(manifest, raw)) return raw;
        }
        var fallback = FACE_BY_ID_FALLBACK[gender === '男' ? '1' : '0'];
        return fallback || '';
    }

    function normalizeHair(manifest, raw, gender, headItemName) {
        var appearance = manifest && manifest.appearance ? manifest.appearance : {};
        raw = raw === undefined || raw === null ? '' : String(raw);
        if (appearance.hairById && appearance.hairById[raw]) {
            raw = appearance.hairById[raw];
        }
        if (skinCovered(manifest, raw)) return raw;
        var alias = HAIR_COMPAT_ALIASES[raw];
        return alias && skinCovered(manifest, alias) ? alias : '';
    }

    function normalizeMask(manifest, raw) {
        raw = raw === undefined || raw === null ? '' : String(raw);
        return skinCovered(manifest, raw) ? raw : '';
    }

    /**
     * appearance → { gender, fields, equipment, keyMap, normalizedAppearance }
     * fields 是 manifest 中文 field 名 → skinKey；equipment 是槽位 → 物品名，
     * 由 buildStateFromEquipment 展开为 item.fieldsByGender 合并。
     * normalizedAppearance 用英文槽位键记录归一化后的取值，供 identity/对账。
     */
    function normalizeAppearance(manifest, appearance) {
        appearance = appearance || {};
        var gender = normalizeGender(appearance.gender);
        var equipment = {};
        EQUIPMENT_SLOTS.forEach(function(slot) {
            var name = stripEquipName(appearance[slot]);
            if (name) equipment[slot] = name;
        });
        var headItem = equipment.head && manifest && manifest.items
            ? manifest.items[equipment.head] : null;
        var fields = {};
        var face = normalizeFace(manifest, appearance.face, gender);
        if (face) fields[FIELD_FACE] = face;
        var hair = normalizeHair(manifest, appearance.hair, gender, equipment.head);
        if (hair && hair !== '光头' && !(headItem && headItem.helmet === true)) {
            fields[FIELD_HAIR] = hair;
        }
        var mask = normalizeMask(manifest, appearance.mask);
        if (mask) fields[FIELD_MASK] = mask;
        var keyMap = {};
        if (appearance.keyMap && typeof appearance.keyMap === 'object') {
            Object.keys(appearance.keyMap).forEach(function(field) {
                var value = appearance.keyMap[field];
                if (value !== undefined && value !== null && String(value) !== '') {
                    keyMap[field] = String(value);
                }
            });
        }
        return {
            gender: gender,
            fields: fields,
            equipment: equipment,
            keyMap: keyMap,
            normalizedAppearance: {
                gender: gender,
                face: fields[FIELD_FACE] || '',
                hair: fields[FIELD_HAIR] || '',
                mask: fields[FIELD_MASK] || '',
                head: equipment.head || '',
                body: equipment.body || '',
                leg: equipment.leg || '',
                hand: equipment.hand || '',
                foot: equipment.foot || '',
                neck: equipment.neck || ''
            }
        };
    }

    function normalizeExpression(options) {
        var value = options && options.expression;
        if (value === undefined || value === null) return '';
        return String(value);
    }

    function normalizeSize(options) {
        options = options || {};
        var size = Number(options.size);
        var width = Number(options.width);
        var height = Number(options.height);
        if (!(size > 0)) size = DEFAULT_SIZE;
        if (!(width > 0)) width = size;
        if (!(height > 0)) height = size;
        return { size: size, width: Math.round(width), height: Math.round(height) };
    }

    function normalizeRig(options) {
        var rig = options && options.rig;
        return rig ? String(rig) : 'dialogue';
    }

    /**
     * manifest 资产版本指纹：C# 侧用 assetmanifestSHA 作 cache 成分；
     * Web 侧缺省取 schema@generatedAt，显式 options.assetVersion 优先。
     */
    function assetVersionOf(manifest, options) {
        var explicit = options && options.assetVersion;
        if (explicit !== undefined && explicit !== null && String(explicit) !== '') {
            return String(explicit);
        }
        manifest = manifest || {};
        return String(manifest.schema || '') + '@' + String(manifest.generatedAt || '');
    }

    function buildState(manifest, appearance, options) {
        options = options || {};
        if (typeof DressupDollRenderer === 'undefined' || !DressupDollRenderer) return null;
        var normalized = normalizeAppearance(manifest, appearance);
        var state = DressupDollRenderer.buildStateFromEquipment(manifest, {
            gender: normalized.gender,
            equipment: normalized.equipment,
            appearance: normalized.fields,
            keyMap: normalized.keyMap,
            fitFields: options.fitFields || BUST_FIT_FIELDS,
            drawFields: options.drawFields === undefined ? null : options.drawFields,
            rig: normalizeRig(options),
            stateLabel: options.stateLabel,
            zoom: options.zoom == null ? 1 : options.zoom,
            margin: options.margin == null ? 8 : options.margin,
            expression: normalizeExpression(options),
            fieldExpressions: options.fieldExpressions,
            strictFields: options.strictFields === true
        });
        state.vAlign = options.vAlign || 'top';
        var fitEnvelope = options.fitEnvelope;
        if (fitEnvelope && typeof fitEnvelope === 'object') state.fitEnvelope = fitEnvelope;
        return state;
    }

    /**
     * 稳定 cache identity：appearance 归一化键值（键序固定）+ expression +
     * rig + 尺寸档 + assetVersion。与 C# 的 appearance+expression+rig+size+
     * assetmanifestSHA 键同成分；不含渲染调参（zoom/margin 等），那些由
     * 内部 LRU 另加 profile 成分隔离。
     */
    function identity(manifest, appearance, options) {
        var normalized = normalizeAppearance(manifest, appearance);
        var size = normalizeSize(options);
        var keyMap = normalized.keyMap || {};
        var extra = {};
        Object.keys(keyMap).sort().forEach(function(field) {
            extra[field] = keyMap[field];
        });
        return 'live-portrait:' + JSON.stringify({
            v: 1,
            appearance: normalized.normalizedAppearance,
            keyMap: extra,
            expression: normalizeExpression(options),
            rig: normalizeRig(options),
            size: size.width + 'x' + size.height,
            assetVersion: assetVersionOf(manifest, options)
        });
    }

    function resolve(appearance, options) {
        options = options || {};
        var manifest = manifestOf(options);
        var ready = manifest ? Promise.resolve(manifest) : loadManifest();
        return ready.then(function(loaded) {
            var state = buildState(loaded, appearance, options);
            if (!state) throw new Error('live portrait state build failed');
            return {
                manifest: loaded,
                appearance: normalizeAppearance(loaded, appearance),
                state: state,
                identity: identity(loaded, appearance, options)
            };
        });
    }

    function createCanvas(options) {
        var size = normalizeSize(options);
        var canvas = options && typeof options.createCanvas === 'function'
            ? options.createCanvas(size)
            : (browserDocument && browserDocument.createElement
                ? browserDocument.createElement('canvas')
                : null);
        if (!canvas) throw new Error('canvas is not available');
        if (!(canvas.width > 0)) canvas.width = size.width;
        if (!(canvas.height > 0)) canvas.height = size.height;
        if (typeof canvas.getBoundingClientRect !== 'function') {
            canvas.getBoundingClientRect = function() {
                return { left: 0, top: 0, right: canvas.width, bottom: canvas.height,
                    width: canvas.width, height: canvas.height };
            };
        }
        return canvas;
    }

    function alphaPixels(canvas) {
        if (!canvas || !canvas.width || !canvas.height) return 0;
        var data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        var count = 0;
        for (var i = 3; i < data.length; i += 4) if (data[i] > 8) count++;
        return count;
    }

    /**
     * 有界静态渲染：图片 onload 回调 + setTimeout 轮询驱动（隐藏 WebView2
     * 没有持续 rAF），超时显式 reject，绝不把空白/半加载当成功。
     */
    function snapshotDataUrl(manifest, state, options, control) {
        return new Promise(function(resolvePromise, rejectPromise) {
            var size = normalizeSize(options);
            var timeoutMs = Number(options.timeoutMs);
            if (!(timeoutMs > 0)) timeoutMs = DEFAULT_TIMEOUT_MS;
            var pollMs = Number(options.pollMs);
            if (!(pollMs > 0)) pollMs = DEFAULT_POLL_MS;
            var minAlpha = Number(options.minAlphaPixels);
            if (!(minAlpha >= 0)) minAlpha = DEFAULT_MIN_ALPHA_PIXELS;
            var canvas = null;
            var renderer = null;
            var timer = null;
            var settled = false;
            var lastMeta = null;
            var deadline = Date.now() + timeoutMs;

            function cleanup() {
                if (timer !== null) {
                    clearTimeout(timer);
                    timer = null;
                }
                if (renderer) {
                    try { renderer.destroy(); } catch (ignore) {}
                    renderer = null;
                }
            }

            function settle(url, error) {
                if (settled) return;
                settled = true;
                cleanup();
                if (error) rejectPromise(error);
                else resolvePromise(url);
            }
            control.cancel = function() {
                settle('', new Error('live portrait disposed'));
            };

            function tick() {
                if (settled) return;
                try {
                    lastMeta = renderer.render(state) || lastMeta;
                    var ready = !!(lastMeta && lastMeta.pendingImages === 0
                        && lastMeta.failedImages === 0 && lastMeta.drawnImages > 0);
                    if (ready && alphaPixels(canvas) > minAlpha) {
                        settle(canvas.toDataURL('image/png'));
                        return;
                    }
                    if (Date.now() >= deadline) {
                        var reason = !lastMeta ? 'no render result'
                            : lastMeta.pendingImages > 0 ? 'pendingImages=' + lastMeta.pendingImages
                            : lastMeta.failedImages > 0 ? 'failedImages=' + lastMeta.failedImages
                            : !(lastMeta.drawnImages > 0) ? 'drawnImages=0'
                            : 'transparent pixels';
                        settle('', new Error('live portrait render timeout: ' + reason));
                        return;
                    }
                    timer = setTimeout(tick, pollMs);
                } catch (error) {
                    settle('', error);
                }
            }

            try {
                canvas = createCanvas(options);
                renderer = DressupDollRenderer.create(canvas, {
                    manifest: manifest,
                    width: size.width,
                    height: size.height,
                    // 物理 PNG 尺寸契约：pixelRatio 固定 1，宿主 WebView DPI 不得放大 backing。
                    pixelRatio: 1,
                    animate: false,
                    fps: 24
                });
                tick();
            } catch (error) {
                settle('', error);
            }
        });
    }

    function cacheKeyFor(identityString, options) {
        // 内部 LRU 在契约身份之外叠加渲染调参，避免不同 profile 共享像素。
        var profile = {
            zoom: options.zoom == null ? 1 : options.zoom,
            margin: options.margin == null ? 8 : options.margin,
            vAlign: options.vAlign || 'top',
            fitFields: options.fitFields || BUST_FIT_FIELDS,
            fitEnvelope: options.fitEnvelope || null,
            drawFields: options.drawFields === undefined ? null : options.drawFields
        };
        return identityString + '|profile:' + JSON.stringify(profile);
    }

    function cacheGet(key) {
        return _dataUrlCache[key] || '';
    }

    function cacheSet(key, url) {
        if (!key || !url) return;
        if (!_dataUrlCache[key]) _dataUrlCacheOrder.push(key);
        _dataUrlCache[key] = url;
        while (_dataUrlCacheOrder.length > _maxCacheEntries) {
            var oldest = _dataUrlCacheOrder.shift();
            delete _dataUrlCache[oldest];
        }
    }

    function clearCache() {
        _dataUrlCache = {};
        _dataUrlCacheOrder = [];
    }

    /**
     * 离屏 768 档 PNG：Promise<data:image/png;base64,...>。
     * 返回值附带 dispose()，可中止在途渲染（reject 'live portrait disposed'）。
     */
    function renderDataUrl(appearance, options) {
        options = options || {};
        var control = { cancel: null, disposed: false };
        var identityString = null;
        var promise = resolve(appearance, options).then(function(resolved) {
            identityString = resolved.identity;
            if (control.disposed) throw new Error('live portrait disposed');
            var cached = cacheGet(cacheKeyFor(identityString, options));
            if (cached) return cached;
            return snapshotDataUrl(resolved.manifest, resolved.state, options, control);
        }).then(function(dataUrl) {
            if (typeof dataUrl !== 'string' || dataUrl.indexOf(DATA_URL_PREFIX) !== 0
                    || dataUrl.length <= DATA_URL_PREFIX.length) {
                throw new Error('empty live portrait render');
            }
            if (identityString) cacheSet(cacheKeyFor(identityString, options), dataUrl);
            return dataUrl;
        });
        promise.dispose = function() {
            control.disposed = true;
            if (control.cancel) control.cancel();
        };
        return promise;
    }

    /**
     * 挂载渲染：container 由调用方持有。返回 thenable handle：
     *   { ready, state, identity, canvas, renderer, dispose() }
     * ready 在首帧完整渲染（pending/failed 均为 0）或 timeoutMs 用尽时 resolve
     * 最近一次 renderResult；dispose 幂等并截断迟到回调。
     */
    function render(container, appearance, options) {
        options = options || {};
        var handle = {
            ready: null,
            state: null,
            identity: null,
            canvas: null,
            renderer: null,
            disposed: false
        };
        var timer = null;
        handle.ready = resolve(appearance, options).then(function(resolved) {
            if (handle.disposed) throw new Error('live portrait disposed');
            handle.state = resolved.state;
            handle.identity = resolved.identity;
            var size = normalizeSize(options);
            var canvas = createCanvas(options);
            handle.canvas = canvas;
            var appended = false;
            if (container && typeof container.appendChild === 'function'
                    && canvas.parentNode !== container) {
                container.appendChild(canvas);
                appended = true;
            }
            var renderer = DressupDollRenderer.create(canvas, {
                manifest: resolved.manifest,
                width: size.width,
                height: size.height,
                pixelRatio: Number(options.pixelRatio) > 0 ? Number(options.pixelRatio) : 1,
                animate: options.animate === true,
                fps: Number(options.fps) > 0 ? Number(options.fps) : 24,
                vAlign: options.vAlign || 'top'
            });
            handle.renderer = renderer;
            var timeoutMs = Number(options.timeoutMs);
            if (!(timeoutMs > 0)) timeoutMs = DEFAULT_TIMEOUT_MS;
            var pollMs = Number(options.pollMs);
            if (!(pollMs > 0)) pollMs = DEFAULT_POLL_MS;
            var deadline = Date.now() + timeoutMs;
            var lastMeta = null;
            return new Promise(function(resolveReady, rejectReady) {
                function tick() {
                    if (handle.disposed) {
                        rejectReady(new Error('live portrait disposed'));
                        return;
                    }
                    try {
                        lastMeta = renderer.render(resolved.state) || lastMeta;
                        var ready = !!(lastMeta && lastMeta.pendingImages === 0
                            && lastMeta.failedImages === 0 && lastMeta.drawnImages > 0);
                        if (ready || Date.now() >= deadline) {
                            resolveReady(lastMeta);
                            return;
                        }
                        timer = setTimeout(tick, pollMs);
                    } catch (error) {
                        resolveReady(lastMeta || { error: String(error && error.message || error) });
                    }
                }
                tick();
            });
        });
        handle.dispose = function() {
            if (handle.disposed) return;
            handle.disposed = true;
            if (timer !== null) {
                clearTimeout(timer);
                timer = null;
            }
            if (handle.renderer) {
                try { handle.renderer.destroy(); } catch (ignore) {}
            }
            if (handle.canvas && handle.canvas.parentNode) {
                try { handle.canvas.parentNode.removeChild(handle.canvas); } catch (ignore) {}
            }
        };
        handle.then = function(onOk, onErr) { return handle.ready.then(onOk, onErr); };
        handle.catch = function(onErr) { return handle.ready.catch(onErr); };
        handle.finally = function(fn) { return handle.ready.finally(fn); };
        return handle;
    }

    return {
        DEFAULT_EXPRESSION: DEFAULT_EXPRESSION,
        APPEARANCE_FIELDS: APPEARANCE_FIELDS.slice(),
        BUST_FIT_FIELDS: BUST_FIT_FIELDS.slice(),
        normalizeAppearance: normalizeAppearance,
        buildState: buildState,
        identity: identity,
        resolve: resolve,
        render: render,
        renderDataUrl: renderDataUrl,
        loadManifest: loadManifest,
        clearCache: clearCache
    };
})();

if (typeof window !== 'undefined') window.LiveDialoguePortraits = LiveDialoguePortraits;
