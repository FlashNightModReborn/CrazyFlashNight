/**
 * Toast module - 全站 L1 瞬时反馈总线（上下文感知：面板期浮条 / 离场刘海回执）。
 *
 * 面板打开期间 NativeHudOverlay 会被 SW_HIDE 挂起，过去所有面板报错/阻断提示
 * 只发 panel-toast 给刘海导致面板内完全不可见。本模块按上下文分流：
 * - 面板打开态（且未声明 opts.persistAfterClose）：在当前面板顶部居中（紧贴顶栏下方）
 *   即时渲染唯一 #panel-feedback-banner（单行 upsert 覆盖、pointer-events:none、
 *   四态语义色轨+图标、pure textContent 防 XSS），不污染关窗后的刘海；
 * - 无面板打开或 opts.persistAfterClose === true：继续经 Bridge.send('panel-toast')
 *   上送 Host → NativeHud NotchWidget（保留 ADR D6 离场回执）。
 *
 * severity 音效契约（契约 §6）：
 * - 'error'   → BootstrapAudio.cue('rejected')
 * - 'warning' → BootstrapAudio.cue('illegal')
 * - 'success' → BootstrapAudio.cue('success')
 * - 'info' / 缺省 / opts.silent === true → 静默（已有显式结果音的路径不传或传 silent:true）。
 */
var Toast = (function() {
    'use strict';

    var SEVERITY_ICONS = {
        error: '✕',
        warning: '!',
        success: '✓',
        info: 'i'
    };
    var BANNER_ID = 'panel-feedback-banner';
    var DEFAULT_DURATION_MS = {
        error: 4500,
        warning: 4500,
        success: 3200,
        info: 3200
    };

    var _bannerEl = null;
    var _iconEl = null;
    var _textEl = null;
    var _hideTimer = null;
    var _pulseTimer = null;
    var _sequence = 0;
    var _last = null;

    function normalizeSeverity(severity) {
        if (severity === 'error' || severity === 'warning'
                || severity === 'success' || severity === 'info') {
            return severity;
        }
        return 'info';
    }

    function toPlainText(rawHtml) {
        if (rawHtml == null) return '';
        return String(rawHtml)
            .replace(/<br\s*\/?>/gi, ' ')
            .replace(/<[^>]+>/g, '')
            .replace(/\s+/g, ' ')
            .trim();
    }

    function isPanelVisible() {
        if (typeof document === 'undefined' || !document) return false;
        if (typeof Panels !== 'undefined' && Panels
                && typeof Panels.isOpen === 'function' && Panels.isOpen()) {
            return true;
        }
        var container = document.getElementById('panel-container');
        if (!container) return false;
        if (container.hidden || container.style.display === 'none') return false;
        var rect = container.getBoundingClientRect ? container.getBoundingClientRect() : null;
        return !rect || (rect.width > 0 && rect.height > 0);
    }

    function ensureBanner() {
        if (typeof document === 'undefined' || !document || !document.createElement) return null;
        var host = document.getElementById('panel-container') || document.body;
        if (!host) return null;
        if (!_bannerEl) {
            _bannerEl = document.getElementById(BANNER_ID);
        }
        if (!_bannerEl) {
            var el = document.createElement('div');
            el.id = BANNER_ID;
            el.className = 'panel-feedback-banner';
            el.setAttribute('role', 'status');
            el.setAttribute('aria-live', 'polite');
            el.setAttribute('aria-atomic', 'true');
            el.hidden = true;
            var icon = document.createElement('span');
            icon.className = 'panel-feedback-icon';
            icon.setAttribute('aria-hidden', 'true');
            var text = document.createElement('span');
            text.className = 'panel-feedback-text';
            el.appendChild(icon);
            el.appendChild(text);
            _bannerEl = el;
            _iconEl = icon;
            _textEl = text;
        } else {
            _iconEl = _bannerEl.querySelector('.panel-feedback-icon');
            _textEl = _bannerEl.querySelector('.panel-feedback-text');
        }
        if (_bannerEl.parentNode !== host) {
            host.appendChild(_bannerEl);
        }
        return _bannerEl;
    }

    function syncBannerGeometry(el) {
        if (!el || typeof document === 'undefined' || !document) return;
        var content = document.getElementById('panel-content');
        var target = content && content.querySelector('.panel-scale-shell:not([hidden])')
            || content || document.getElementById('panel-container');
        var rect = target && target.getBoundingClientRect ? target.getBoundingClientRect() : null;
        if (rect && rect.width > 0 && rect.height > 0) {
            var scale = Math.min(2.2, Math.max(0.85, rect.width / 1024));
            var centerX = Math.round(rect.left + rect.width / 2);
            var topPx = Math.round(rect.top + 52 * scale);
            el.style.setProperty('--panel-feedback-left', centerX + 'px');
            el.style.setProperty('--panel-feedback-top', topPx + 'px');
            el.style.setProperty('--panel-feedback-scale', scale.toFixed(4));
        } else {
            el.style.removeProperty('--panel-feedback-left');
            el.style.removeProperty('--panel-feedback-top');
            el.style.removeProperty('--panel-feedback-scale');
        }
    }

    function clearTimers() {
        if (_hideTimer !== null) {
            clearTimeout(_hideTimer);
            _hideTimer = null;
        }
        if (_pulseTimer !== null) {
            clearTimeout(_pulseTimer);
            _pulseTimer = null;
        }
    }

    function showPanelBanner(plainText, severity, durationMs) {
        var el = ensureBanner();
        if (!el || !_textEl) return false;
        clearTimers();
        _sequence++;
        var seq = _sequence;
        syncBannerGeometry(el);
        el.setAttribute('data-severity', severity);
        el.setAttribute('role', severity === 'error' || severity === 'warning' ? 'alert' : 'status');
        el.setAttribute('aria-live', severity === 'error' || severity === 'warning' ? 'assertive' : 'polite');
        if (_iconEl) _iconEl.textContent = SEVERITY_ICONS[severity] || SEVERITY_ICONS.info;
        _textEl.textContent = plainText;
        el.hidden = false;
        el.classList.remove('is-pulsing');
        el.classList.add('is-visible');
        if (severity === 'error' || severity === 'warning') {
            // 强制重排以让连续同类拒绝仍能触发脉冲提示（reduced-motion 由 motion.css 静态收敛）。
            try { void el.offsetWidth; } catch (_) {}
            el.classList.add('is-pulsing');
            _pulseTimer = setTimeout(function() {
                _pulseTimer = null;
                if (_bannerEl && _sequence === seq) _bannerEl.classList.remove('is-pulsing');
            }, 300);
        }
        var ttl = typeof durationMs === 'number' && isFinite(durationMs) && durationMs > 0
            ? durationMs : (DEFAULT_DURATION_MS[severity] || 3200);
        _hideTimer = setTimeout(function() {
            _hideTimer = null;
            if (_sequence === seq) dismissPanel();
        }, ttl);
        return true;
    }

    function dismissPanel() {
        clearTimers();
        if (_bannerEl) {
            _bannerEl.classList.remove('is-visible', 'is-pulsing');
            _bannerEl.hidden = true;
        }
    }

    function playCueForSeverity(rawSeverity, silent) {
        if (silent === true) return;
        var cueName = rawSeverity === 'error' ? 'rejected'
            : rawSeverity === 'warning' ? 'illegal'
            : rawSeverity === 'success' ? 'success' : '';
        if (!cueName) return;
        var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
        if (A && typeof A.cue === 'function') {
            A.cue(cueName);
        }
    }

    function sendHostToast(rawHtml, rawSeverity) {
        if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.send === 'function') {
            Bridge.send({
                type: 'panel-toast',
                html: rawHtml == null ? '' : String(rawHtml),
                severity: rawSeverity || null
            });
            return true;
        }
        return false;
    }

    function add(rawHtml, severity, opts) {
        opts = opts && typeof opts === 'object' ? opts : null;
        var visualSeverity = normalizeSeverity(severity);
        var plainText = toPlainText(rawHtml);
        playCueForSeverity(severity, !!(opts && opts.silent === true));

        var persistAfterClose = !!(opts && opts.persistAfterClose === true);
        var panelOpen = isPanelVisible();
        var shownInPanel = false;
        if (panelOpen && plainText && !persistAfterClose) {
            shownInPanel = showPanelBanner(plainText, visualSeverity, opts && opts.durationMs);
        }
        var sentToHost = false;
        if (!shownInPanel || persistAfterClose) {
            sentToHost = sendHostToast(rawHtml, severity);
        }
        _last = {
            text: plainText,
            severity: visualSeverity,
            rawSeverity: severity || null,
            shownInPanel: shownInPanel,
            sentToHost: sentToHost,
            persistAfterClose: persistAfterClose,
            sequence: _sequence
        };
    }

    function debugState() {
        return {
            visible: !!(_bannerEl && !_bannerEl.hidden && _bannerEl.classList.contains('is-visible')),
            text: _textEl ? _textEl.textContent : '',
            severity: _bannerEl ? (_bannerEl.getAttribute('data-severity') || '') : '',
            sequence: _sequence,
            last: _last
        };
    }

    var api = {
        add: add,
        dismissPanel: dismissPanel,
        debugState: debugState,
        _toPlainText: toPlainText
    };
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    return api;
})();
