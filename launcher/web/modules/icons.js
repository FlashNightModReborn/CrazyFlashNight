/**
 * Icons — 物品图标 manifest 加载与 URL 解析
 *
 * manifest.json 兼容结构:
 *   {"物品名": {"f1": "hash_1.png", "f2": "hash_2.png"}}
 *   {"物品名": {"frames": [{"frame": 1, "uri": "hash_1.png"}], "playback": "static"}}
 * resolve() 默认仍返回第一帧，避免旧面板被动播放动图。
 */
var Icons = (function() {
    'use strict';

    var _map = null, _loading = false, _queue = [];
    var ICON_ROOT = 'icons/';
    var DEFAULT_FPS = 24;
    var LAYER_FRAME_IDENTITY_KEYS = [
        'uri',
        'cropX',
        'cropY',
        'cropWidth',
        'cropHeight',
        'canvasWidth',
        'canvasHeight'
    ];
    if (typeof AssetTimeline === 'undefined' || !AssetTimeline) {
        throw new Error('AssetTimeline must be loaded before icons.js');
    }
    var Timeline = AssetTimeline;
    var _observer = null;
    var _animationFrame = 0;
    var _preloaded = {};

    function flushQueue() {
        for (var i = 0; i < _queue.length; i++) {
            if (typeof _queue[i] === 'function') _queue[i]();
        }
        _queue = [];
    }

    function entry(name) {
        if (!_map || !name) return null;
        return _map[name] || null;
    }

    function iconUrl(uri) {
        if (!uri) return null;
        if (/^(?:https?:|data:|\/)/.test(uri)) return uri;
        return ICON_ROOT + uri;
    }

    // webp-animated: 单张动图 .webp，由浏览器/Chromium 原生播放，
    // 不进入 tickAnimatedIcons 的 RAF 逐帧换 src 循环。
    function isWebpAnimated(iconEntry) {
        return !!(iconEntry && iconEntry.format === 'webp-animated');
    }

    function webpAnimatedUri(iconEntry) {
        if (!iconEntry) return null;
        if (typeof iconEntry.uri === 'string' && iconEntry.uri) return iconEntry.uri;
        var frames = iconEntry.frames;
        if (frames && frames.length) {
            var first = frames[0] || {};
            var uri = first.uri || first.file || first.filename;
            if (uri) return uri;
        }
        if (typeof iconEntry.f1 === 'string' && iconEntry.f1) return iconEntry.f1;
        return null;
    }

    function webpAnimatedUrl(iconEntry) {
        return iconUrl(webpAnimatedUri(iconEntry));
    }

    function escapeAttr(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/"/g, '&quot;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    function normalizeFrames(iconEntry) {
        if (!iconEntry) return [];
        if (iconEntry._normFrames) return iconEntry._normFrames;
        if (isWebpAnimated(iconEntry)) {
            // 单张动图：归一化为一帧，旧入口(frames/resolve/html)直接拿到 .webp，
            // 浏览器自播；不参与 RAF 换帧。
            var webpUrl = webpAnimatedUrl(iconEntry);
            var webpOut = webpUrl
                ? [{
                    frame: 1,
                    uri: webpAnimatedUri(iconEntry),
                    url: webpUrl,
                    durationMs: null,
                    durationFrames: null,
                    duplicateOfFrame: null,
                    playback: iconEntry.playback || null
                }]
                : [];
            iconEntry._normFrames = webpOut;
            return webpOut;
        }
        var out = [];
        var seen = {};
        var rawFrames = iconEntry && iconEntry.timelineFrames && iconEntry.timelineFrames.length
            ? iconEntry.timelineFrames
            : iconEntry && iconEntry.frames;

        if (rawFrames && rawFrames.length) {
            for (var i = 0; i < rawFrames.length; i++) {
                var raw = rawFrames[i] || {};
                var uri = raw.uri || raw.file || raw.filename;
                if (!uri) continue;
                var frame = raw.frame || raw.index || (i + 1);
                out.push({
                    frame: frame,
                    uri: uri,
                    url: iconUrl(uri),
                    durationMs: raw.durationMs || raw.duration || null,
                    durationFrames: raw.durationFrames || raw.holdFrames || null,
                    duplicateOfFrame: raw.duplicateOfFrame || null,
                    playback: raw.playback || iconEntry.playback || null,
                    sourceFrame: raw.sourceFrame || null,
                    frameEnd: raw.frameEnd || null,
                    sourceFrameEnd: raw.sourceFrameEnd || null
                });
                seen[String(frame)] = true;
            }
        }

        if (iconEntry && iconEntry.f1 && !seen['1']) {
            out.unshift({
                frame: 1,
                uri: iconEntry.f1,
                url: iconUrl(iconEntry.f1),
                durationMs: null,
                durationFrames: null,
                duplicateOfFrame: null,
                playback: iconEntry.playback || null
            });
            seen['1'] = true;
        }
        if (iconEntry && iconEntry.f2 && !seen['2']) {
            out.push({
                frame: 2,
                uri: iconEntry.f2,
                url: iconUrl(iconEntry.f2),
                durationMs: null,
                durationFrames: null,
                duplicateOfFrame: null,
                playback: iconEntry.playback || null
            });
        }

        out.sort(function(a, b) {
            return Number(a.frame || 0) - Number(b.frame || 0);
        });
        iconEntry._normFrames = out;
        return out;
    }

    function normalizeLayerFrames(layer) {
        if (!layer) return [];
        if (layer._normFrames) return layer._normFrames;
        var out = [];
        var rawFrames = layer && layer.timelineFrames && layer.timelineFrames.length
            ? layer.timelineFrames
            : layer && layer.frames;
        if ((!rawFrames || !rawFrames.length) && layer && layer.export) {
            rawFrames = layer.export.timelineFrames && layer.export.timelineFrames.length
                ? layer.export.timelineFrames
                : layer.export.frames;
        }
        if (!rawFrames || !rawFrames.length) {
            layer._normFrames = out;
            return out;
        }
        for (var i = 0; i < rawFrames.length; i++) {
            var raw = rawFrames[i] || {};
            var uri = raw.uri || raw.file || raw.filename;
            if (!uri) continue;
            out.push({
                frame: raw.frame || raw.index || (i + 1),
                uri: uri,
                url: iconUrl(uri),
                durationMs: raw.durationMs || raw.duration || null,
                durationFrames: raw.durationFrames || raw.holdFrames || null,
                duplicateOfFrame: raw.duplicateOfFrame || null,
                sourceFrame: raw.sourceFrame || null,
                frameEnd: raw.frameEnd || null,
                sourceFrameEnd: raw.sourceFrameEnd || null,
                cropX: raw.cropX,
                cropY: raw.cropY,
                cropWidth: raw.cropWidth,
                cropHeight: raw.cropHeight,
                canvasWidth: raw.canvasWidth,
                canvasHeight: raw.canvasHeight
            });
        }
        out.sort(function(a, b) {
            return Number(a.frame || 0) - Number(b.frame || 0);
        });
        layer._normFrames = out;
        return out;
    }

    function positiveNumber(value, fallback) {
        var number = Number(value);
        return isFinite(number) && number > 0 ? number : fallback;
    }

    function finiteNumber(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function layerFrameStyle(frame) {
        var base = 'position:absolute;pointer-events:none;';
        if (!frame || frame.cropX == null || frame.cropY == null || !frame.cropWidth || !frame.cropHeight) {
            return base + 'left:0;top:0;width:100%;height:100%;object-fit:contain;';
        }
        var canvasWidth = positiveNumber(frame.canvasWidth, 256);
        var canvasHeight = positiveNumber(frame.canvasHeight, 256);
        var left = finiteNumber(frame.cropX, 0) / canvasWidth * 100;
        var top = finiteNumber(frame.cropY, 0) / canvasHeight * 100;
        var width = positiveNumber(frame.cropWidth, canvasWidth) / canvasWidth * 100;
        var height = positiveNumber(frame.cropHeight, canvasHeight) / canvasHeight * 100;
        return base +
            'left:' + left.toFixed(4) + '%;' +
            'top:' + top.toFixed(4) + '%;' +
            'width:' + width.toFixed(4) + '%;' +
            'height:' + height.toFixed(4) + '%;' +
            'object-fit:fill;';
    }

    function applyLayerFrame(layerImg, frame) {
        if (!layerImg || !frame) return;
        if (frame.url && layerImg.getAttribute('src') !== frame.url) {
            layerImg.setAttribute('src', frame.url);
        }
        layerImg.setAttribute('style', layerFrameStyle(frame));
    }

    function nestedAnimation(iconEntry) {
        return iconEntry && iconEntry.nestedAnimation && typeof iconEntry.nestedAnimation === 'object'
            ? iconEntry.nestedAnimation
            : null;
    }

    function nestedLayers(iconEntry) {
        var nested = nestedAnimation(iconEntry);
        return nested && nested.layers && nested.layers.length ? nested.layers : [];
    }

    function layeredBaseUrl(iconEntry) {
        var nested = nestedAnimation(iconEntry);
        var base = nested && nested.base;
        if (typeof base === 'string') return iconUrl(base);
        if (base && typeof base.uri === 'string') return iconUrl(base.uri);
        return iconEntry && iconEntry.f1 ? iconUrl(iconEntry.f1) : null;
    }

    function isLayeredEntry(iconEntry) {
        return !!(iconEntry && nestedLayers(iconEntry).length && layeredBaseUrl(iconEntry));
    }

    function distinctFrameCount(frames, keys) {
        return Timeline.distinctFrameCount(frames, keys || ['uri']);
    }

    function layeredHasAnimatedFrames(iconEntry) {
        var layers = nestedLayers(iconEntry);
        for (var i = 0; i < layers.length; i++) {
            if (distinctFrameCount(normalizeLayerFrames(layers[i]), LAYER_FRAME_IDENTITY_KEYS) > 1) return true;
        }
        return false;
    }

    function fpsForEntry(iconEntry, fallbackFps) {
        return Timeline.frameRate(iconEntry, fallbackFps, DEFAULT_FPS);
    }

    function selectedFrame(frames, nowMs, fps) {
        return Timeline.selectedFrame(frames, nowMs, fps);
    }

    function preload(url) {
        if (!url || _preloaded[url]) return;
        var img = new Image();
        _preloaded[url] = img;
        img.src = url;
    }

    function shouldAnimate(iconEntry) {
        if (!iconEntry) return false;
        // webp-animated 由浏览器原生播放，对 RAF 驱动器而言不需要逐帧换 src。
        if (isWebpAnimated(iconEntry)) return false;
        if (iconEntry.playback === 'static' || iconEntry.playback === 'static-first-frame') return false;
        if (isLayeredEntry(iconEntry)) return layeredHasAnimatedFrames(iconEntry);
        if (iconEntry.animated === true) return distinctFrameCount(normalizeFrames(iconEntry)) > 1;
        if (!iconEntry.playback) return false;
        return distinctFrameCount(normalizeFrames(iconEntry)) > 1;
    }

    function scheduleAnimation() {
        if (_animationFrame || typeof window === 'undefined' || !window.requestAnimationFrame) return;
        _animationFrame = window.requestAnimationFrame(tickAnimatedIcons);
    }

    function tickAnimatedIcons(nowMs) {
        _animationFrame = 0;
        if (typeof document === 'undefined') return;
        var nodes = document.querySelectorAll('img[data-icon-name][data-icon-animated="1"]');
        var any = false;
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (!document.documentElement.contains(node)) continue;
            var name = node.getAttribute('data-icon-name');
            var iconEntry = entry(name);
            if (!shouldAnimate(iconEntry)) continue;
            var frames = normalizeFrames(iconEntry);
            var frame = selectedFrame(frames, nowMs || 0, fpsForEntry(iconEntry, node.getAttribute('data-icon-fps')));
            if (frame && frame.url && node.getAttribute('src') !== frame.url) {
                node.setAttribute('src', frame.url);
            }
            any = true;
        }
        var layeredNodes = document.querySelectorAll('[data-icon-layered-name][data-icon-layered-animated="1"]');
        for (var l = 0; l < layeredNodes.length; l++) {
            var layeredNode = layeredNodes[l];
            if (!document.documentElement.contains(layeredNode)) continue;
            var layeredName = layeredNode.getAttribute('data-icon-layered-name');
            var layeredEntry = entry(layeredName);
            if (!shouldAnimate(layeredEntry)) continue;
            var layers = nestedLayers(layeredEntry);
            for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
                var layerImg = layeredNode.querySelector('img[data-icon-layer-index="' + layerIndex + '"]');
                if (!layerImg) continue;
                var layerFrames = normalizeLayerFrames(layers[layerIndex]);
                var layerFrame = selectedFrame(
                    layerFrames,
                    nowMs || 0,
                    fpsForEntry(layers[layerIndex], layeredNode.getAttribute('data-icon-fps'))
                );
                applyLayerFrame(layerImg, layerFrame);
            }
            any = true;
        }
        if (any) scheduleAnimation();
    }

    function enhanceLayeredNode(node) {
        if (!node || node.nodeType !== 1) return;
        var name = node.getAttribute && node.getAttribute('data-icon-layered-name');
        if (!name) return;
        var iconEntry = entry(name);
        if (!isLayeredEntry(iconEntry)) return;
        var base = node.querySelector('img[data-icon-layer-base="1"]');
        var baseUrl = layeredBaseUrl(iconEntry);
        if (base && baseUrl && base.getAttribute('src') !== baseUrl) base.setAttribute('src', baseUrl);
        var layers = nestedLayers(iconEntry);
        var animated = false;
        for (var i = 0; i < layers.length; i++) {
            var frames = normalizeLayerFrames(layers[i]);
            var layerImg = node.querySelector('img[data-icon-layer-index="' + i + '"]');
            if (!frames.length || !layerImg) continue;
            applyLayerFrame(layerImg, frames[0]);
            for (var f = 0; f < frames.length; f++) preload(frames[f].url);
            if (distinctFrameCount(frames, LAYER_FRAME_IDENTITY_KEYS) > 1) animated = true;
        }
        if (animated) {
            node.setAttribute('data-icon-layered-animated', '1');
            scheduleAnimation();
        } else {
            node.removeAttribute('data-icon-layered-animated');
        }
    }

    function enhanceNode(node) {
        if (!node || node.nodeType !== 1) return;
        var name = node.getAttribute && node.getAttribute('data-icon-name');
        if (!name) return;
        var iconEntry = entry(name);
        if (isWebpAnimated(iconEntry)) {
            // 单张动图：只 set 一次 src，浏览器原生播放；不挂 data-icon-animated。
            var webpUrl = webpAnimatedUrl(iconEntry);
            if (!webpUrl) return;
            if (node.getAttribute('src') !== webpUrl) node.setAttribute('src', webpUrl);
            node.removeAttribute('data-icon-animated');
            return;
        }
        var frames = normalizeFrames(iconEntry);
        if (!frames.length) return;
        if (isLayeredEntry(iconEntry)) {
            node.setAttribute('src', frames[0].url);
            node.removeAttribute('data-icon-animated');
            return;
        }
        node.setAttribute('src', frames[0].url);
        if (shouldAnimate(iconEntry)) {
            for (var i = 0; i < frames.length; i++) preload(frames[i].url);
            node.setAttribute('data-icon-animated', '1');
            scheduleAnimation();
        } else {
            node.removeAttribute('data-icon-animated');
        }
    }

    function enhance(root) {
        if (typeof document === 'undefined') return;
        root = root || document;
        if (root.nodeType === 1 && root.getAttribute && root.getAttribute('data-icon-layered-name')) {
            enhanceLayeredNode(root);
        }
        if (root.nodeType === 1 && root.getAttribute && root.getAttribute('data-icon-name')) {
            enhanceNode(root);
        }
        var layeredNodes = root.querySelectorAll ? root.querySelectorAll('[data-icon-layered-name]') : [];
        for (var l = 0; l < layeredNodes.length; l++) enhanceLayeredNode(layeredNodes[l]);
        var nodes = root.querySelectorAll ? root.querySelectorAll('img[data-icon-name]') : [];
        for (var i = 0; i < nodes.length; i++) enhanceNode(nodes[i]);
    }

    function startObserver() {
        if (_observer || typeof MutationObserver === 'undefined' || typeof document === 'undefined') return;
        if (!document.body) return;
        _observer = new MutationObserver(function(records) {
            for (var i = 0; i < records.length; i++) {
                if (records[i].type === 'attributes') {
                    enhance(records[i].target);
                    continue;
                }
                var added = records[i].addedNodes || [];
                for (var j = 0; j < added.length; j++) enhance(added[j]);
            }
        });
        _observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['data-icon-name', 'data-icon-layered-name']
        });
        enhance(document);
    }

    function layeredHtml(name, iconEntry, className, attrs) {
        var layers = nestedLayers(iconEntry);
        var baseUrl = layeredBaseUrl(iconEntry);
        if (!layers.length || !baseUrl) return '';
        var wrapperClass = 'cfn-layered-icon' + (className ? ' ' + className : '');
        var imgClass = 'cfn-layered-icon-part';
        var childErrorAttr = /\sonerror\s*=/.test(attrs || '')
            ? ''
            : ' onerror="if(this.parentNode){this.parentNode.dispatchEvent(new Event(\'error\'))}"';
        var html = '<span class="' + escapeAttr(wrapperClass) + '"' +
            ' data-icon-layered-name="' + escapeAttr(name) + '"' +
            ' data-icon-fps="' + escapeAttr(iconEntry.fps || DEFAULT_FPS) + '"' +
            ' style="position:relative;display:inline-block;vertical-align:middle;line-height:0;overflow:hidden;">' +
            '<img class="' + escapeAttr(imgClass + ' cfn-layered-icon-base') + '"' +
            ' src="' + escapeAttr(baseUrl) + '"' +
            ' data-icon-layer-base="1"' +
            ' style="display:block;width:100%;height:100%;object-fit:contain;"' +
            attrs + childErrorAttr +
            ' alt="">';
        for (var i = 0; i < layers.length; i++) {
            var frames = normalizeLayerFrames(layers[i]);
            if (!frames.length) continue;
            html += '<img class="' + escapeAttr(imgClass + ' cfn-layered-icon-layer') + '"' +
                ' src="' + escapeAttr(frames[0].url) + '"' +
                ' data-icon-layer-index="' + i + '"' +
                ' style="' + escapeAttr(layerFrameStyle(frames[0])) + '"' +
                attrs + childErrorAttr +
                ' alt="">';
        }
        html += '</span>';
        return html;
    }

    return {
        load: function(cb) {
            if (_map) {
                if (typeof cb === 'function') cb();
                return;
            }
            if (typeof cb === 'function') _queue.push(cb);
            if (_loading) return;
            _loading = true;
            fetch('icons/manifest.json')
                .then(function(r) { return r.json(); })
                .then(function(d) { _map = d || {}; _loading = false; startObserver(); flushQueue(); })
                .catch(function() { _map = {}; _loading = false; flushQueue(); });
        },
        entry: function(name) {
            return entry(name);
        },
        frames: function(name) {
            return normalizeFrames(entry(name));
        },
        resolveFrame: function(name, frame) {
            var frameList = normalizeFrames(entry(name));
            if (!frameList.length) return null;
            if (frame == null) return frameList[0].url;
            for (var i = 0; i < frameList.length; i++) {
                if (String(frameList[i].frame) === String(frame)) return frameList[i].url;
            }
            return null;
        },
        isAnimated: function(name) {
            return shouldAnimate(entry(name));
        },
        html: function(name, className, attrs) {
            var iconEntry = entry(name);
            attrs = attrs || '';
            var cls = className ? ' class="' + escapeAttr(className) + '"' : '';
            if (isWebpAnimated(iconEntry)) {
                // 单张动图 .webp：直接 <img src>，Chromium 原生播放，不进 RAF 循环。
                var webpUrl = webpAnimatedUrl(iconEntry);
                if (!webpUrl) return '';
                return '<img' + cls +
                    ' src="' + escapeAttr(webpUrl) + '"' +
                    ' data-icon-name="' + escapeAttr(name) + '"' +
                    attrs +
                    ' alt="">';
            }
            if (isLayeredEntry(iconEntry)) return layeredHtml(name, iconEntry, className, attrs);
            var frameList = normalizeFrames(iconEntry);
            if (!frameList.length) return '';
            return '<img' + cls +
                ' src="' + escapeAttr(frameList[0].url) + '"' +
                ' data-icon-name="' + escapeAttr(name) + '"' +
                attrs +
                ' alt="">';
        },
        applyIconToImage: function(img, name) {
            if (!img) return false;
            img.setAttribute('data-icon-name', name || '');
            enhanceNode(img);
            return !!normalizeFrames(entry(name)).length;
        },
        enhance: function(root) {
            enhance(root);
        },
        resolve: function(name) {
            var frameList = normalizeFrames(entry(name));
            return frameList.length ? frameList[0].url : null;
        }
    };
})();
