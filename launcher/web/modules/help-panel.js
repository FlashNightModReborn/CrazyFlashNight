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
        'controls':    '\u57fa\u672c\u64cd\u4f5c',
        'worldview':   '\u4e16\u754c\u89c2',
        'easter-eggs': '\u5f69\u86cb\u5185\u5bb9'
    };
    var TAB_ORDER = ['controls', 'worldview', 'easter-eggs'];

    var _el, _tabBar, _content;
    var _cache = {};
    var _currentTab = '';

    Panels.register('help', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: function() { doClose(); }
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'help-panel';
        _el.innerHTML =
            '<div class="help-header">' +
                '<span class="help-title">\u6e38\u620f\u5e2e\u52a9</span>' +
                '<button class="help-close-btn">\u00d7</button>' +
            '</div>' +
            '<div class="help-tabs" id="help-tab-bar"></div>' +
            '<div class="help-content" id="help-content"></div>';

        _tabBar = _el.querySelector('#help-tab-bar');
        _content = _el.querySelector('#help-content');
        _el.querySelector('.help-close-btn').addEventListener('click', function() { doClose(); });

        // 构建 tab 按钮
        for (var i = 0; i < TAB_ORDER.length; i++) {
            var id = TAB_ORDER[i];
            var btn = document.createElement('button');
            btn.className = 'help-tab-btn';
            btn.textContent = TAB_LABELS[id];
            btn.setAttribute('data-tab', id);
            btn.addEventListener('click', onTabClick);
            _tabBar.appendChild(btn);
        }

        return _el;
    }

    function onOpen() {
        _currentTab = '';
        switchTab('controls');
    }

    function onTabClick(e) {
        var tab = e.target.getAttribute('data-tab');
        if (tab) switchTab(tab);
    }

    function switchTab(tabId) {
        if (!TAB_FILES[tabId]) return;
        _currentTab = tabId;

        // 更新 tab 高亮
        var btns = _tabBar.querySelectorAll('.help-tab-btn');
        for (var i = 0; i < btns.length; i++) {
            if (btns[i].getAttribute('data-tab') === tabId)
                btns[i].classList.add('active');
            else
                btns[i].classList.remove('active');
        }

        // 从缓存或网络加载
        if (_cache[tabId]) {
            _content.innerHTML = _cache[tabId];
            _content.scrollTop = 0;
        } else {
            _content.innerHTML = '<p class="help-loading">\u52a0\u8f7d\u4e2d\u2026</p>';
            fetchMd(TAB_FILES[tabId], function(html) {
                _cache[tabId] = html;
                if (_currentTab === tabId) {
                    _content.innerHTML = html;
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
                    cb('<p class="help-error">\u52a0\u8f7d\u5931\u8d25</p>');
                }
            }
        };
        xhr.send();
    }

    function doClose() {
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'help'});
    }

    return {};
})();
