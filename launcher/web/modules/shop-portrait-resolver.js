/**
 * ShopPortraits - exact shopId portrait resolution for archive consumers.
 *
 * The generated manifest is the only identity authority. This runtime does
 * not import DialogueView/MapPanel, normalize labels, or guess aliases. A
 * missing/corrupt manifest or failed image decode leaves the caller's fixed
 * placeholder visible and never removes the adjacent source text.
 */
(function() {
    'use strict';

    var browserWindow = typeof window !== 'undefined' ? window : {};

    function trailingSlash(value) {
        value = value == null ? '' : String(value);
        return value && value.charAt(value.length - 1) !== '/' ? value + '/' : value;
    }

    var PORTRAIT_ROOT = trailingSlash(browserWindow.CF7_SHOP_PORTRAIT_ROOT
        || 'assets/shop-portraits/');
    var MANIFEST_URL = PORTRAIT_ROOT + 'manifest.json';
    var RETRY_BASE_MS = Math.max(1,
        Number(browserWindow.CF7_SHOP_PORTRAIT_RETRY_BASE_MS) || 250);
    var RETRY_MAX_MS = Math.max(RETRY_BASE_MS,
        Number(browserWindow.CF7_SHOP_PORTRAIT_RETRY_MAX_MS) || 4000);
    var _manifest = null;
    var _manifestPromise = null;
    var _failureCount = 0;
    var _retryAfter = 0;
    var _requestSequence = 0;

    function isRecord(value) {
        return !!value && typeof value === 'object' && !Array.isArray(value);
    }

    function exactKeys(value, expected) {
        if (!isRecord(value)) return false;
        var actual = Object.keys(value).sort();
        expected = expected.slice().sort();
        if (actual.length !== expected.length) return false;
        for (var i = 0; i < actual.length; i++) {
            if (actual[i] !== expected[i]) return false;
        }
        return true;
    }

    function isInteger(value) {
        return typeof value === 'number' && isFinite(value) && Math.floor(value) === value;
    }

    function isExactShopId(value) {
        if (typeof value !== 'string' || value.length === 0 || value.length > 80
                || value !== value.trim() || value.toLowerCase() === 'undefined'
                || /[\u0000-\u001f\u007f]/.test(value)) return false;
        for (var index = 0; index < value.length; index++) {
            var code = value.charCodeAt(index);
            if (code >= 128 && code <= 159) return false;
        }
        return true;
    }

    function validateBounds(bounds) {
        if (!exactKeys(bounds, ['x', 'y', 'width', 'height'])) return false;
        if (!isInteger(bounds.x) || !isInteger(bounds.y)
                || !isInteger(bounds.width) || !isInteger(bounds.height)) return false;
        return bounds.x >= 0 && bounds.y >= 0 && bounds.width > 0 && bounds.height > 0
            && bounds.x + bounds.width <= 256 && bounds.y + bounds.height <= 256;
    }

    function validateEntry(entry) {
        if (!exactKeys(entry, ['uri', 'width', 'height', 'bounds', 'sha256'])) return false;
        if (entry.width !== 256 || entry.height !== 256 || !validateBounds(entry.bounds)) return false;
        if (typeof entry.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(entry.sha256)) return false;
        if (typeof entry.uri !== 'string') return false;
        var uriMatch = /^subjects\/([0-9a-f]{64})\.png$/.exec(entry.uri);
        return !!uriMatch && uriMatch[1] === entry.sha256;
    }

    function validateManifest(value) {
        if (!exactKeys(value, ['schema', 'geometry', 'entries'])
                || value.schema !== 'cf7-shop-portraits-v1'
                || !exactKeys(value.geometry, ['width', 'height'])
                || value.geometry.width !== 256 || value.geometry.height !== 256
                || !isRecord(value.entries)) {
            throw new Error('shop portrait manifest schema mismatch');
        }
        var shopIds = Object.keys(value.entries);
        if (shopIds.length > 256) throw new Error('shop portrait manifest entry limit exceeded');
        for (var i = 0; i < shopIds.length; i++) {
            var shopId = shopIds[i];
            if (!isExactShopId(shopId) || !validateEntry(value.entries[shopId])) {
                throw new Error('shop portrait manifest entry mismatch: ' + shopId);
            }
        }
        return value;
    }

    function loadJson(url) {
        if (typeof fetch === 'function') {
            return fetch(url, { cache: 'no-cache', credentials: 'same-origin' }).then(function(response) {
                if (!response.ok) throw new Error('shop portrait manifest HTTP ' + response.status);
                return response.json();
            });
        }
        return new Promise(function(resolve, reject) {
            if (typeof XMLHttpRequest === 'undefined') {
                reject(new Error('shop portrait manifest transport unavailable'));
                return;
            }
            var xhr = new XMLHttpRequest();
            xhr.open('GET', url, true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== 4) return;
                if (xhr.status >= 200 && xhr.status < 300) {
                    try { resolve(JSON.parse(xhr.responseText)); }
                    catch (error) { reject(error); }
                } else {
                    reject(new Error('shop portrait manifest XHR ' + xhr.status));
                }
            };
            xhr.send();
        });
    }

    function loadManifest() {
        if (_manifest) return Promise.resolve(_manifest);
        if (_manifestPromise) return _manifestPromise;
        if (_retryAfter > Date.now()) return Promise.resolve(null);
        _manifestPromise = loadJson(MANIFEST_URL).then(function(value) {
            _manifest = validateManifest(value);
            _failureCount = 0;
            _retryAfter = 0;
            return _manifest;
        }).catch(function() {
            _manifestPromise = null;
            _failureCount++;
            var exponent = Math.min(6, Math.max(0, _failureCount - 1));
            var delay = Math.min(RETRY_MAX_MS, RETRY_BASE_MS * Math.pow(2, exponent));
            _retryAfter = Date.now() + delay;
            return null;
        });
        return _manifestPromise;
    }

    function descriptor(manifest, shopId) {
        if (!manifest || !isExactShopId(shopId)
                || !Object.prototype.hasOwnProperty.call(manifest.entries, shopId)) return null;
        var entry = manifest.entries[shopId];
        return {
            shopId: shopId,
            url: PORTRAIT_ROOT + entry.uri,
            width: entry.width,
            height: entry.height,
            bounds: {
                x: entry.bounds.x,
                y: entry.bounds.y,
                width: entry.bounds.width,
                height: entry.bounds.height
            },
            sha256: entry.sha256
        };
    }

    function isCurrent(container, token) {
        return !!container && typeof container.getAttribute === 'function'
            && container.getAttribute('data-shop-portrait-request') === token
            && container.isConnected !== false;
    }

    function markPlaceholder(container, img) {
        if (img) {
            img.onerror = null;
            img.onload = null;
            if (typeof img.removeAttribute === 'function') img.removeAttribute('src');
        }
        if (!container) return;
        if (container.classList) container.classList.add('shop-portrait-art');
        if (typeof container.setAttribute === 'function') {
            container.setAttribute('data-shop-portrait-source', 'placeholder');
            if (typeof container.removeAttribute === 'function') {
                container.removeAttribute('data-shop-portrait-id');
            }
        }
    }

    function mount(container, img, shopId) {
        if (!container || !img || typeof container.setAttribute !== 'function') {
            return Promise.resolve(null);
        }
        var token = 'shop_portrait_' + (++_requestSequence) + '_' + Date.now();
        container.setAttribute('data-shop-portrait-request', token);
        img.alt = '';
        if (typeof img.setAttribute === 'function') {
            img.setAttribute('alt', '');
            img.setAttribute('aria-hidden', 'true');
        }
        img.draggable = false;
        img.decoding = 'async';
        markPlaceholder(container, img);

        if (!isExactShopId(shopId)) return Promise.resolve(null);
        return loadManifest().then(function(manifest) {
            if (!isCurrent(container, token)) return null;
            var value = descriptor(manifest, shopId);
            if (!value) return null;
            img.onerror = function() {
                if (!isCurrent(container, token)) return;
                markPlaceholder(container, img);
            };
            img.onload = function() {
                if (!isCurrent(container, token)) return;
                container.setAttribute('data-shop-portrait-source', 'manifest');
                container.setAttribute('data-shop-portrait-id', value.shopId);
            };
            img.src = value.url;
            return value;
        });
    }

    var api = {
        loadManifest: loadManifest,
        mount: mount,
        resolve: function(shopId) { return descriptor(_manifest, shopId); },
        resolveAsync: function(shopId) {
            return loadManifest().then(function(manifest) { return descriptor(manifest, shopId); });
        },
        // Deterministic test seams. Production consumers must not inject data.
        __setManifestForTests: function(value) {
            _manifest = validateManifest(value);
            _manifestPromise = Promise.resolve(_manifest);
            _failureCount = 0;
            _retryAfter = 0;
        },
        __resetForTests: function() {
            _manifest = null;
            _manifestPromise = null;
            _failureCount = 0;
            _retryAfter = 0;
            _requestSequence = 0;
        }
    };

    if (typeof window !== 'undefined') window.ShopPortraits = api;
})();
