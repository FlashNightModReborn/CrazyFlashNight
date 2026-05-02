/**
 * IntelligencePanel — 情报详情 Web 测试面板。
 *
 * 第一阶段只读取 legacy txt 数据，由 C# IntelligenceTask 返回真实字典和分页文本。
 */
var IntelligencePanel = (function() {
    'use strict';

    var _el, _refs;
    var _catalog = [];
    var _catalogByName = {};
    var _bundleByName = {};
    var _snapshot = null;
    var _reqSeq = 0;
    var _pending = {};
    var _selectedPage = 0;
    var _showPlain = true;
    var _currentItemName = '资料';
    var _currentValue = 99;
    var _decryptLevel = 10;
    var _pcName = '测试玩家';
    var _debugMode = false;
    var _runtimeMode = false;
    var _drawerCollapsed = false;
    var _pagePopupOpen = false;
    var _tooltipCache = {};
    var _hoverTooltipName = '';
    var _resizeObserver = null;
    var _keyHandler = null;
    var _outsideClickHandler = null;

    var DESIGN_WIDTH = 1180;
    var DESIGN_HEIGHT = 790;

    Panels.register('intelligence', {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        onRequestClose: doClose
    });

    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'intelligence') return;
        var cb = _pending[data.callId];
        if (!cb) return;
        delete _pending[data.callId];
        cb(data);
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'intelligence-panel';
        _el.innerHTML =
            '<div class="intel-shell">' +
                '<header class="intel-header">' +
                    '<div class="intel-icon-wrap"><img class="intel-icon" alt=""><span class="intel-icon-placeholder">?</span></div>' +
                    '<div class="intel-heading">' +
                        '<div class="intel-name">未选择</div>' +
                        '<div class="intel-meta"></div>' +
                    '</div>' +
                    '<div class="intel-progress-box">' +
                        '<div class="intel-progress-label">收集进度</div>' +
                        '<div class="intel-progress-value"></div>' +
                    '</div>' +
                    '<button class="intel-close-btn" type="button" title="关闭" aria-label="关闭"></button>' +
                '</header>' +
                '<main class="intel-reader">' +
                    '<div class="intel-status"></div>' +
                    '<article class="intel-content"></article>' +
                '</main>' +
                '<aside class="intel-catalog-panel" aria-label="情报目录">' +
                    '<button class="intel-catalog-toggle" type="button" title="收纳情报栏" aria-label="收纳情报栏"><span class="intel-catalog-toggle-mark"></span></button>' +
                    '<div class="intel-catalog-body">' +
                        '<div class="intel-catalog-head">' +
                            '<div class="intel-catalog-title">情报物品</div>' +
                            '<div class="intel-catalog-count"></div>' +
                        '</div>' +
                        '<div class="intel-catalog-list"></div>' +
                    '</div>' +
                '</aside>' +
                '<footer class="intel-footer">' +
                    '<button class="intel-prev-btn" type="button" title="上一页" aria-label="上一页"><span class="intel-arrow-left"></span></button>' +
                    '<button class="intel-next-btn" type="button" title="下一页" aria-label="下一页"><span class="intel-arrow-right"></span></button>' +
                    '<div class="intel-page-jumper">' +
                        '<button class="intel-page-indicator" type="button" title="点击展开页码列表" aria-haspopup="listbox" aria-expanded="false">' +
                            '<span class="intel-page-current">1</span>' +
                            '<span class="intel-page-sep">/</span>' +
                            '<span class="intel-page-total">0</span>' +
                            '<span class="intel-page-unit">页</span>' +
                            '<span class="intel-page-chevron" aria-hidden="true"></span>' +
                        '</button>' +
                        '<div class="intel-page-strip" hidden role="listbox" aria-label="页码列表">' +
                            '<div class="intel-page-list"></div>' +
                        '</div>' +
                    '</div>' +
                    '<button class="intel-toggle-btn" type="button">密文视图</button>' +
                '</footer>' +
                // ── DEV-ONLY 浮窗：absolute 定位，作为 .intel-shell 的子节点跟随 shell 的
                //    transform:scale，这样所有视口下相对 catalog/footer 的位置都稳定。
                //    脱离 grid 流，dev/prod 模式下 reader/header/footer 几何完全一致。
                //    正式版只需在 createDOM 阶段不挂载该 aside（或 _debugMode=false 时）即可，
                //    无需移除任何 CSS 规则、无需重排 .intel-shell 的 grid template。
                '<aside class="intel-devbar" hidden role="complementary" aria-label="开发参数">' +
                    '<div class="intel-dev-label">DEV · 测试参数</div>' +
                    '<div class="intel-field-row">' +
                        '<label class="intel-field">收集值<input class="intel-value-input" type="number" min="0"></label>' +
                        '<label class="intel-field">解密等级<input class="intel-decrypt-input" type="number" min="0"></label>' +
                    '</div>' +
                    '<button class="intel-refresh-btn" type="button">刷新</button>' +
                '</aside>' +
            '</div>';

        _refs = {
            devbar: _el.querySelector('.intel-devbar'),
            valueInput: _el.querySelector('.intel-value-input'),
            decryptInput: _el.querySelector('.intel-decrypt-input'),
            refreshBtn: _el.querySelector('.intel-refresh-btn'),
            pageList: _el.querySelector('.intel-page-list'),
            pageStrip: _el.querySelector('.intel-page-strip'),
            pageCurrent: _el.querySelector('.intel-page-current'),
            pageTotal: _el.querySelector('.intel-page-total'),
            icon: _el.querySelector('.intel-icon'),
            iconPlaceholder: _el.querySelector('.intel-icon-placeholder'),
            name: _el.querySelector('.intel-name'),
            meta: _el.querySelector('.intel-meta'),
            progress: _el.querySelector('.intel-progress-value'),
            status: _el.querySelector('.intel-status'),
            content: _el.querySelector('.intel-content'),
            pageIndicator: _el.querySelector('.intel-page-indicator'),
            toggleBtn: _el.querySelector('.intel-toggle-btn'),
            prevBtn: _el.querySelector('.intel-prev-btn'),
            nextBtn: _el.querySelector('.intel-next-btn'),
            closeBtn: _el.querySelector('.intel-close-btn'),
            catalogPanel: _el.querySelector('.intel-catalog-panel'),
            catalogToggle: _el.querySelector('.intel-catalog-toggle'),
            catalogList: _el.querySelector('.intel-catalog-list'),
            catalogCount: _el.querySelector('.intel-catalog-count')
        };

        _refs.icon.addEventListener('error', function() {
            _refs.icon.removeAttribute('src');
            _refs.icon.style.display = 'none';
            _refs.iconPlaceholder.style.display = '';
        });
        _refs.valueInput.addEventListener('change', readInputsAndRefresh);
        _refs.decryptInput.addEventListener('change', readInputsAndRefresh);
        _refs.refreshBtn.addEventListener('click', readInputsAndRefresh);
        _refs.prevBtn.addEventListener('click', function() { movePage(-1); });
        _refs.nextBtn.addEventListener('click', function() { movePage(1); });
        _refs.toggleBtn.addEventListener('click', function() {
            _showPlain = !_showPlain;
            renderPage();
        });
        _refs.closeBtn.addEventListener('click', doClose);
        _refs.catalogToggle.addEventListener('click', toggleCatalogDrawer);

        // 显式 click toggle —— 不挂 hover，避免「只想点 prev/next」的玩家被误触发。
        // 不依赖 input 输入路径（WebView2 + ghost-input 架构下 input typing 不可靠）。
        _refs.pageIndicator.addEventListener('click', function(e) {
            e.stopPropagation();
            togglePageStrip();
        });
        _refs.pageStrip.addEventListener('click', function(e) { e.stopPropagation(); });

        return _el;
    }

    function onOpen(el, initData) {
        _snapshot = null;
        _bundleByName = {};
        _selectedPage = 0;
        _showPlain = true;

        initData = initData || {};
        _currentItemName = initData.itemName || '资料';
        _currentValue = Number(initData.value);
        if (isNaN(_currentValue)) _currentValue = 99;
        _decryptLevel = Number(initData.decryptLevel);
        if (isNaN(_decryptLevel)) _decryptLevel = 10;
        _pcName = initData.pcName || '测试玩家';
        _debugMode = initData.debug === true || initData.mode === 'dev';
        _runtimeMode = initData.mode === 'prod' || (initData.source === 'runtime' && !_debugMode);
        _tooltipCache = {};
        _hoverTooltipName = '';
        if (_debugMode) _el.classList.add('is-debug');
        else _el.classList.remove('is-debug');
        _refs.devbar.hidden = !_debugMode;

        _refs.valueInput.value = String(_currentValue);
        _refs.decryptInput.value = String(_decryptLevel);
        showLoading('正在读取情报目录…');

        if (typeof Icons !== 'undefined' && Icons && Icons.load) {
            Icons.load(function() { renderIcon(); renderCatalogPanel(); });
        }

        if (_runtimeMode) {
            requestState(function() {
                populateCatalog(true);
                requestSnapshot();
            });
        } else {
            requestBundle(function() {
                populateCatalog(false);
                applyCurrentItemFromBundle();
            });
        }
        bindScaleWatcher();
        bindKeyboardAndOutsideClick();
        scheduleScaleUpdate();
    }

    function onClose() {
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip) PanelTooltip.hide();
        unbindScaleWatcher();
        unbindKeyboardAndOutsideClick();
        _pagePopupOpen = false;
        _pending = {};
        _hoverTooltipName = '';
    }

    function readInputsAndRefresh() {
        if (_runtimeMode) {
            requestState(function() {
                populateCatalog(true);
                requestSnapshot();
            });
            return;
        }
        _currentValue = Number(_refs.valueInput.value);
        if (isNaN(_currentValue)) _currentValue = 0;
        _decryptLevel = Number(_refs.decryptInput.value);
        if (isNaN(_decryptLevel)) _decryptLevel = 0;
        _selectedPage = 0;
        _showPlain = true;
        if (_catalog.length) {
            applyCurrentItemFromBundle();
        } else {
            requestBundle(function() {
                populateCatalog(false);
                applyCurrentItemFromBundle();
            });
        }
    }

    function requestBundle(done) {
        sendRequest('bundle', {
            value: _currentValue,
            decryptLevel: _decryptLevel,
            pcName: _pcName
        }, function(resp) {
            if (!resp.success) {
                showError('全量情报加载失败：' + (resp.error || 'unknown'));
                return;
            }
            ingestBundle(resp.items || []);
            if (done) done(resp);
        });
    }

    function requestState(done) {
        showLoading('正在同步情报状态…');
        sendRequest('state', {}, function(resp) {
            if (!resp.success) {
                showError('运行态情报状态加载失败：' + (resp.error || 'unknown'));
                return;
            }
            _catalog = resp.items || [];
            _catalogByName = {};
            _bundleByName = {};
            _decryptLevel = Number(resp.decryptLevel);
            if (isNaN(_decryptLevel)) _decryptLevel = 0;
            _pcName = resp.pcName || '';
            _refs.decryptInput.value = String(_decryptLevel);
            for (var i = 0; i < _catalog.length; i++) {
                _catalogByName[_catalog[i].name] = _catalog[i];
            }
            if (done) done(resp);
        });
    }

    function requestCatalog(done) {
        sendRequest('catalog', {}, function(resp) {
            if (!resp.success) {
                showError('目录加载失败：' + (resp.error || 'unknown'));
                return;
            }
            _catalog = resp.items || [];
            _catalogByName = {};
            for (var i = 0; i < _catalog.length; i++) {
                _catalogByName[_catalog[i].name] = _catalog[i];
            }
            if (done) done(resp);
        });
    }

    function requestSnapshot() {
        showLoading('正在读取情报文本…');
        var payload = { itemName: _currentItemName };
        if (!_runtimeMode) {
            payload.value = _currentValue;
            payload.decryptLevel = _decryptLevel;
            payload.pcName = _pcName;
        }
        sendRequest('snapshot', payload, function(resp) {
            if (!resp.success) {
                showError('文本加载失败：' + (resp.error || 'unknown'));
                return;
            }
            _snapshot = resp;
            _currentValue = Number(resp.value);
            if (isNaN(_currentValue)) _currentValue = 0;
            _decryptLevel = Number(resp.decryptLevel);
            if (isNaN(_decryptLevel)) _decryptLevel = 0;
            _pcName = resp.pcName || _pcName || '';
            _refs.valueInput.value = String(_currentValue);
            _refs.decryptInput.value = String(_decryptLevel);
            if (_selectedPage >= getPages().length) _selectedPage = 0;
            renderSnapshot();
        });
    }

    function ingestBundle(items) {
        _catalog = items || [];
        _catalogByName = {};
        _bundleByName = {};
        for (var i = 0; i < _catalog.length; i++) {
            _catalogByName[_catalog[i].name] = _catalog[i];
            _bundleByName[_catalog[i].name] = _catalog[i];
        }
    }

    function sendRequest(cmd, payload, cb) {
        var callId = 'intel-' + (++_reqSeq);
        _pending[callId] = cb;
        var msg = payload || {};
        msg.type = 'panel';
        msg.panel = 'intelligence';
        msg.cmd = cmd;
        msg.callId = callId;
        Bridge.send(msg);
    }

    function populateCatalog(preferProgress) {
        var current = _catalogByName[_currentItemName];
        if (_catalog.length && (!current || (preferProgress && (Number(current.value) || 0) <= 0))) {
            _currentItemName = pickDefaultItemName(preferProgress);
            current = _catalogByName[_currentItemName];
        }
        if (current && current.value != null) {
            _currentValue = Number(current.value);
            if (isNaN(_currentValue)) _currentValue = 0;
            _refs.valueInput.value = String(_currentValue);
        }
        renderCatalogPanel();
    }

    function pickDefaultItemName(preferProgress) {
        if (preferProgress) {
            for (var i = 0; i < _catalog.length; i++) {
                if ((Number(_catalog[i].value) || 0) > 0) return _catalog[i].name;
            }
        }
        return _catalog.length ? _catalog[0].name : '资料';
    }

    function applyCurrentItemFromBundle() {
        var item = _bundleByName[_currentItemName];
        if (!item) {
            showError('未找到情报条目：' + _currentItemName);
            return;
        }

        var pages = [];
        var sourcePages = item.pages || [];
        for (var i = 0; i < sourcePages.length; i++) {
            var page = sourcePages[i] || {};
            pages.push({
                pageKey: page.pageKey,
                value: Number(page.value) || 0,
                encryptLevel: Number(page.encryptLevel) || 0,
                unlocked: (Number(page.value) || 0) <= _currentValue,
                text: page.text || ''
            });
        }

        _snapshot = {
            item: {
                name: item.name,
                iconName: item.iconName,
                index: item.index,
                maxValue: item.maxValue,
                pageCount: item.pageCount || sourcePages.length
            },
            name: item.name,
            maxValue: item.maxValue || 0,
            value: _currentValue,
            decryptLevel: _decryptLevel,
            pcName: _pcName,
            pages: pages,
            encryptRules: item.encryptRules || { replace: {}, cut: {} },
            textError: item.textError || ''
        };

        if (_selectedPage >= pages.length) _selectedPage = 0;
        renderSnapshot();
    }

    function renderSnapshot() {
        var item = _snapshot.item || {};
        var pages = getPages();
        var unlockedPages = countUnlockedPages(pages);
        var displayLabel = item.displayName || _snapshot.displayName ||
                           (_catalogByName[_currentItemName] && _catalogByName[_currentItemName].displayName) ||
                           item.name || _snapshot.name || '未命名情报';
        _refs.name.textContent = displayLabel;
        _refs.meta.textContent = '已发现 ' + unlockedPages + ' / ' + pages.length + ' 页信息';
        _refs.progress.textContent = (_snapshot.value || 0) + ' / ' + (_snapshot.maxValue || 0);
        renderIcon();
        renderCatalogPanel();
        renderPageList();
        renderPage();
        scheduleScaleUpdate();
    }

    function renderIcon() {
        if (!_refs || !_refs.icon) return;
        var url = resolveIconUrl(_bundleByName[_currentItemName] || _catalogByName[_currentItemName] || _currentItemName);
        if (url) {
            _refs.icon.src = url;
            _refs.icon.style.display = '';
            _refs.iconPlaceholder.style.display = 'none';
        } else {
            _refs.icon.removeAttribute('src');
            _refs.icon.style.display = 'none';
            _refs.iconPlaceholder.style.display = '';
        }
    }

    function resolveIconUrl(name) {
        if (typeof Icons === 'undefined' || !Icons || !Icons.resolve) return null;
        var candidates = [];
        if (name && typeof name === 'object') {
            candidates.push(name.iconName);
            candidates.push(name.icon);
            candidates.push(name.name);
        } else {
            candidates.push(name);
        }
        if ((name && name.name === '资料') || name === '资料') candidates.push('废城资料');

        var seen = {};
        for (var i = 0; i < candidates.length; i++) {
            var key = candidates[i];
            if (!key || seen[key]) continue;
            seen[key] = true;
            var url = Icons.resolve(key);
            if (url) return url;
        }
        return null;
    }

    function renderCatalogPanel() {
        if (!_refs || !_refs.catalogList) return;
        _refs.catalogList.innerHTML = '';
        _refs.catalogCount.textContent = _catalog.length + ' 件';
        for (var i = 0; i < _catalog.length; i++) {
            _refs.catalogList.appendChild(createCatalogItem(_catalog[i]));
        }
    }

    function createCatalogItem(item) {
        var name = item.name || '';
        var label = item.displayName || name;
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'intel-catalog-item' + (name === _currentItemName ? ' active' : '') + (item.textError ? ' has-error' : '');
        btn.setAttribute('data-name', name);
        // 使用 aria-label 保留可访问性；不用 title 是为了避免 WebView2/Chromium 在 hover 长停后弹出原生 tooltip 与 PanelTooltip 重叠
        btn.setAttribute('aria-label', label + (label !== name ? ' (' + name + ')' : '') + (item.textError ? ' / ' + item.textError : ''));

        var iconWrap = document.createElement('span');
        iconWrap.className = 'intel-catalog-icon-wrap';
        var iconUrl = resolveIconUrl(item);
        if (iconUrl) {
            var img = document.createElement('img');
            img.className = 'intel-catalog-icon';
            img.alt = '';
            img.src = iconUrl;
            img.onerror = function() { this.style.display = 'none'; };
            iconWrap.appendChild(img);
        } else {
            var placeholder = document.createElement('span');
            placeholder.className = 'intel-catalog-icon-placeholder';
            placeholder.textContent = '?';
            iconWrap.appendChild(placeholder);
        }

        var text = document.createElement('span');
        text.className = 'intel-catalog-text';
        var labelEl = document.createElement('span');
        labelEl.className = 'intel-catalog-name';
        labelEl.textContent = label;
        var meta = document.createElement('span');
        meta.className = 'intel-catalog-meta';
        meta.textContent = countUnlockedPagesForItem(item) + ' / ' + getPageCountForItem(item) + ' 页';
        text.appendChild(labelEl);
        text.appendChild(meta);

        btn.appendChild(iconWrap);
        btn.appendChild(text);
        btn.addEventListener('click', function(e) {
            var nextName = e.currentTarget.getAttribute('data-name');
            if (!nextName || nextName === _currentItemName) return;
            _currentItemName = nextName;
            var nextItem = _catalogByName[_currentItemName];
            if (nextItem && nextItem.value != null) {
                _currentValue = Number(nextItem.value);
                if (isNaN(_currentValue)) _currentValue = 0;
                _refs.valueInput.value = String(_currentValue);
            }
            _selectedPage = 0;
            _showPlain = true;
            if (!_runtimeMode && _bundleByName[_currentItemName]) applyCurrentItemFromBundle();
            else requestSnapshot();
        });
        btn.addEventListener('mouseenter', function(e) { showCatalogTooltip(name, e); });
        btn.addEventListener('mousemove', function(e) {
            if (typeof PanelTooltip !== 'undefined' && PanelTooltip) PanelTooltip.followMouse(e);
        });
        btn.addEventListener('mouseleave', function() {
            _hoverTooltipName = '';
            if (typeof PanelTooltip !== 'undefined' && PanelTooltip) PanelTooltip.hide();
        });
        return btn;
    }

    function countUnlockedPagesForItem(item) {
        if (item && item.unlockedCount != null) return Number(item.unlockedCount) || 0;
        var pages = item && item.pages ? item.pages : [];
        var count = 0;
        for (var i = 0; i < pages.length; i++) {
            if ((Number(pages[i].value) || 0) <= _currentValue) count++;
        }
        return count;
    }

    function getPageCountForItem(item) {
        if (item && item.pageCount != null) return Number(item.pageCount) || 0;
        return item && item.pages ? item.pages.length : 0;
    }

    function showCatalogTooltip(name, e) {
        if (typeof PanelTooltip === 'undefined' || !PanelTooltip) return;
        var item = _catalogByName[name] || _bundleByName[name] || { name: name };
        _hoverTooltipName = name;
        PanelTooltip.showAtMouse(buildBasicTooltip(item, false), e);

        var cached = _tooltipCache[name];
        if (cached && cached.success) {
            PanelTooltip.updateContent(buildRichTooltip(item, cached));
            return;
        }
        if (cached && cached.loading) return;
        if (cached && cached.failed && (Date.now() - (cached.failedAt || 0)) < 8000) {
            PanelTooltip.updateContent(buildBasicTooltip(item, true));
            return;
        }

        _tooltipCache[name] = { loading: true };
        sendRequest('tooltip', { itemName: name }, function(resp) {
            if (!resp.success) {
                _tooltipCache[name] = { failed: true, failedAt: Date.now(), error: resp.error || 'unknown' };
                if (_hoverTooltipName === name && PanelTooltip.isVisible()) {
                    PanelTooltip.updateContent(buildBasicTooltip(item, true));
                }
                return;
            }
            _tooltipCache[name] = resp;
            if (_hoverTooltipName === name && PanelTooltip.isVisible()) {
                PanelTooltip.updateContent(buildRichTooltip(item, resp));
            }
        });
    }

    function buildBasicTooltip(item, failed) {
        var label = item.displayName || item.name || '';
        var iconUrl = resolveIconUrl(item);
        var iconHtml = iconUrl
            ? '<div class="kshop-tt-icon"><img src="' + escAttr(iconUrl) + '" alt=""></div>'
            : '<div class="kshop-tt-icon"><span class="intel-catalog-icon-placeholder">?</span></div>';
        return '<div class="kshop-tt-rich intel-tt-basic">' +
            iconHtml +
            '<div class="kshop-tt-desc">' +
                '<div class="kshop-tt-header"><b>' + escHtml(label) + '</b></div>' +
                '<div class="kshop-tt-divider"></div>' +
                '<div class="kshop-tt-dim">收集品 · 情报</div>' +
                '<div class="kshop-tt-dim">已发现 ' + countUnlockedPagesForItem(item) + ' / ' + getPageCountForItem(item) + ' 页</div>' +
                (failed ? '<div class="kshop-tt-locked">注释暂不可用</div>' : '<div class="kshop-tt-loading">加载注释…</div>') +
            '</div>' +
        '</div>';
    }

    // 与商城 buildRichHtml 对齐：introHTML 已含 displayname 标题，不再重复 header；
    // 仅渲染 icon + intro + desc 三栏，避免和 TooltipComposer 输出的标题撞行。
    function buildRichTooltip(item, resp) {
        var iconUrl = resolveIconUrl(item);
        var iconHtml = iconUrl
            ? '<div class="kshop-tt-icon"><img src="' + escAttr(iconUrl) + '" alt=""></div>'
            : '<div class="kshop-tt-icon"><span class="intel-catalog-icon-placeholder">?</span></div>';
        var intro = PanelTooltip.convertAS2Html(resp.introHTML || '');
        var desc = PanelTooltip.convertAS2Html(resp.descHTML || '');
        var meta = '<div class="kshop-tt-dim">已发现 ' + countUnlockedPagesForItem(item) + ' / ' + getPageCountForItem(item) + ' 页</div>';
        return '<div class="kshop-tt-rich intel-tt-rich">' +
            iconHtml +
            (intro ? '<div class="kshop-tt-intro">' + intro + meta + '</div>' : '<div class="kshop-tt-intro">' + meta + '</div>') +
            (desc ? '<div class="kshop-tt-desc">' + desc + '</div>' : '') +
        '</div>';
    }

    function escHtml(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function escAttr(s) {
        return escHtml(s);
    }

    function toggleCatalogDrawer() {
        _drawerCollapsed = !_drawerCollapsed;
        if (_drawerCollapsed) {
            _el.classList.add('is-catalog-collapsed');
            _refs.catalogToggle.title = '展开情报栏';
            _refs.catalogToggle.setAttribute('aria-label', '展开情报栏');
        } else {
            _el.classList.remove('is-catalog-collapsed');
            _refs.catalogToggle.title = '收纳情报栏';
            _refs.catalogToggle.setAttribute('aria-label', '收纳情报栏');
        }
        scheduleScaleUpdate();
    }

    function renderPageList() {
        var pages = getPages();
        _refs.pageList.innerHTML = '';
        for (var i = 0; i < pages.length; i++) {
            var page = pages[i];
            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'intel-page-btn' + (i === _selectedPage ? ' active' : '') + (!page.unlocked ? ' locked' : '');
            btn.setAttribute('data-index', String(i));
            btn.textContent = String(i + 1);
            btn.title = 'PageKey ' + page.pageKey + (page.encryptLevel > 0 ? ' / E' + page.encryptLevel : '');
            btn.addEventListener('click', function(e) {
                _selectedPage = Number(e.currentTarget.getAttribute('data-index')) || 0;
                _showPlain = true;
                closePageStrip();
                renderPageList();
                renderPage();
            });
            _refs.pageList.appendChild(btn);
        }
    }

    function renderPage() {
        var pages = getPages();
        var page = pages[_selectedPage];
        _refs.content.innerHTML = '';

        if (!page) {
            _refs.status.textContent = '没有可显示的情报页';
            _refs.pageCurrent.textContent = '0';
            _refs.pageTotal.textContent = '0';
            _refs.pageIndicator.disabled = true;
            _refs.toggleBtn.disabled = true;
            _refs.prevBtn.disabled = true;
            _refs.nextBtn.disabled = true;
            return;
        }

        _refs.pageIndicator.disabled = pages.length <= 1;
        _refs.pageCurrent.textContent = String(_selectedPage + 1);
        _refs.pageTotal.textContent = String(pages.length);
        _refs.prevBtn.disabled = _selectedPage <= 0;
        _refs.nextBtn.disabled = _selectedPage >= pages.length - 1;

        if (_snapshot.textError) {
            _refs.status.textContent = '文本加载失败：' + _snapshot.textError;
            _refs.toggleBtn.disabled = true;
            _refs.toggleBtn.textContent = '不可用';
            _refs.content.appendChild(emptyBlock('该情报文本暂不可用。'));
            return;
        }

        if (!page.unlocked) {
            _refs.status.textContent = '尚未发现 · 需要收集进度达到 ' + page.value;
            _refs.toggleBtn.disabled = true;
            _refs.toggleBtn.textContent = '未解锁';
            _refs.content.appendChild(emptyBlock('情报页仍处于锁定状态。'));
            return;
        }

        var canDecrypt = page.encryptLevel > 0 && (_snapshot.decryptLevel || 0) >= page.encryptLevel;
        var mustEncrypt = page.encryptLevel > (_snapshot.decryptLevel || 0);
        var renderText = page.text || '';
        if (mustEncrypt || (page.encryptLevel > 0 && !_showPlain)) {
            renderText = encryptText(renderText, _snapshot.encryptRules || {});
        }

        if (mustEncrypt) {
            _refs.status.textContent = '信息未完全解明 · 需要解密等级 ' + page.encryptLevel;
            _refs.toggleBtn.disabled = true;
            _refs.toggleBtn.textContent = '密文视图';
        } else if (canDecrypt) {
            _refs.status.textContent = _showPlain ? '信息已解明' : '当前显示未解明文本';
            _refs.toggleBtn.disabled = false;
            _refs.toggleBtn.textContent = _showPlain ? '密文视图' : '明文视图';
        } else {
            _refs.status.textContent = '';
            _refs.toggleBtn.disabled = true;
            _refs.toggleBtn.textContent = '明文视图';
        }

        appendLegacyHtml(_refs.content, renderText, _snapshot.pcName || _pcName);
        _refs.content.scrollTop = 0;
    }

    function movePage(delta) {
        var pages = getPages();
        var next = _selectedPage + delta;
        if (next < 0 || next >= pages.length) return;
        _selectedPage = next;
        _showPlain = true;
        closePageStrip();
        renderPageList();
        renderPage();
    }

    function jumpPage(targetIndex) {
        var pages = getPages();
        if (!pages.length) return;
        var clamped = Math.max(0, Math.min(pages.length - 1, targetIndex));
        if (clamped === _selectedPage) return;
        _selectedPage = clamped;
        _showPlain = true;
        closePageStrip();
        renderPageList();
        renderPage();
    }

    function getPages() {
        return (_snapshot && _snapshot.pages) ? _snapshot.pages : [];
    }

    function countUnlockedPages(pages) {
        var count = 0;
        for (var i = 0; i < pages.length; i++) {
            if (pages[i] && pages[i].unlocked) count++;
        }
        return count;
    }

    function showLoading(text) {
        _refs.status.textContent = text;
        _refs.content.innerHTML = '';
        _refs.content.appendChild(emptyBlock(text));
        scheduleScaleUpdate();
    }

    function showError(text) {
        _refs.status.textContent = text;
        _refs.content.innerHTML = '';
        var block = emptyBlock(text);
        block.className += ' error';
        _refs.content.appendChild(block);
        scheduleScaleUpdate();
    }

    function emptyBlock(text) {
        var div = document.createElement('div');
        div.className = 'intel-empty';
        div.textContent = text;
        return div;
    }

    function encryptText(raw, rules) {
        var text = raw || '';
        var replace = rules.replace || {};
        var cut = rules.cut || {};
        var keys = Object.keys(replace).sort(lengthDesc);
        for (var i = 0; i < keys.length; i++) {
            text = text.split(keys[i]).join(replace[keys[i]] == null ? '' : String(replace[keys[i]]));
        }
        keys = Object.keys(cut).sort(lengthDesc);
        for (i = 0; i < keys.length; i++) {
            var parts = text.split(keys[i]);
            if (parts.length > 1) text = parts[0] + (cut[keys[i]] == null ? '' : String(cut[keys[i]]));
        }
        return text;
    }

    function lengthDesc(a, b) {
        return b.length - a.length;
    }

    function appendLegacyHtml(target, raw, pcName) {
        raw = (raw || '').split('${PC_NAME}').join(pcName || '');
        raw = raw.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n/g, '<br>');
        var doc = new DOMParser().parseFromString('<div>' + raw + '</div>', 'text/html');
        var root = doc.body.firstChild;
        var fragment = document.createDocumentFragment();
        copySafeChildren(root, fragment);
        target.appendChild(fragment);
    }

    function copySafeChildren(source, target) {
        if (!source) return;
        for (var i = 0; i < source.childNodes.length; i++) {
            var node = source.childNodes[i];
            if (node.nodeType === 3) {
                target.appendChild(document.createTextNode(node.nodeValue));
            } else if (node.nodeType === 1) {
                appendSafeElement(node, target);
            }
        }
    }

    function appendSafeElement(node, target) {
        var tag = node.tagName.toLowerCase();
        var el = null;
        if (tag === 'b' || tag === 'strong') el = document.createElement('strong');
        else if (tag === 'u') el = document.createElement('u');
        else if (tag === 'i') el = document.createElement('em');
        else if (tag === 'br') el = document.createElement('br');
        else if (tag === 'font') {
            el = document.createElement('span');
            var color = node.getAttribute('color') || '';
            if (/^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$/.test(color)) el.style.color = color;
        }

        if (!el) {
            copySafeChildren(node, target);
            return;
        }
        if (tag !== 'br') copySafeChildren(node, el);
        target.appendChild(el);
    }

    function doClose() {
        Panels.close();
        Bridge.send({ type: 'panel', cmd: 'close', panel: 'intelligence' });
    }

    function togglePageStrip() {
        if (_pagePopupOpen) closePageStrip();
        else openPageStrip();
    }

    function openPageStrip() {
        if (!getPages().length) return;
        if (_pagePopupOpen) return;
        _pagePopupOpen = true;
        _refs.pageStrip.hidden = false;
        _refs.pageIndicator.setAttribute('aria-expanded', 'true');
        // 把三角顶点对准 indicator 几何中心。strip 锚到 jumper 左边沿，所以
        // 三角的 X 坐标就是 indicator 中心相对 jumper 左边沿的偏移。
        var indicatorRect = _refs.pageIndicator.getBoundingClientRect();
        var jumperRect = _refs.pageIndicator.parentElement.getBoundingClientRect();
        var triangleX = indicatorRect.left + indicatorRect.width / 2 - jumperRect.left;
        _refs.pageStrip.style.setProperty('--triangle-x', triangleX.toFixed(1) + 'px');
        // 自动把 active 页号横向滚到中央
        var active = _refs.pageList.querySelector('.intel-page-btn.active');
        if (active && active.scrollIntoView) {
            active.scrollIntoView({ block: 'nearest', inline: 'center' });
        }
    }

    function closePageStrip() {
        if (!_pagePopupOpen) return;
        _pagePopupOpen = false;
        _refs.pageStrip.hidden = true;
        _refs.pageIndicator.setAttribute('aria-expanded', 'false');
    }

    function bindKeyboardAndOutsideClick() {
        unbindKeyboardAndOutsideClick();
        _keyHandler = function(e) {
            if (!_el || !document.contains(_el)) return;
            var target = e.target;
            // 任何 input/textarea/contenteditable 内不拦截（虽然当前 panel 没有这类，
            // 但保留通用兜底以防未来加搜索框等）
            if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) return;
            var pages = getPages();
            if (e.key === 'ArrowLeft') { e.preventDefault(); movePage(-1); }
            else if (e.key === 'ArrowRight') { e.preventDefault(); movePage(1); }
            else if (e.key === 'Home' && pages.length) { e.preventDefault(); jumpPage(0); }
            else if (e.key === 'End' && pages.length) { e.preventDefault(); jumpPage(pages.length - 1); }
            else if (e.key === 'PageUp' && pages.length) { e.preventDefault(); jumpPage(_selectedPage - 5); }
            else if (e.key === 'PageDown' && pages.length) { e.preventDefault(); jumpPage(_selectedPage + 5); }
            else if (e.key === 'Escape') {
                if (_pagePopupOpen) { e.preventDefault(); closePageStrip(); }
            }
        };
        _outsideClickHandler = function(e) {
            if (!_pagePopupOpen) return;
            if (_refs.pageIndicator.contains(e.target) || _refs.pageStrip.contains(e.target)) return;
            closePageStrip();
        };
        document.addEventListener('keydown', _keyHandler);
        document.addEventListener('mousedown', _outsideClickHandler, true);
    }

    function unbindKeyboardAndOutsideClick() {
        if (_keyHandler) document.removeEventListener('keydown', _keyHandler);
        if (_outsideClickHandler) document.removeEventListener('mousedown', _outsideClickHandler, true);
        _keyHandler = null;
        _outsideClickHandler = null;
    }

    function bindScaleWatcher() {
        unbindScaleWatcher();
        window.addEventListener('resize', scheduleScaleUpdate);
        if (typeof ResizeObserver !== 'undefined' && _el) {
            _resizeObserver = new ResizeObserver(scheduleScaleUpdate);
            _resizeObserver.observe(_el);
            if (_el.parentElement) _resizeObserver.observe(_el.parentElement);
        }
    }

    function unbindScaleWatcher() {
        window.removeEventListener('resize', scheduleScaleUpdate);
        if (_resizeObserver) {
            _resizeObserver.disconnect();
            _resizeObserver = null;
        }
    }

    function scheduleScaleUpdate() {
        if (typeof requestAnimationFrame === 'function') {
            requestAnimationFrame(updateFitScale);
        } else {
            setTimeout(updateFitScale, 0);
        }
    }

    function updateFitScale() {
        if (!_el) return;
        fitPanelToParent();
        var width = _el.clientWidth || _el.offsetWidth || 0;
        var height = _el.clientHeight || _el.offsetHeight || 0;
        if (!width || !height) return;
        var scale = Math.min(width / DESIGN_WIDTH, height / DESIGN_HEIGHT);
        if (!isFinite(scale) || scale <= 0) scale = 1;
        _el.style.setProperty('--intel-scale', scale.toFixed(4));
    }

    function fitPanelToParent() {
        var parent = _el.parentElement;
        var parentWidth = parent ? parent.clientWidth : 0;
        var parentHeight = parent ? parent.clientHeight : 0;
        if (!parentWidth) parentWidth = window.innerWidth || document.documentElement.clientWidth || 0;
        if (!parentHeight) parentHeight = window.innerHeight || document.documentElement.clientHeight || 0;
        if (!parentWidth || !parentHeight) return;

        var aspect = DESIGN_WIDTH / DESIGN_HEIGHT;
        var panelWidth = parentWidth;
        var panelHeight = panelWidth / aspect;
        if (panelHeight > parentHeight) {
            panelHeight = parentHeight;
            panelWidth = panelHeight * aspect;
        }
        panelWidth = Math.max(1, Math.floor(panelWidth));
        panelHeight = Math.max(1, Math.floor(panelHeight));
        if (_el.style.width !== panelWidth + 'px') _el.style.width = panelWidth + 'px';
        if (_el.style.height !== panelHeight + 'px') _el.style.height = panelHeight + 'px';
    }

    return {
        _debugRequestSnapshot: requestSnapshot,
        _debugGetState: function() {
            return {
                itemName: _currentItemName,
                value: _currentValue,
                decryptLevel: _decryptLevel,
                pageIndex: _selectedPage,
                pageCount: getPages().length,
                debug: _debugMode,
                runtime: _runtimeMode,
                hasSnapshot: !!_snapshot,
                catalogCount: _catalog.length,
                catalogCollapsed: _drawerCollapsed,
                pagePopupOpen: _pagePopupOpen,
                devbarVisible: _refs && _refs.devbar ? !_refs.devbar.hidden : false,
                scale: _el ? Number(_el.style.getPropertyValue('--intel-scale')) || 1 : 1
            };
        },
        _debugSetPage: function(index) {
            var pages = getPages();
            _selectedPage = Math.max(0, Math.min(pages.length - 1, Number(index) || 0));
            renderPageList();
            renderPage();
        }
    };
})();
