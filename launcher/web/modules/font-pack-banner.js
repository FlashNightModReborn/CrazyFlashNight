/**
 * FontPackBanner — 情报面板首次访问时的字体包安装条幅。
 *
 * 触发时机：IntelligencePanel.onOpen 完成后调用 FontPackBanner.checkAndShow(rootEl)。
 * 行为：
 *   1. Bridge.task('font_pack', {op:'status'}) 拉取 manifest 状态
 *   2. 任意 group 缺文件 → 渲染条幅到 rootEl 顶部，提示"建议安装基础字体包"
 *      - 立即下载 → Bridge.task('font_pack', {op:'download_group', group:'expressive'})
 *      - 暂不 → 设 localStorage 标记 6h 内不再提示
 *   3. 全部已装 → 不渲染
 *
 * 不强依赖 Bridge.task 存在（chrome.webview 缺失时静默 noop）。
 */
var FontPackBanner = (function() {
    'use strict';

    var SUPPRESS_KEY = 'cfn_font_pack_banner_suppressed_until';
    var SUPPRESS_HOURS = 6;
    var _activeBanner = null;

    function isSuppressed() {
        try {
            var until = parseInt(window.localStorage.getItem(SUPPRESS_KEY) || '0', 10);
            return until && Date.now() < until;
        } catch (e) { return false; }
    }

    function suppress() {
        try {
            window.localStorage.setItem(SUPPRESS_KEY,
                String(Date.now() + SUPPRESS_HOURS * 3600 * 1000));
        } catch (e) {}
    }

    function clearSuppression() {
        try { window.localStorage.removeItem(SUPPRESS_KEY); } catch (e) {}
    }

    function formatBytes(b) {
        if (!b || b <= 0) return '';
        if (b < 1024) return b + ' B';
        if (b < 1024 * 1024) return Math.round(b / 1024) + ' KB';
        return (b / (1024 * 1024)).toFixed(1) + ' MB';
    }

    function findHostEl(rootEl) {
        if (!rootEl) return null;
        return rootEl.querySelector('.intel-status') || rootEl;
    }

    function removeBanner() {
        if (_activeBanner && _activeBanner.parentNode) {
            _activeBanner.parentNode.removeChild(_activeBanner);
        }
        _activeBanner = null;
    }

    function buildBanner(missingGroups) {
        var wrap = document.createElement('div');
        wrap.className = 'intel-fontpack-banner';

        var msg = document.createElement('div');
        msg.className = 'intel-fontpack-msg';
        var bytes = 0;
        var labels = [];
        for (var i = 0; i < missingGroups.length; i++) {
            bytes += missingGroups[i].totalBytes || 0;
            labels.push(missingGroups[i].label || missingGroups[i].name);
        }
        msg.textContent = '建议安装字体包以获得最佳阅读体验：' + labels.join(' / ')
            + '（约 ' + formatBytes(bytes) + '）';

        var actions = document.createElement('div');
        actions.className = 'intel-fontpack-actions';

        var installBtn = document.createElement('button');
        installBtn.type = 'button';
        installBtn.className = 'intel-fontpack-install';
        installBtn.textContent = '立即安装';

        var laterBtn = document.createElement('button');
        laterBtn.type = 'button';
        laterBtn.className = 'intel-fontpack-later';
        laterBtn.textContent = '暂不';

        installBtn.addEventListener('click', function() {
            installBtn.disabled = true;
            laterBtn.disabled = true;
            installBtn.textContent = '下载中…';
            // 顺序串行下载所有缺失 group
            var idx = 0;
            function next() {
                if (idx >= missingGroups.length) {
                    installBtn.textContent = '完成（刷新生效）';
                    clearSuppression();
                    setTimeout(removeBanner, 2500);
                    return;
                }
                var g = missingGroups[idx++];
                Bridge.task('font_pack', { op: 'download_group', group: g.name }, function(resp) {
                    if (!resp || resp.success === false) {
                        installBtn.textContent = '失败，可重试';
                        installBtn.disabled = false;
                        laterBtn.disabled = false;
                        return;
                    }
                    next();
                });
            }
            next();
        });

        laterBtn.addEventListener('click', function() {
            suppress();
            removeBanner();
        });

        actions.appendChild(installBtn);
        actions.appendChild(laterBtn);
        wrap.appendChild(msg);
        wrap.appendChild(actions);
        return wrap;
    }

    /**
     * 检查并按需展示条幅。rootEl = 情报面板根 DOM。
     * 多次调用幂等：已渲染则不重复；用户已 suppress 则跳过。
     */
    function checkAndShow(rootEl) {
        if (!rootEl) return;
        if (_activeBanner && _activeBanner.parentNode) return;
        if (isSuppressed()) return;
        if (!window.Bridge || typeof Bridge.task !== 'function') return;

        Bridge.task('font_pack', { op: 'status' }, function(resp) {
            if (!resp || resp.success === false || !resp.groups) return;
            var missing = [];
            for (var i = 0; i < resp.groups.length; i++) {
                var g = resp.groups[i];
                if (g && g.allInstalled === false) missing.push(g);
            }
            if (missing.length === 0) return;

            var host = findHostEl(rootEl);
            if (!host) return;
            removeBanner();
            _activeBanner = buildBanner(missing);
            host.parentNode.insertBefore(_activeBanner, host);
        });
    }

    function dispose() { removeBanner(); }

    return {
        checkAndShow: checkAndShow,
        dispose: dispose
    };
})();
