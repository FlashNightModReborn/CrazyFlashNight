/**
 * HelpPanel — 游戏帮助面板（Panel 系统）
 *
 * 从 help/*.md 加载 markdown 内容，用 marked.js 渲染。
 * 注册为 Panels.register('help', {...}) 走通用面板生命周期。
 */
var HelpPanel = (function() {
    'use strict';

    var TAB_FILES = {
        'controls':    'help/controls.md',
        'worldview':   'help/worldview.md',
        'easter-eggs': 'help/easter-eggs.md'
    };
    var TAB_LABELS = {
        'controls':    '基本操作',
        'worldview':   '世界观',
        'easter-eggs': '彩蛋内容'
    };
    TAB_LABELS.tutorials = '操作教程';
    var TAB_ORDER = ['tutorials', 'controls', 'worldview', 'easter-eggs'];

    var _el, _headerBadge, _titleEl, _modeBtn, _tabBar, _content, _skipBar, _disableButton, _skipNote;
    var _cache = {};
    var _currentTab = '';
    var _tutorials = null;
    var _guidance = null;
    var _mode = 'full';
    var _scaleHandle = null;
    var _instanceId = '', _disableCall = '', _preferenceTimer = null, _preferenceSeq = 0;
    var SKIP_NOTE = '关闭教程弹窗后，所有自动教程改为顶部通知提醒；仍可随时从帮助页查看。';

    function resetPreferenceRequest() {
        if (_preferenceTimer !== null) clearTimeout(_preferenceTimer);
        _preferenceTimer = null; _disableCall = ''; _instanceId = '';
    }

    function detachScale() {
        if (_scaleHandle) {
            _scaleHandle.detach();
            _scaleHandle = null;
        }
    }

    function attachScale() {
        detachScale();
        if (_el && typeof PanelScale !== 'undefined' && PanelScale && typeof PanelScale.attach === 'function') {
            _scaleHandle = PanelScale.attach(_el, 1024, 576);
        }
    }

    function findGuideTitle(guideId) {
        var list = window.GuidanceCatalog && window.GuidanceCatalog.guides;
        if (!list) return '操作教程';
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === guideId) return list[i].title;
        }
        return '操作教程';
    }

    Panels.register('help', {
        create: createDOM,
        onOpen: onOpen,
        onClose: function() {
            detachScale();
            disposeTutorials();
            resetPreferenceRequest();
            _currentTab = '';
            _guidance = null;
            _mode = 'full';
            if (_el) _el.setAttribute('data-help-mode', 'full');
            if (_skipBar) _skipBar.hidden = true;
        },
        onRebind: function(el, initData) { return onOpen(el, initData); },
        onRequestClose: function() { doClose(); }
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'help-panel panel-scale-shell';
        _el.setAttribute('data-help-mode', 'full');
        _el.innerHTML =
            '<div class="help-header">' +
                '<div class="help-header-brand">' +
                    '<span class="help-header-badge" hidden>新手引导</span>' +
                    '<span class="help-title">游戏帮助</span>' +
                '</div>' +
                '<div class="help-header-actions">' +
                    '<button class="help-mode-toggle" type="button" hidden>查看全部帮助</button>' +
                    '<button class="help-close-btn" type="button" aria-label="关闭帮助">×</button>' +
                '</div>' +
            '</div>' +
            '<div class="help-tabs" id="help-tab-bar" role="tablist" aria-label="帮助分类"></div>' +
            '<div class="help-content" id="help-content"></div>' +
            '<div class="guidance-skip-bar" hidden>' +
                '<span class="guidance-skip-note" role="status" aria-live="polite"></span>' +
                '<div class="guidance-skip-actions">' +
                    '<button class="guidance-disable-btn" type="button">关闭教程弹窗</button>' +
                    '<button class="guidance-skip-btn" type="button">跳过本次</button>' +
                '</div>' +
            '</div>';

        _headerBadge = _el.querySelector('.help-header-badge');
        _titleEl = _el.querySelector('.help-title');
        _modeBtn = _el.querySelector('.help-mode-toggle');
        _tabBar = _el.querySelector('#help-tab-bar');
        _content = _el.querySelector('#help-content');
        _skipBar = _el.querySelector('.guidance-skip-bar');
        _skipNote = _el.querySelector('.guidance-skip-note');
        _disableButton = _el.querySelector('.guidance-disable-btn');
        _el.querySelector('.help-close-btn').addEventListener('click', function() { doClose(); });
        _el.querySelector('.guidance-skip-btn').addEventListener('click', function() { doClose(); });
        _disableButton.addEventListener('click', disableAutomaticTutorials);
        _modeBtn.addEventListener('click', toggleHelpMode);

        // 构建 tab 按钮
        for (var i = 0; i < TAB_ORDER.length; i++) {
            var id = TAB_ORDER[i];
            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'help-tab-btn';
            btn.textContent = TAB_LABELS[id];
            btn.setAttribute('data-tab', id);
            btn.setAttribute('role', 'tab');
            btn.setAttribute('aria-selected', 'false');
            btn.addEventListener('click', onTabClick);
            _tabBar.appendChild(btn);
        }

        return _el;
    }

    function applyMode(mode) {
        var briefing = mode === 'briefing' && !!_guidance;
        _mode = briefing ? 'briefing' : 'full';
        _el.setAttribute('data-help-mode', _mode);
        _tabBar.hidden = briefing;
        _headerBadge.hidden = !briefing;
        _titleEl.textContent = briefing ? findGuideTitle(_guidance.guideId) : '游戏帮助';
        _modeBtn.hidden = !_guidance;
        _modeBtn.textContent = briefing ? '查看全部帮助' : '返回当前引导';
        if (_tutorials && typeof _tutorials.setBriefing === 'function') {
            _tutorials.setBriefing(briefing);
        }
    }

    function toggleHelpMode() {
        if (!_guidance) return;
        if (_mode === 'briefing') {
            applyMode('full');
        } else {
            if (_currentTab !== 'tutorials') {
                switchTab('tutorials');
            } else if (_tutorials && typeof _tutorials.selectGuide === 'function') {
                _tutorials.selectGuide(_guidance.guideId);
            }
            applyMode('briefing');
        }
    }

    function readGuidance(data) {
        if (!data || !Object.prototype.hasOwnProperty.call(data, 'guidance')) return null;
        var g = data.guidance, names = ['left','right','up','down','attack','jump','interact'];
        if (!g || typeof g !== 'object' || Object.keys(g).length !== 2 || typeof g.guideId !== 'string'
                || !g.keys || typeof g.keys !== 'object' || Object.keys(g.keys).length !== names.length
                || names.some(function(key) { return !Object.prototype.hasOwnProperty.call(g.keys,key) || typeof g.keys[key] !== 'string' || !g.keys[key].trim()
                    || g.keys[key].length > 24 || /[\x00-\x1f\x7f]/.test(g.keys[key]); })
                || !window.GuidanceCatalog.guides.some(function(guide) { return guide.id === g.guideId && guide.surface === 'help'; }))
            throw Error('Invalid guidance help display');
        return { guideId:g.guideId, keys:Object.assign({},g.keys) };
    }
    function onOpen(el, initData) {
        try { _guidance = readGuidance(initData); } catch (error) { return false; }
        resetPreferenceRequest();
        _instanceId = initData && typeof initData.panelInstanceId === 'string' ? initData.panelInstanceId : '';
        _disableButton.disabled = !_instanceId;
        _disableButton.textContent = '关闭教程弹窗'; _skipNote.textContent = SKIP_NOTE;
        _skipBar.hidden = !_guidance;
        _currentTab = '';
        applyMode(_guidance ? 'briefing' : 'full');
        switchTab('tutorials');
        attachScale();
        return true;
    }

    function disableAutomaticTutorials() {
        if (!_guidance || !_instanceId || _disableCall) return;
        _disableCall = 'help-pref-' + Date.now().toString(36) + '-' + (++_preferenceSeq);
        _disableButton.disabled = true; _disableButton.textContent = '保存中…';
        if (Bridge.send({type:'tutorial_preference', cmd:'disable_auto_open', version:1,
                callId:_disableCall, panelInstanceId:_instanceId}) === false) {
            _disableCall = ''; _disableButton.disabled = false; _disableButton.textContent = '关闭教程弹窗';
            _skipNote.textContent = '设置未发送，请重试；也可以先跳过本次。'; return;
        }
        _preferenceTimer = setTimeout(function() {
            _preferenceTimer = null;
            _disableButton.textContent = '等待确认';
            _skipNote.textContent = '设置结果尚未确认，可以先跳过本次；稍后可在设置中查看教程弹窗偏好。';
        }, 10000);
    }

    Bridge.on('tutorial_preference_result', function(result) {
        if (!_guidance || !_disableCall || !result || result.version !== 1
                || result.panelInstanceId !== _instanceId || result.callId !== _disableCall
                || typeof result.ok !== 'boolean' || typeof result.tutorialsAutoOpen !== 'boolean') return;
        if (_preferenceTimer !== null) clearTimeout(_preferenceTimer);
        _preferenceTimer = null; _disableCall = '';
        if (result.ok && result.tutorialsAutoOpen === false) { doClose(); return; }
        _disableButton.disabled = false; _disableButton.textContent = '关闭教程弹窗';
        _skipNote.textContent = '设置保存失败，教程弹窗设置未改变；可以重试或跳过本次。';
    });

    function onTabClick(e) {
        var tab = e.target.getAttribute('data-tab');
        if (tab) switchTab(tab);
    }

    function switchTab(tabId) {
        if (!TAB_FILES[tabId] && tabId !== 'tutorials') return;
        disposeTutorials();
        _currentTab = tabId;

        // 更新 tab 高亮
        var btns = _tabBar.querySelectorAll('.help-tab-btn');
        for (var i = 0; i < btns.length; i++) {
            var active = btns[i].getAttribute('data-tab') === tabId;
            btns[i].classList.toggle('active', active);
            btns[i].setAttribute('aria-selected', active ? 'true' : 'false');
        }

        _content.setAttribute('data-help-tab', tabId);

        if (tabId === 'tutorials') {
            _content.innerHTML = '';
            var mountOptions = _guidance
                ? { guideId: _guidance.guideId, keys: _guidance.keys, briefing: _mode === 'briefing' }
                : { briefing: false };
            _tutorials = GuidanceTutorials.mount(_content, mountOptions);
            _content.scrollTop = 0;
            return;
        }
        // 从缓存或网络加载
        if (_cache[tabId]) {
            _content.innerHTML = '<article class="help-markdown">' + _cache[tabId] + '</article>';
            _content.scrollTop = 0;
        } else {
            _content.innerHTML = '<article class="help-markdown"><p class="help-loading">加载中…</p></article>';
            fetchMd(TAB_FILES[tabId], function(html) {
                _cache[tabId] = html;
                if (_currentTab === tabId) {
                    _content.innerHTML = '<article class="help-markdown">' + html + '</article>';
                    _content.scrollTop = 0;
                }
            });
        }
    }

    function fetchMd(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200 || xhr.status === 0) {
                    var html = (typeof marked !== 'undefined' && marked.parse)
                        ? marked.parse(xhr.responseText)
                        : '<pre>' + xhr.responseText + '</pre>';
                    cb(html);
                } else {
                    cb('<p class="help-error">加载失败</p>');
                }
            }
        };
        xhr.send();
    }

    function doClose() {
        var instance = _instanceId;
        if (window.BootstrapAudio) window.BootstrapAudio.cue('back');  // 语义音效：关闭
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'help', panelInstanceId:instance});
    }

    function disposeTutorials() {
        if (_tutorials) _tutorials.destroy();
        _tutorials = null;
    }

    return {};
})();
