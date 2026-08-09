/**
 * PortraitResolver — identity-first enemy portrait loading for Web consumers.
 *
 * Identity/provenance lives in the generated manifest.  This module owns only
 * consumer resolution, JK live-variant mapping, fail-soft loading and visual
 * atmosphere tags.  Team and Arena share this implementation; PortraitResolver
 * remains a compatibility alias while EnemyPortraits is the consumer-neutral
 * public name.
 */
(function() {
    'use strict';

    var browserWindow = typeof window !== 'undefined' ? window : {};

    function trailingSlash(value) {
        value = value == null ? '' : String(value);
        return value && value.charAt(value.length - 1) !== '/' ? value + '/' : value;
    }

    // Harness pages live below modules/**/dev and therefore cannot rely on the
    // production document base.  Consumers may project both roots before this
    // script loads without changing manifest-owned identity/provenance data.
    var PORTRAIT_ROOT = trailingSlash(browserWindow.CF7_PORTRAIT_ROOT || 'assets/enemy-portraits/');
    var LEGACY_ROOT = trailingSlash(browserWindow.CF7_PORTRAIT_LEGACY_ROOT || 'assets/pets/');
    var MANIFEST_URL = PORTRAIT_ROOT + 'manifest.json';
    var LOCKED_URL = browserWindow.CF7_PORTRAIT_LOCKED_URL || (LEGACY_ROOT + 'pet_locked.png');
    var MANIFEST_RETRY_BASE_MS = Math.max(1,
        Number(browserWindow.CF7_PORTRAIT_MANIFEST_RETRY_BASE_MS) || 250);
    var MANIFEST_RETRY_MAX_MS = Math.max(MANIFEST_RETRY_BASE_MS,
        Number(browserWindow.CF7_PORTRAIT_MANIFEST_RETRY_MAX_MS) || 4000);
    var PNG_FIRST_MIN_SVG_BYTES = Math.max(1,
        Number(browserWindow.CF7_PORTRAIT_PNG_FIRST_MIN_SVG_BYTES) || (2 * 1024 * 1024));
    var PNG_FIRST_SIZE_RATIO = Math.max(1,
        Number(browserWindow.CF7_PORTRAIT_PNG_FIRST_SIZE_RATIO) || 8);
    var _manifest = null;
    var _manifestPromise = null;
    var _manifestFailureCount = 0;
    var _manifestRetryAfter = 0;
    var _mountSeq = 0;
    var _svgVisualCache = {};

    function loadJson(url) {
        if (typeof fetch === 'function') {
            return fetch(url, { cache: 'no-cache', credentials: 'same-origin' }).then(function(response) {
                if (!response.ok) throw new Error('portrait manifest HTTP ' + response.status);
                return response.json();
            });
        }
        return new Promise(function(resolve, reject) {
            if (typeof XMLHttpRequest === 'undefined') {
                reject(new Error('portrait manifest transport unavailable'));
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
                    reject(new Error('portrait manifest XHR ' + xhr.status));
                }
            };
            xhr.send();
        });
    }

    function validateManifest(value) {
        var supported = value && (value.schema === 'cf7.team-enemy-portrait-manifest.v1'
            || value.schema === 'cf7.enemy-portrait-manifest.v1');
        if (!supported
                || !value.entries || typeof value.entries !== 'object') {
            throw new Error('portrait manifest schema mismatch');
        }
        return value;
    }

    function loadManifest() {
        if (_manifest) return Promise.resolve(_manifest);
        if (_manifestPromise) return _manifestPromise;
        if (_manifestRetryAfter > Date.now()) return Promise.resolve(null);
        _manifestPromise = loadJson(MANIFEST_URL).then(function(value) {
            _manifest = validateManifest(value);
            _manifestFailureCount = 0;
            _manifestRetryAfter = 0;
            return _manifest;
        }).catch(function() {
            // Missing/corrupt modern assets are never allowed to blank a card.
            // Keep the rejection private and let every mount retain legacy art,
            // but release the in-flight promise so a later mount can retry. A
            // short bounded cooldown prevents a broken local server from being
            // hammered once per visible card.
            _manifestPromise = null;
            _manifestFailureCount++;
            var exponent = Math.min(6, Math.max(0, _manifestFailureCount - 1));
            var delay = Math.min(MANIFEST_RETRY_MAX_MS,
                MANIFEST_RETRY_BASE_MS * Math.pow(2, exponent));
            _manifestRetryAfter = Date.now() + delay;
            return null;
        });
        return _manifestPromise;
    }

    function textOf(value) {
        return value == null ? '' : String(value);
    }

    function remapAssetUrl(url) {
        url = textOf(url);
        if (url.indexOf('assets/enemy-portraits/') === 0) {
            return PORTRAIT_ROOT + url.substring('assets/enemy-portraits/'.length);
        }
        if (url.indexOf('assets/pets/') === 0) {
            return LEGACY_ROOT + url.substring('assets/pets/'.length);
        }
        return url;
    }

    function resolveAlias(manifest, portraitRef) {
        var seen = {};
        var current = portraitRef;
        var variantKey = null;
        while (manifest.aliases && manifest.aliases[current] && !seen[current]) {
            seen[current] = true;
            var alias = manifest.aliases[current];
            if (!variantKey && alias.variantKey) variantKey = alias.variantKey;
            current = alias.targetPortraitRef;
        }
        return { portraitRef: current, variantKey: variantKey };
    }

    function jkVariant(context) {
        var schemeStatus = context && context.schemeStatus;
        var toggle = schemeStatus && schemeStatus['切换发型'];
        var value = toggle && (toggle.toggleValue != null ? toggle.toggleValue : toggle.value);
        value = textOf(value);
        if (value.indexOf('白') >= 0) return 'white';
        if (value.indexOf('橙') >= 0) return 'orange';
        return null;
    }

    function selectVariant(entry, portraitRef, context, aliasVariantKey) {
        // portraitVariant is the stable Host/AS2 projection.  variantKey is
        // retained as a generic caller override; localized schemeStatus is
        // only a compatibility bridge for the current Team snapshot.
        var requested = context && (context.portraitVariant || context.variantKey);
        if (!requested) requested = aliasVariantKey;
        if (!requested && portraitRef === '敌人-武装JK') requested = jkVariant(context);
        if (requested && entry.variants[requested]) return requested;
        return entry.defaultVariant;
    }

    function subjectFormatPreference(subject) {
        subject = subject || {};
        // preferredFormat is generated from the audited SVG representation
        // metadata (including embeddedRasterCount/isRasterHeavy) and is the
        // sole ordering authority when present.
        var explicit = textOf(subject.preferredFormat).toLowerCase();
        if (explicit === 'png') return 'png';
        if (explicit === 'svg') return 'svg';
        return '';
    }

    function shouldPreferPng(subject) {
        subject = subject || {};
        if (!subject.pngFallback || !subject.pngFallback.url) return false;
        var preference = subjectFormatPreference(subject);
        if (preference) return preference === 'png';
        var svgBytes = Number(subject.svg && subject.svg.bytes);
        var pngBytes = Number(subject.pngFallback.bytes);
        // Legacy manifests have no representation metadata. Keep this fallback
        // deliberately conservative so ordinary, moderately large pure-vector
        // portraits stay SVG-primary; it only catches extreme raster wrappers.
        return isFinite(svgBytes) && isFinite(pngBytes) && svgBytes >= PNG_FIRST_MIN_SVG_BYTES
            && pngBytes > 0 && svgBytes >= pngBytes * PNG_FIRST_SIZE_RATIO;
    }

    function inferTheme(portraitRef) {
        var ref = textOf(portraitRef).toLowerCase();
        if (/(凤凰|火焰|黑炎|赤焰|菲尼克斯|fire|phoenix)/.test(ref)) return 'ember';
        if (/(机器人|机械|终结者|改造人|无人机|小飞机|arms|t800|exusiai|arius|archai|malakim)/.test(ref)) return 'machine';
        if (/(僵尸|尸母|死士|不死|骷髅|无常|血腥|undead)/.test(ref)) return 'undead';
        if (/(异形|兽|犬|狗|虫|蛛|虎|马|鳄|蛙|蛇|血鼠|serpent)/.test(ref)) return 'beast';
        if (/(方舟|诺亚|黑洞|魔神|虚拟|投影|妖姬|noah|arc)/.test(ref)) return 'arcane';
        return 'human';
    }

    function descriptor(manifest, context) {
        if (!manifest || !context) return null;
        var requestedRef = context.portraitRef || context.identifier;
        if (!requestedRef) return null;
        var aliasResolution = resolveAlias(manifest, requestedRef);
        var resolvedRef = aliasResolution.portraitRef;
        var entry = manifest.entries[resolvedRef];
        if (!entry || !entry.variants) return null;
        var variantKey = selectVariant(entry, resolvedRef, context, aliasResolution.variantKey);
        var variant = entry.variants[variantKey];
        if (!variant || variant.status !== 'human_accepted' || !variant.subject) {
            return {
                portraitRef: resolvedRef,
                requestedPortraitRef: requestedRef,
                variantKey: variantKey,
                theme: inferTheme(resolvedRef),
                status: variant ? variant.status : 'missing_variant',
                legacyUrl: remapAssetUrl(context.legacyUrl || (variant && variant.legacyUrl) || LOCKED_URL)
            };
        }
        return {
            portraitRef: resolvedRef,
            requestedPortraitRef: requestedRef,
            variantKey: variantKey,
            theme: inferTheme(resolvedRef),
            status: variant.status,
            svgUrl: variant.subject.svg && remapAssetUrl(variant.subject.svg.url),
            pngUrl: variant.subject.pngFallback && remapAssetUrl(variant.subject.pngFallback.url),
            preferPng: shouldPreferPng(variant.subject),
            legacyUrl: remapAssetUrl(context.legacyUrl || variant.legacyUrl || LOCKED_URL)
        };
    }

    function mark(container, value, source, context) {
        if (!container) return;
        container.classList.add('entity-portrait-art');
        if (context && context.consumer === 'team') container.classList.add('team-portrait-art');
        container.setAttribute('data-portrait-theme', value && value.theme ? value.theme : 'legacy');
        container.setAttribute('data-portrait-source', source || 'legacy');
        if (value && value.portraitRef) container.setAttribute('data-portrait-ref', value.portraitRef);
        else container.removeAttribute('data-portrait-ref');
        if (value && value.variantKey) container.setAttribute('data-portrait-variant', value.variantKey);
        else container.removeAttribute('data-portrait-variant');
    }

    function isCurrent(container, token) {
        return !!container && container.getAttribute('data-portrait-request') === token
            && (container.isConnected !== false);
    }

    function svgHasVisiblePixels(img, url) {
        if (Object.prototype.hasOwnProperty.call(_svgVisualCache, url)) return _svgVisualCache[url];
        try {
            var canvas = document.createElement('canvas');
            canvas.width = 32;
            canvas.height = 32;
            var context = canvas.getContext('2d', { willReadFrequently: true });
            context.clearRect(0, 0, 32, 32);
            context.drawImage(img, 0, 0, 32, 32);
            var pixels = context.getImageData(0, 0, 32, 32).data;
            var visible = false;
            for (var i = 3; i < pixels.length; i += 4) {
                if (pixels[i] > 4) { visible = true; break; }
            }
            _svgVisualCache[url] = visible;
            return visible;
        } catch (ignore) {
            // Same-origin production assets are readable. If a downstream host
            // changes that contract, preserve onload semantics instead of
            // incorrectly rejecting a valid cross-origin portrait.
            return true;
        }
    }

    function applyChain(container, img, value, token, context) {
        var chain = [];
        if (value && value.preferPng) {
            if (value.pngUrl) chain.push({ url: value.pngUrl, source: 'png' });
            if (value.svgUrl) chain.push({ url: value.svgUrl, source: 'svg' });
        } else {
            if (value && value.svgUrl) chain.push({ url: value.svgUrl, source: 'svg' });
            if (value && value.pngUrl) chain.push({ url: value.pngUrl, source: 'png' });
        }
        chain.push({ url: value && value.legacyUrl ? value.legacyUrl : LOCKED_URL, source: 'legacy' });
        if (chain[chain.length - 1].url !== LOCKED_URL) chain.push({ url: LOCKED_URL, source: 'locked' });
        var index = 0;
        function attempt() {
            if (!isCurrent(container, token)) return;
            var step = chain[index++];
            if (!step) return;
            img.onerror = function() { attempt(); };
            img.onload = function() {
                if (!isCurrent(container, token)) return;
                if (step.source === 'svg' && !svgHasVisiblePixels(img, step.url)) {
                    attempt();
                    return;
                }
                mark(container, value, step.source, context);
            };
            img.src = step.url;
        }
        attempt();
    }

    function mount(container, img, context) {
        context = context || {};
        if (!container || !img) return Promise.resolve(null);
        var token = 'portrait_' + (++_mountSeq) + '_' + Date.now();
        container.setAttribute('data-portrait-request', token);
        img.alt = '';
        img.draggable = false;
        img.decoding = 'async';
        var legacy = remapAssetUrl(context.legacyUrl || LOCKED_URL);
        // Do not start a legacy request before the identity manifest settles.
        // Most accepted portraits replace it within the same turn, which makes
        // Edge report the deliberately cancelled pet_locked.png request as a
        // network failure and also causes a visible locked-art flash.
        img.onerror = null;
        img.onload = null;
        img.removeAttribute('src');
        container.classList.add('entity-portrait-art');
        if (context.consumer === 'team') container.classList.add('team-portrait-art');
        container.setAttribute('data-portrait-theme', context.portraitRef ? inferTheme(context.portraitRef) : 'legacy');
        container.removeAttribute('data-portrait-source');
        container.removeAttribute('data-portrait-ref');
        container.removeAttribute('data-portrait-variant');
        if (context.locked) {
            // Locked/spoiler cards are often assembled off-DOM.  They must
            // receive the sealed image synchronously and are never upgraded,
            // so the connected-node guard used by the async chain is neither
            // necessary nor correct here.
            var lockedAttempted = legacy === LOCKED_URL;
            img.onerror = function() {
                // HTMLImageElement.src is absolute even when LOCKED_URL is
                // relative, so string comparison cannot be the retry fence.
                // Clear the handler before the one allowed fallback request.
                this.onerror = null;
                if (!lockedAttempted) {
                    lockedAttempted = true;
                    this.src = LOCKED_URL;
                }
            };
            img.src = legacy;
            mark(container, { theme: 'legacy' }, 'legacy', context);
            return Promise.resolve(null);
        }
        return loadManifest().then(function(manifest) {
            if (!isCurrent(container, token)) return null;
            var value = descriptor(manifest, context);
            if (!value || value.status !== 'human_accepted') {
                applyChain(container, img, value || { legacyUrl: legacy, theme: 'legacy' }, token, context);
                return value;
            }
            applyChain(container, img, value, token, context);
            return value;
        });
    }

    function summarizeCoverage(manifest, portraitRefs) {
        var unique = {};
        var refs = [];
        var blank = 0;
        portraitRefs = portraitRefs || [];
        for (var i = 0; i < portraitRefs.length; i++) {
            var ref = textOf(portraitRefs[i]).trim();
            if (!ref) { blank++; continue; }
            if (unique[ref]) continue;
            unique[ref] = true;
            refs.push(ref);
        }
        var result = {
            manifestAvailable: !!manifest,
            total: refs.length,
            ready: 0,
            missing: 0,
            blank: blank,
            aliasResolved: 0,
            readyRefs: [],
            missingRefs: []
        };
        for (var r = 0; r < refs.length; r++) {
            var requestedRef = refs[r];
            var resolvedRef = manifest ? resolveAlias(manifest, requestedRef).portraitRef : requestedRef;
            if (resolvedRef !== requestedRef) result.aliasResolved++;
            var value = manifest ? descriptor(manifest, { portraitRef: requestedRef }) : null;
            if (value && value.status === 'human_accepted') {
                result.ready++;
                result.readyRefs.push(requestedRef);
            } else {
                result.missing++;
                result.missingRefs.push(requestedRef);
            }
        }
        return result;
    }

    var api = {
        loadManifest: loadManifest,
        mount: mount,
        inferTheme: inferTheme,
        fallbackUrl: function() { return LOCKED_URL; },
        coverage: function(portraitRefs) {
            return loadManifest().then(function(manifest) {
                return summarizeCoverage(manifest, portraitRefs);
            });
        },
        resolve: function(context) { return descriptor(_manifest, context || {}); },
        // Deterministic harness seam; never used by production callers.
        __setManifestForTests: function(value) {
            _manifest = validateManifest(value);
            _manifestPromise = Promise.resolve(_manifest);
            _manifestFailureCount = 0;
            _manifestRetryAfter = 0;
        },
        __resetForTests: function() {
            _manifest = null;
            _manifestPromise = null;
            _manifestFailureCount = 0;
            _manifestRetryAfter = 0;
            _mountSeq = 0;
            _svgVisualCache = {};
        }
    };
    if (typeof window !== 'undefined') {
        window.EnemyPortraits = api;
        window.PortraitResolver = api;
    }
})();
