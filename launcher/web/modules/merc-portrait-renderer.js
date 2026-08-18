/**
 * MercPortraits — shared, consumer-neutral mercenary portrait renderer.
 *
 * The authoritative merc tuple remains in AS2.  Web consumers project only the
 * appearance/equipment fields needed to build a cached battle-rig bust.  Team
 * and Arena use the same normalization, crop and lifecycle fence so a portrait
 * cannot drift between panels or keep rendering after its card is replaced.
 */
(function() {
    'use strict';

    var browserWindow = typeof window !== 'undefined' ? window : {};
    var MANIFEST_URL = browserWindow.CF7_DRESSUP_MANIFEST_URL || 'assets/dressup/manifest.json';
    var BODY_FIT_FIELDS = [
        '身体', '上臂', '左下臂', '右下臂', '左手', '右手',
        '屁股', '左大腿', '右大腿', '小腿', '脚',
        '脸型', '发型', '面具'
    ];
    var BUST_FIT_FIELDS = ['脸型', '发型', '面具', '身体', '上臂'];
    var BATTLE_STATE = '空手站立';
    var FACE_BY_ID_FALLBACK = {
        '0': '女变装-基本脸型',
        '1': '男变装-基本脸型'
    };
    // Mirror of HAIR_COMPAT_ALIASES in tools/lib/arena-portrait-routing.js
    // (Node build-time copy). Both copies must stay byte-equal; pinned by
    // tools/test-merc-portrait-renderer-runtime.js.
    var HAIR_COMPAT_ALIASES = {
        '发型-女式-红马尾': '发型-女式-玫红色马尾',
        '发型-女式-白长发': '发型-女式-银色清爽直发',
        '发型-男式-黑尖长发': '发型-男式-黑长发',
        '发型-男式-黑短发': '发型-男式-精武短发'
    };

    var _manifest = null;
    var _manifestPromise = null;
    var _thumbCache = {};
    var _thumbCacheBytes = 0;
    var _cacheAccessSeq = 0;
    var _thumbPending = {};
    var _mountSeq = 0;
    var _pendingSubscriberSeq = 0;
    var _renderQueue = [];
    var _activeRenderCount = 0;
    var _peakActiveRenderCount = 0;
    var _pumpingRenderQueue = false;
    var _maxConcurrentRenders = Math.max(1, Math.min(8,
        Number(browserWindow.CF7_MERC_PORTRAIT_MAX_CONCURRENCY) || 4));
    var _maxCacheEntries = boundedPositiveInteger(
        browserWindow.CF7_MERC_PORTRAIT_CACHE_MAX_ENTRIES, 96, 1024);
    var _maxCacheBytes = boundedPositiveInteger(
        browserWindow.CF7_MERC_PORTRAIT_CACHE_MAX_BYTES, 12 * 1024 * 1024, 256 * 1024 * 1024);

    function boundedPositiveInteger(value, fallback, maximum) {
        value = Number(value);
        if (!isFinite(value) || value <= 0) value = fallback;
        return Math.max(1, Math.min(maximum, Math.floor(value)));
    }

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

    function normalizeGender(merc) {
        var value = merc && merc.gender !== undefined && merc.gender !== null
            ? String(merc.gender) : '';
        // Match ArenaPanelService.as: explicit male encodings are male;
        // missing/unknown legacy Host values fail soft to female.
        return (value === '男' || value === '主角-男' || value === '1') ? '男' : '女';
    }

    function stripEquipName(value) {
        if (value === undefined || value === null) return '';
        return String(value).split('#', 1)[0];
    }

    function dressupSlotName(slot) {
        var map = typeof MercData !== 'undefined' && MercData.DRESSUP_SLOT_BY_INDEX
            ? MercData.DRESSUP_SLOT_BY_INDEX : {};
        return map[Number(slot)] || slot;
    }

    function setEquipmentSlot(equipment, slot, value) {
        var slotName = dressupSlotName(slot);
        var name = stripEquipName(value);
        if (slotName && name) equipment[slotName] = name;
    }

    function equipmentFromMerc(merc) {
        var equipment = {};
        var equips = merc && merc.equips ? merc.equips : [];
        for (var i = 0; i < equips.length; i++) {
            var eq = equips[i] || {};
            setEquipmentSlot(equipment, eq.slot, eq.name || eq.raw || eq.displayname);
        }
        var direct = merc && merc.equipment ? merc.equipment : null;
        if (direct) {
            Object.keys(direct).forEach(function(slot) {
                if (!equipment[dressupSlotName(slot)]) setEquipmentSlot(equipment, slot, direct[slot]);
            });
        }
        return equipment;
    }

    function skinCovered(manifest, key) {
        return !!(key && manifest && manifest.skinKeys && manifest.skinKeys[key]
            && manifest.skinKeys[key].covered);
    }

    function normalizeAppearanceKey(manifest, value, type, gender) {
        var raw = value === undefined || value === null ? '' : String(value).trim();
        var appearance = manifest && manifest.appearance ? manifest.appearance : {};
        if (type === 'face') {
            if (/^\d+$/.test(raw)) {
                return (appearance.faceById && appearance.faceById[raw])
                    || FACE_BY_ID_FALLBACK[raw]
                    || (gender === '女' ? '女变装-基本脸型' : '男变装-基本脸型');
            }
            if (skinCovered(manifest, raw)) return raw;
            return gender === '女' ? '女变装-基本脸型' : '男变装-基本脸型';
        }
        if (!raw || raw === '光头') return '';
        if (/^\d+$/.test(raw)) {
            raw = appearance.hairById && appearance.hairById[raw] ? appearance.hairById[raw] : raw;
        }
        if (skinCovered(manifest, raw)) return raw;
        var alias = HAIR_COMPAT_ALIASES[raw];
        return alias && skinCovered(manifest, alias) ? alias : '';
    }

    function appearanceFromMerc(manifest, merc, equipment) {
        var gender = normalizeGender(merc);
        var appearance = {};
        var face = normalizeAppearanceKey(manifest, merc && merc.face, 'face', gender);
        var hair = normalizeAppearanceKey(manifest, merc && merc.hair, 'hair', gender);
        var headItem = equipment && equipment.head ? equipment.head : '';
        var item = headItem && manifest && manifest.items ? manifest.items[headItem] : null;
        appearance['脸型'] = face;
        if (hair && hair !== '光头' && !(item && item.helmet === true)) appearance['发型'] = hair;
        return appearance;
    }

    function buildState(merc, options) {
        options = options || {};
        var manifest = options.manifest || _manifest;
        if (!manifest || typeof DressupDollRenderer === 'undefined') return null;
        var equipment = equipmentFromMerc(merc);
        var state = DressupDollRenderer.buildStateFromEquipment(manifest, {
            gender: normalizeGender(merc),
            equipment: equipment,
            appearance: appearanceFromMerc(manifest, merc, equipment),
            fitFields: options.fitFields || BUST_FIT_FIELDS,
            drawFields: options.drawFields === undefined ? null : options.drawFields,
            rig: options.rig || 'battle',
            stateLabel: options.stateLabel || BATTLE_STATE,
            zoom: options.zoom == null ? 1 : options.zoom,
            margin: options.margin == null ? 6 : options.margin
        });
        if (state && options.vAlign) state.vAlign = options.vAlign;
        return state;
    }

    function normalizedRenderOptions(variant, options) {
        options = options || {};
        var defaultZoom = variant === 'decision' ? 1.04 : 1;
        var zoom = options.zoom == null ? defaultZoom : Number(options.zoom);
        var margin = options.margin == null ? 6 : Number(options.margin);
        if (!isFinite(zoom)) zoom = defaultZoom;
        if (!isFinite(margin)) margin = 6;
        return {
            zoom: zoom,
            margin: margin,
            vAlign: options.vAlign || 'top'
        };
    }

    function cacheKey(manifest, merc, variant, size, renderOptions) {
        var equipment = equipmentFromMerc(merc);
        var appearance = appearanceFromMerc(manifest, merc, equipment);
        var parts = [
            variant,
            size,
            normalizeGender(merc),
            appearance['脸型'] || '',
            appearance['发型'] || '',
            renderOptions.zoom,
            renderOptions.margin,
            renderOptions.vAlign
        ];
        Object.keys(equipment).sort().forEach(function(slot) {
            parts.push([slot, equipment[slot]]);
        });
        return JSON.stringify(parts);
    }

    function estimateCacheBytes(url) {
        // Data URLs are retained as JS strings. Two bytes per code unit is a
        // conservative, engine-neutral memory estimate for the cache budget.
        return String(url || '').length * 2;
    }

    function cacheGet(key) {
        var entry = _thumbCache[key];
        if (!entry) return '';
        entry.lastUsed = ++_cacheAccessSeq;
        return entry.url;
    }

    function removeCacheEntry(key) {
        var entry = _thumbCache[key];
        if (!entry) return;
        _thumbCacheBytes = Math.max(0, _thumbCacheBytes - entry.bytes);
        delete _thumbCache[key];
    }

    function evictCacheToLimits() {
        var keys = Object.keys(_thumbCache);
        while (keys.length > _maxCacheEntries || _thumbCacheBytes > _maxCacheBytes) {
            var oldestKey = null;
            var oldestAccess = Infinity;
            for (var i = 0; i < keys.length; i++) {
                var candidate = _thumbCache[keys[i]];
                if (candidate && candidate.lastUsed < oldestAccess) {
                    oldestAccess = candidate.lastUsed;
                    oldestKey = keys[i];
                }
            }
            if (!oldestKey) break;
            removeCacheEntry(oldestKey);
            keys = Object.keys(_thumbCache);
        }
    }

    function cacheSet(key, url) {
        if (!key || !url) return;
        removeCacheEntry(key);
        var bytes = estimateCacheBytes(url);
        _thumbCache[key] = {
            url: url,
            bytes: bytes,
            lastUsed: ++_cacheAccessSeq
        };
        _thumbCacheBytes += bytes;
        evictCacheToLimits();
    }

    function clearCache() {
        _thumbCache = {};
        _thumbCacheBytes = 0;
        _cacheAccessSeq = 0;
    }

    function alphaPixels(canvas) {
        if (!canvas || !canvas.width || !canvas.height) return 0;
        var data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        var count = 0;
        for (var i = 3; i < data.length; i += 4) if (data[i] > 8) count++;
        return count;
    }

    function renderSnapshot(manifest, state, size, isAlive) {
        var control = { promise: null, cancel: function() {} };
        control.promise = new Promise(function(resolve, reject) {
            var canvas = null;
            var renderer = null;
            var timer = null;
            var attempts = 0;
            var settled = false;

            function dispose() {
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
                dispose();
                if (error) reject(error);
                else resolve(url || '');
            }

            control.cancel = function() { settle(''); };

            function tick() {
                if (settled) return;
                try {
                    if (!isAlive()) {
                        settle('');
                        return;
                    }
                    var meta = renderer.render(state);
                    var ready = !!(meta && meta.pendingImages === 0 && meta.failedImages === 0);
                    if (ready && alphaPixels(canvas) > 120) {
                        settle(canvas.toDataURL('image/png'));
                        return;
                    }
                    if (attempts >= 50) {
                        settle('');
                        return;
                    }
                    attempts++;
                    timer = setTimeout(tick, 80);
                } catch (error) {
                    // setTimeout callbacks execute outside the Promise executor;
                    // explicitly reject so the render slot cannot stay occupied.
                    settle('', error);
                }
            }

            try {
                canvas = document.createElement('canvas');
                renderer = DressupDollRenderer.create(canvas, {
                    manifest: manifest,
                    width: size,
                    height: size,
                    // `size` is the transport contract's physical PNG size. Do not let
                    // the host WebView's DPI (for example 150%) silently turn 256 into 384.
                    pixelRatio: 1,
                    animate: false,
                    fps: 24
                });
                tick();
            } catch (error) {
                settle('', error);
            }
        });
        return control;
    }

    function jobIsAlive(job) {
        try { return !job.cancelled && job.isAlive(); }
        catch (ignore) { return false; }
    }

    function settleRenderJob(job, url, error) {
        if (!job || job.finished) return;
        job.finished = true;
        if (job.started) _activeRenderCount = Math.max(0, _activeRenderCount - 1);
        if (error) job.reject(error);
        else job.resolve(url || '');
        if (!_pumpingRenderQueue) pumpRenderQueue();
    }

    function pumpRenderQueue() {
        if (_pumpingRenderQueue) return;
        _pumpingRenderQueue = true;
        try {
            while (_activeRenderCount < _maxConcurrentRenders && _renderQueue.length) {
                var job = _renderQueue.shift();
                if (!job || job.finished) continue;
                if (!jobIsAlive(job)) {
                    settleRenderJob(job, '');
                    continue;
                }
                job.started = true;
                _activeRenderCount++;
                _peakActiveRenderCount = Math.max(_peakActiveRenderCount, _activeRenderCount);
                try {
                    job.control = renderSnapshot(job.manifest, job.state, job.size, job.isAlive);
                    job.control.promise.then(function(completedJob) {
                        return function(url) { settleRenderJob(completedJob, url); };
                    }(job), function(completedJob) {
                        return function(error) { settleRenderJob(completedJob, '', error); };
                    }(job));
                } catch (error) {
                    settleRenderJob(job, '', error);
                }
            }
        } finally {
            _pumpingRenderQueue = false;
        }
    }

    function scheduleSnapshot(manifest, state, size, isAlive) {
        var job = {
            manifest: manifest,
            state: state,
            size: size,
            isAlive: isAlive,
            resolve: null,
            reject: null,
            control: null,
            started: false,
            finished: false,
            cancelled: false,
            promise: null,
            cancel: null
        };
        job.promise = new Promise(function(resolve, reject) {
            job.resolve = resolve;
            job.reject = reject;
        });
        job.cancel = function() {
            if (job.finished) return;
            job.cancelled = true;
            if (job.control) {
                job.control.cancel();
                return;
            }
            var index = _renderQueue.indexOf(job);
            if (index >= 0) _renderQueue.splice(index, 1);
            settleRenderJob(job, '');
        };
        _renderQueue.push(job);
        pumpRenderQueue();
        return job;
    }

    function markFallback(container, img) {
        if (!container) return;
        container.classList.add('merc-portrait-art', 'merc-portrait-fallback', 'merc-card-portrait-fallback');
        container.classList.remove('merc-dressup-ready');
        container.setAttribute('data-merc-portrait-source', 'fallback');
        container.setAttribute('data-merc-portrait-state', 'fallback');
        if (img) {
            img.removeAttribute('src');
            img.hidden = true;
        }
    }

    function markPending(container, img) {
        markFallback(container, img);
        if (container) container.setAttribute('data-merc-portrait-state', 'pending');
    }

    function markReady(container, img, url) {
        if (!container || !img || !url) return;
        img.hidden = false;
        img.src = url;
        container.classList.remove('merc-portrait-fallback', 'merc-card-portrait-fallback');
        container.classList.add('merc-portrait-art', 'merc-dressup-ready');
        container.setAttribute('data-merc-portrait-source', 'dressup');
        container.setAttribute('data-merc-portrait-state', 'ready');
    }

    function detachPendingSubscriber(subscription) {
        if (!subscription || subscription.released) return;
        subscription.released = true;
        delete subscription.entry.subscribers[subscription.id];
        if (subscription.container
                && subscription.container._mercPortraitSubscription === subscription) {
            subscription.container._mercPortraitSubscription = null;
        }
    }

    function pendingHasLiveSubscribers(entry) {
        var keys = Object.keys(entry.subscribers);
        var live = false;
        for (var i = 0; i < keys.length; i++) {
            var subscription = entry.subscribers[keys[i]];
            var alive = false;
            try { alive = !subscription.released && subscription.isAlive(); }
            catch (ignore) { alive = false; }
            if (alive) live = true;
            else detachPendingSubscriber(subscription);
        }
        return live;
    }

    function subscribePending(entry, container, isAlive) {
        var subscription = {
            id: 'merc_sub_' + (++_pendingSubscriberSeq),
            entry: entry,
            container: container,
            isAlive: isAlive,
            released: false,
            cancel: null
        };
        subscription.cancel = function() {
            if (subscription.released) return;
            detachPendingSubscriber(subscription);
            if (entry.job && !pendingHasLiveSubscribers(entry)) {
                // Remove the abandoned key synchronously. A same-turn remount
                // must create a fresh job instead of subscribing to the old
                // control whose cancellation settles on the next microtask.
                cleanupPendingEntry(entry);
                entry.job.cancel();
            }
        };
        entry.subscribers[subscription.id] = subscription;
        container._mercPortraitSubscription = subscription;
        return subscription;
    }

    function cleanupPendingEntry(entry) {
        if (_thumbPending[entry.key] === entry) delete _thumbPending[entry.key];
    }

    function startPendingEntry(entry, manifest, state, size) {
        entry.job = scheduleSnapshot(manifest, state, size, function() {
            return pendingHasLiveSubscribers(entry);
        });
        entry.promise = entry.job.promise.then(function(url) {
            if (url) cacheSet(entry.key, url);
            cleanupPendingEntry(entry);
            return url;
        }, function(error) {
            cleanupPendingEntry(entry);
            throw error;
        });
    }

    function consumePending(entry, subscription, source, container, img, key, isAlive) {
        return entry.promise.then(function(url) {
            subscription.cancel();
            if (!url || !isAlive()) {
                if (isAlive()) markFallback(container, img);
                return null;
            }
            markReady(container, img, url);
            return { source: source, key: key };
        }, function(error) {
            subscription.cancel();
            throw error;
        });
    }

    function invalidateMount(container) {
        if (!container) return;
        var subscription = container._mercPortraitSubscription;
        if (subscription && typeof subscription.cancel === 'function') subscription.cancel();
        container._mercPortraitSubscription = null;
        if (typeof container.removeAttribute === 'function') {
            container.removeAttribute('data-merc-portrait-request');
        } else {
            container.setAttribute('data-merc-portrait-request', '');
        }
    }

    function clearPortrait(container, img) {
        if (!img && container && typeof container.querySelector === 'function') {
            img = container.querySelector('img');
        }
        invalidateMount(container);
        markFallback(container, img);
    }

    function mount(container, img, merc, options) {
        options = options || {};
        invalidateMount(container);
        if (!container || !img || !merc) {
            markFallback(container, img);
            return Promise.resolve(null);
        }
        var variant = options.variant || 'card';
        var size = Number(options.size) || (variant === 'decision' ? 140 : 112);
        var token = 'merc_portrait_' + (++_mountSeq) + '_' + Date.now();
        var wasConnected = false;
        container.setAttribute('data-merc-portrait-request', token);
        img.alt = options.alt || '';
        img.draggable = false;
        img.decoding = 'async';
        markPending(container, img);

        function isAlive() {
            if (container.getAttribute('data-merc-portrait-request') !== token) return false;
            var connected = !!(document.documentElement && document.documentElement.contains(container));
            if (connected) wasConnected = true;
            return !wasConnected || connected;
        }

        return loadManifest().then(function(manifest) {
            if (!isAlive()) return null;
            var renderOptions = normalizedRenderOptions(variant, options);
            var key = cacheKey(manifest, merc, variant, size, renderOptions);
            var cached = cacheGet(key);
            if (cached) {
                markReady(container, img, cached);
                return { source: 'cache', key: key };
            }
            var entry = _thumbPending[key];
            var source = entry ? 'shared-pending' : 'dressup';
            if (!entry) {
                var state = buildState(merc, {
                    manifest: manifest,
                    fitFields: BUST_FIT_FIELDS,
                    zoom: renderOptions.zoom,
                    margin: renderOptions.margin,
                    drawFields: null,
                    rig: 'battle',
                    stateLabel: BATTLE_STATE,
                    vAlign: renderOptions.vAlign
                });
                if (!state) {
                    markFallback(container, img);
                    return null;
                }
                entry = {
                    key: key,
                    subscribers: {},
                    job: null,
                    promise: null
                };
                _thumbPending[key] = entry;
            }
            // Register the consumer before a new job is pumped: a synchronous
            // first tick must already see at least one live subscriber.
            var subscription = subscribePending(entry, container, isAlive);
            if (!entry.promise) startPendingEntry(entry, manifest, state, size);
            return consumePending(entry, subscription, source, container, img, key, isAlive);
        }).catch(function() {
            if (container.getAttribute('data-merc-portrait-request') === token) markFallback(container, img);
            return null;
        });
    }

    function create(merc, options) {
        options = options || {};
        var portrait = document.createElement(options.tagName || 'div');
        portrait.className = options.className || 'merc-card-portrait merc-dressup-portrait';
        var img = document.createElement('img');
        portrait.appendChild(img);
        mount(portrait, img, merc, options);
        return portrait;
    }

    /**
     * 无 DOM 挂载的胸像快照：归一化 merc → buildState → 离屏 canvas → PNG dataURL。
     * 供 doll-bake 等后台烘焙消费者使用（复用同一归一化/裁剪/渲染队列，
     * 不进卡片挂载与 _thumbCache 语义）。空渲染/失败 resolve ''，不 reject，
     * 调用方按静默降级处理。
     */
    function renderDataUrl(merc, options) {
        options = options || {};
        var size = Number(options.size) || 256;
        return loadManifest().then(function(manifest) {
            var state = buildState(merc, {
                manifest: manifest,
                fitFields: options.fitFields || BUST_FIT_FIELDS,
                zoom: options.zoom == null ? 1 : options.zoom,
                margin: options.margin == null ? 6 : options.margin,
                vAlign: options.vAlign || 'top'
            });
            if (!state) return '';
            var job = scheduleSnapshot(manifest, state, size, function() { return true; });
            return job.promise;
        }).catch(function() { return ''; });
    }

    function updateHost(host, merc, options) {
        options = options || {};
        if (!host) return Promise.resolve(null);
        var selector = options.selector || '.merc-card-portrait';
        var portrait = host.querySelector(selector);
        if (!portrait) {
            portrait = create(null, options);
            host.appendChild(portrait);
        }
        var img = portrait.querySelector('img');
        if (!img) {
            img = document.createElement('img');
            portrait.appendChild(img);
        }
        return mount(portrait, img, merc, options);
    }

    function debugState() {
        var pendingSubscriberCount = 0;
        Object.keys(_thumbPending).forEach(function(key) {
            pendingSubscriberCount += Object.keys(_thumbPending[key].subscribers).length;
        });
        return {
            maxConcurrentRenders: _maxConcurrentRenders,
            activeRenderCount: _activeRenderCount,
            queuedRenderCount: _renderQueue.length,
            peakActiveRenderCount: _peakActiveRenderCount,
            cachedSnapshotCount: Object.keys(_thumbCache).length,
            cachedSnapshotBytes: _thumbCacheBytes,
            maxCachedSnapshotCount: _maxCacheEntries,
            maxCachedSnapshotBytes: _maxCacheBytes,
            pendingSnapshotCount: Object.keys(_thumbPending).length,
            pendingSubscriberCount: pendingSubscriberCount
        };
    }

    browserWindow.MercPortraits = {
        loadManifest: loadManifest,
        buildState: buildState,
        mount: mount,
        create: create,
        renderDataUrl: renderDataUrl,
        updateHost: updateHost,
        debugState: debugState,
        clear: clearPortrait,
        clearCache: clearCache,
        BODY_FIT_FIELDS: BODY_FIT_FIELDS.slice(),
        BUST_FIT_FIELDS: BUST_FIT_FIELDS.slice(),
        BATTLE_STATE: BATTLE_STATE,
        // Test seam: keeps the browser copy pinned equal to the Node copy in
        // tools/lib/arena-portrait-routing.js (asserted by
        // tools/test-merc-portrait-renderer-runtime.js).
        HAIR_COMPAT_ALIASES: Object.assign({}, HAIR_COMPAT_ALIASES)
    };
})();
