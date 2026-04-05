/**
 * GameHelp — 游戏帮助弹窗
 * 从 launcher/web/help/*.md 加载 markdown，用 marked.js 渲染
 */
var GameHelp = (function() {
    'use strict';

    var modal, content, tabs, closeBtn;
    var cache = {}; // tab → html string
    var currentTab = '';

    var TAB_FILES = {
        'controls':    'help/controls.md',
        'worldview':   'help/worldview.md',
        'easter-eggs': 'help/easter-eggs.md'
    };

    function init() {
        modal = document.getElementById('game-help-modal');
        content = document.getElementById('game-help-content');
        closeBtn = document.getElementById('game-help-close');
        if (!modal) return;

        tabs = modal.querySelectorAll('.gh-tab');
        for (var i = 0; i < tabs.length; i++) {
            (function(tab) {
                tab.addEventListener('click', function() {
                    switchTab(tab.getAttribute('data-tab'));
                });
            })(tabs[i]);
        }

        if (closeBtn) {
            closeBtn.addEventListener('click', close);
        }
    }

    function open() {
        if (!modal) return;
        modal.classList.add('visible');
        // 默认显示第一个 tab
        if (!currentTab) switchTab('controls');
        // 延迟上报 hitRect，确保布局完成
        setTimeout(function() {
            if (typeof Notch !== 'undefined') Notch.reportRect();
        }, 50);
    }

    function close() {
        if (!modal) return;
        modal.classList.remove('visible');
        setTimeout(function() {
            if (typeof Notch !== 'undefined') Notch.reportRect();
        }, 50);
    }

    function toggle() {
        if (modal && modal.classList.contains('visible')) close();
        else open();
    }

    function switchTab(tabId) {
        if (!TAB_FILES[tabId]) return;
        currentTab = tabId;

        // 更新 tab 高亮
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].getAttribute('data-tab') === tabId)
                tabs[i].classList.add('active');
            else
                tabs[i].classList.remove('active');
        }

        // 从缓存或网络加载
        if (cache[tabId]) {
            content.innerHTML = cache[tabId];
            content.scrollTop = 0;
        } else {
            content.innerHTML = '<p style="color:rgba(255,255,255,0.4)">加载中…</p>';
            fetchMd(TAB_FILES[tabId], function(html) {
                cache[tabId] = html;
                if (currentTab === tabId) {
                    content.innerHTML = html;
                    content.scrollTop = 0;
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
                    cb('<p style="color:#ff6666">加载失败</p>');
                }
            }
        };
        xhr.send();
    }

    window.addEventListener('load', init);
    return { open: open, close: close, toggle: toggle };
})();
