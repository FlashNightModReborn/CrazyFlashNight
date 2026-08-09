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
    var HAIR_COMPAT_ALIASES = {
        '发型-女式-红马尾': '发型-女式-玫红色马尾',
        '发型-女式-白长发': '发型-女式-银色清爽直发',
        '发型-男式-黑尖长发': '发型-男式-黑长发',
        '发型-男式-黑短发': '发型-男式-精武短发'
    };

    var _manifest = null;
    var _manifestPromise = null;
    var _thumbCache = {};
    var _thumbPending = {};
    var _mountSeq = 0;
    var _renderQueue = [];
    var _activeRenderCount = 0;
    var _peakActiveRenderCount = 0;
    var _maxConcurrentRenders = Math.max(1, Math.min(8,
        Number(browserWindow.CF7_MERC_PORTRAIT_MAX_CONCURRENCY) || 4));

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
            ? String(merc.gender) : '男';
        return (value === '女' || value === '主角-女' || value === '0') ? '女' : '男';
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

    function cacheKey(merc, variant, size) {
        var parts = [variant, size, normalizeGender(merc), merc && merc.face || '', merc && merc.hair || ''];
        var equipment = equipmentFromMerc(merc);
        Object.keys(equipment).sort().forEach(function(slot) {
            parts.push(slot + ':' + equipment[slot]);
        });
        return parts.join('|');
    }

    function alphaPixels(canvas) {
        if (!canvas || !canvas.width || !canvas.height) return 0;
        var data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        var count = 0;
        for (var i = 3; i < data.length; i += 4) if (data[i] > 8) count++;
        return count;
    }

    function renderSnapshot(manifest, state, size, isAlive) {
        return new Promise(function(resolve) {
            var canvas = document.createElement('canvas');
            var renderer = DressupDollRenderer.create(canvas, {
                manifest: manifest,
                width: size,
                height: size,
                fps: 24
            });
            var attempts = 0;
            function tick() {
                if (!isAlive()) {
                    renderer.destroy();
                    resolve('');
                    return;
                }
                var meta = renderer.render(state);
                var ready = !!(meta && meta.pendingImages === 0 && meta.failedImages === 0);
                if (ready && alphaPixels(canvas) > 120) {
                    var url = '';
                    try { url = canvas.toDataURL('image/png'); } catch (ignore) {}
                    renderer.destroy();
                    resolve(url);
                    return;
                }
                if (attempts >= 50) {
                    renderer.destroy();
                    resolve('');
                    return;
                }
                attempts++;
                setTimeout(tick, 80);
            }
            tick();
        });
    }

    function pumpRenderQueue() {
        while (_activeRenderCount < _maxConcurrentRenders && _renderQueue.length) {
            var job = _renderQueue.shift();
            _activeRenderCount++;
            _peakActiveRenderCount = Math.max(_peakActiveRenderCount, _activeRenderCount);
            renderSnapshot(job.manifest, job.state, job.size, job.isAlive).then(
                job.resolve,
                job.reject
            ).then(function() {
                _activeRenderCount--;
                pumpRenderQueue();
            }, function() {
                _activeRenderCount--;
                pumpRenderQueue();
            });
        }
    }

    function scheduleSnapshot(manifest, state, size, isAlive) {
        return new Promise(function(resolve, reject) {
            _renderQueue.push({
                manifest: manifest,
                state: state,
                size: size,
                isAlive: isAlive,
                resolve: resolve,
                reject: reject
            });
            pumpRenderQueue();
        });
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

    function mount(container, img, merc, options) {
        options = options || {};
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
            var key = cacheKey(merc, variant, size);
            if (_thumbCache[key]) {
                markReady(container, img, _thumbCache[key]);
                return { source: 'cache', key: key };
            }
            if (_thumbPending[key]) {
                return _thumbPending[key].then(function(pendingUrl) {
                    if (!pendingUrl || !isAlive()) {
                        if (isAlive()) markFallback(container, img);
                        return null;
                    }
                    markReady(container, img, pendingUrl);
                    return { source: 'shared-pending', key: key };
                });
            }
            var state = buildState(merc, {
                manifest: manifest,
                fitFields: BUST_FIT_FIELDS,
                zoom: options.zoom == null ? (variant === 'decision' ? 1.04 : 1) : options.zoom,
                margin: options.margin == null ? 6 : options.margin,
                drawFields: null,
                rig: 'battle',
                stateLabel: BATTLE_STATE,
                vAlign: options.vAlign || 'top'
            });
            if (!state) {
                markFallback(container, img);
                return null;
            }
            // 同一批十余张卡常共享装备/外观。按 cacheKey 合并飞行中的快照，避免重复建
            // renderer 和重复解码图层；每个消费者仍用自己的 token 判断是否可以落 DOM。
            _thumbPending[key] = scheduleSnapshot(manifest, state, size, function() { return true; });
            return _thumbPending[key].then(function(url) {
                delete _thumbPending[key];
                if (url) _thumbCache[key] = url;
                if (!url || !isAlive()) {
                    if (isAlive()) markFallback(container, img);
                    return null;
                }
                markReady(container, img, url);
                return { source: 'dressup', key: key };
            }).catch(function(error) {
                delete _thumbPending[key];
                throw error;
            });
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
        return {
            maxConcurrentRenders: _maxConcurrentRenders,
            activeRenderCount: _activeRenderCount,
            queuedRenderCount: _renderQueue.length,
            peakActiveRenderCount: _peakActiveRenderCount,
            cachedSnapshotCount: Object.keys(_thumbCache).length,
            pendingSnapshotCount: Object.keys(_thumbPending).length
        };
    }

    browserWindow.MercPortraits = {
        loadManifest: loadManifest,
        buildState: buildState,
        mount: mount,
        create: create,
        updateHost: updateHost,
        debugState: debugState,
        clear: markFallback,
        BODY_FIT_FIELDS: BODY_FIT_FIELDS.slice(),
        BUST_FIT_FIELDS: BUST_FIT_FIELDS.slice(),
        BATTLE_STATE: BATTLE_STATE
    };
})();
