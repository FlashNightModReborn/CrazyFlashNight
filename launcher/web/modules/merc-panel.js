(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 状态
    // ═══════════════════════════════════════════════════════════
    var _el;
    var _snapshot = null;
    var _hiredMercs = [];
    var _currentPage = 'list';
    var _hirePage = 1;
    var _hireTotalPages = 1;
    var _hireData = [];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _toastTimer = null;
    var _ttCache = {};            // (raw|level) → {descHTML, introHTML, displayname}
    var _ttHoverKey = null;       // current hover cache key

    var _pageList, _pageHire;
    var _goldEl, _kpointEl, _slotCountEl;

    // ═══════════════════════════════════════════════════════════
    // Panel 注册
    // ═══════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════
    // Bridge 通信
    // ═══════════════════════════════════════════════════════════
    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'merc_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = cb;
        var msg = { type: 'panel', panel: 'mercs', cmd: cmd, callId: callId };
        if (extra) {
            Object.keys(extra).forEach(function(k) { msg[k] = extra[k]; });
        }
        Bridge.send(msg);
    }

    Bridge.on('panel_resp', function(data) {
        if (data.panel !== 'mercs') return;
        var cb = _pendingReq[data.callId];
        if (cb) {
            delete _pendingReq[data.callId];
            cb(data);
        }
    });

    // ═══════════════════════════════════════════════════════════
    // Toast
    // ═══════════════════════════════════════════════════════════
    function showToast(text) {
        var toast = _el.querySelector('#merc-toast');
        if (!toast) return;
        toast.textContent = text;
        toast.classList.add('visible');
        if (_toastTimer) clearTimeout(_toastTimer);
        _toastTimer = setTimeout(function() {
            toast.classList.remove('visible');
            _toastTimer = null;
        }, 2500);
    }

    // ═══════════════════════════════════════════════════════════
    // 页面导航
    // ═══════════════════════════════════════════════════════════
    function navigateTo(page) {
        if (_busy) return;
        _currentPage = page;
        _pageList.hidden = (page !== 'list');
        _pageHire.hidden = (page !== 'hire');

        if (page === 'list') {
            requestSnapshot();
        } else if (page === 'hire') {
            _hirePage = 1;
            requestHireList();
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 数据请求
    // ═══════════════════════════════════════════════════════════
    function requestSnapshot() {
        sendPanelMsg('snapshot', null, function(data) {
            if (!data.success) {
                _busy = false;
                showToast('加载失败: ' + (data.error || '未知错误'));
                return;
            }
            _snapshot = data.snapshot;
            _hiredMercs = _snapshot.hiredMercs || [];
            updateResources();
            renderListPage();
        });
    }

    function requestHireList() {
        if (_busy) return;
        _busy = true;
        var loadingEl = _el.querySelector('#merc-hire-loading');
        if (loadingEl) loadingEl.hidden = false;

        sendPanelMsg('hire_list', { page: _hirePage }, function(data) {
            _busy = false;
            if (loadingEl) loadingEl.hidden = true;
            if (!data.success) {
                showToast('加载失败: ' + (data.error || '未知错误'));
                return;
            }
            var hl = data.hireList;
            _hireData = hl.hireable || [];
            _hirePage = hl.page;
            _hireTotalPages = hl.totalPages;
            renderHirePage();
        });
    }

    function updateResources() {
        if (!_snapshot) return;
        if (_goldEl) _goldEl.textContent = '金币: ' + (_snapshot.gold || 0).toLocaleString();
        if (_kpointEl) _kpointEl.textContent = 'K点: ' + (_snapshot.kpoint || 0);
        if (_slotCountEl) _slotCountEl.textContent = _hiredMercs.length + '/' + (_snapshot.maxSlots || 0);
    }

    // ═══════════════════════════════════════════════════════════
    // 操作
    // ═══════════════════════════════════════════════════════════
    function onDeploy(mercIndex, mercName) {
        if (_busy) return;
        _busy = true;
        sendPanelMsg('deploy', { mercIndex: mercIndex }, function(data) {
            _busy = false;
            if (!data.success) {
                showToast('操作失败: ' + (data.error || '未知错误'));
                return;
            }
            // 找到对应佣兵更新本地状态（使用 slotIndex 匹配，不能用数组下标直接索引）
            for (var i = 0; i < _hiredMercs.length; i++) {
                if (_hiredMercs[i].slotIndex === mercIndex) {
                    _hiredMercs[i].deployed = data.deployed;
                    break;
                }
            }
            // 同时更新 snapshot 缓存
            if (_snapshot && _snapshot.hiredMercs) {
                for (var j = 0; j < _snapshot.hiredMercs.length; j++) {
                    if (_snapshot.hiredMercs[j].slotIndex === mercIndex) {
                        _snapshot.hiredMercs[j].deployed = data.deployed;
                        break;
                    }
                }
            }
            renderListPage();
        });
    }

    function onDismiss(mercIndex, mercName) {
        if (_busy) return;
        if (!confirm('确定要解雇 ' + mercName + ' 吗？')) return;
        _busy = true;
        sendPanelMsg('dismiss', { mercIndex: mercIndex }, function(data) {
            _busy = false;
            if (!data.success) {
                showToast('解雇失败: ' + (data.error || '未知错误'));
                return;
            }
            showToast('已解雇 ' + data.mercName);
            requestSnapshot();
        });
    }

    function onHire(poolIndex, mercName) {
        if (_busy) return;
        _busy = true;
        sendPanelMsg('hire', { poolIndex: poolIndex }, function(data) {
            _busy = false;
            if (!data.success) {
                showToast('雇佣失败: ' + (data.error || '未知错误'));
                return;
            }
            showToast('成功雇佣 ' + data.mercName + '！');
            // 更新资源显示
            if (_snapshot) {
                _snapshot.gold = data.goldRemaining;
                _snapshot.kpoint = data.kpointRemaining;
            }
            updateResources();
            // 刷新列表
            requestHireList();
        });
    }

    function updateSnapshotMerc(index, updates) {
        if (_snapshot && _snapshot.hiredMercs && _snapshot.hiredMercs[index]) {
            Object.keys(updates).forEach(function(k) {
                _snapshot.hiredMercs[index][k] = updates[k];
            });
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：列表页（佣兵管理）
    // ═══════════════════════════════════════════════════════════
    function renderListPage() {
        var grid = _el.querySelector('#merc-grid');
        var emptyEl = _el.querySelector('#merc-list-empty');
        if (!grid) return;

        grid.innerHTML = '';

        if (_hiredMercs.length === 0) {
            if (emptyEl) emptyEl.hidden = false;
            return;
        }
        if (emptyEl) emptyEl.hidden = true;

        _hiredMercs.forEach(function(merc) {
            var card = document.createElement('div');
            card.className = 'merc-card';
            card.appendChild(createPortrait());

            // 基本信息区
            var info = document.createElement('div');
            info.className = 'merc-card-info';
            info.innerHTML =
                '<div class="merc-card-name">' + escHtml(merc.name) +
                ' <span class="merc-card-meta">Lv.' + merc.level + ' | ' + escHtml(merc.gender) +
                (merc.deployed ? ' | <span class="merc-deployed">已出战</span>' : '') +
                '</span></div>';

            // 装备图标网格 — 11 槽固定渲染 (slot 6-16)
            var equipGrid = document.createElement('div');
            equipGrid.className = 'merc-equip-grid';
            var SLOTS = window.MercData.SLOTS;
            var SLOT_NAMES = window.MercData.SLOT_NAMES;
            var equipBySlot = {};
            if (merc.equips && merc.equips.length > 0) {
                for (var k = 0; k < merc.equips.length; k++) {
                    equipBySlot[merc.equips[k].slot] = merc.equips[k];
                }
            }
            for (var s = 0; s < SLOTS.length; s++) {
                var slot = SLOTS[s];
                var eq = equipBySlot[slot];
                if (eq) {
                    var raw = eq.raw || eq.name;
                    var iconKey = eq.icon || eq.name;
                    var displayName = eq.displayname || eq.name;
                    var iconUrl = (typeof Icons !== 'undefined') ? Icons.resolve(iconKey) : null;
                    var iconHtml = iconUrl
                        ? '<img src="' + escAttr(iconUrl) + '" alt="" onerror="this.style.display=\'none\'">'
                        : '<span class="merc-equip-fallback">' + escHtml(displayName.charAt(0)) + '</span>';
                    var cell = document.createElement('div');
                    cell.className = 'merc-equip-cell';
                    cell.setAttribute('data-eq-raw', raw);
                    cell.setAttribute('data-eq-displayname', displayName);
                    cell.setAttribute('data-eq-icon', iconKey);
                    cell.setAttribute('data-eq-level', eq.level);
                    cell.innerHTML = iconHtml +
                        '<span class="merc-equip-level">' + eq.level + '</span>';
                    cell.addEventListener('mouseenter', onEquipHover);
                    cell.addEventListener('mouseleave', onEquipLeave);
                    cell.addEventListener('mousemove', onEquipMove);
                    equipGrid.appendChild(cell);
                } else {
                    var emptyCell = document.createElement('div');
                    emptyCell.className = 'merc-equip-cell merc-equip-empty';
                    emptyCell.title = SLOT_NAMES[slot] || '';
                    equipGrid.appendChild(emptyCell);
                }
            }

            // 操作按钮
            var actions = document.createElement('div');
            actions.className = 'merc-card-actions';
            var deployBtn = document.createElement('button');
            deployBtn.className = 'merc-deploy-btn' + (merc.deployed ? ' merc-deploy-btn-rest' : '');
            deployBtn.textContent = merc.deployed ? '休息' : '出战';
            deployBtn.addEventListener('click', function() { onDeploy(merc.slotIndex, merc.name); });
            actions.appendChild(deployBtn);

            var dismissBtn = document.createElement('button');
            dismissBtn.className = 'merc-dismiss-btn';
            dismissBtn.textContent = '解雇';
            dismissBtn.addEventListener('click', function() { onDismiss(merc.slotIndex, merc.name); });
            actions.appendChild(dismissBtn);

            info.appendChild(equipGrid);
            info.insertAdjacentHTML('beforeend', '<div class="merc-ability-placeholder">战术能力 · 待接入</div>');
            card.appendChild(info);
            card.appendChild(actions);
            grid.appendChild(card);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：雇佣页
    // ═══════════════════════════════════════════════════════════
    function renderHirePage() {
        var grid = _el.querySelector('#merc-hire-grid');
        var emptyEl = _el.querySelector('#merc-hire-empty');
        var pageInfo = _el.querySelector('#merc-hire-page-info');
        if (!grid) return;

        grid.innerHTML = '';

        if (_hireData.length === 0) {
            if (emptyEl) emptyEl.hidden = false;
            if (pageInfo) pageInfo.textContent = '';
            return;
        }
        if (emptyEl) emptyEl.hidden = true;
        if (pageInfo) pageInfo.textContent = '第 ' + _hirePage + ' / ' + _hireTotalPages + ' 页';

        updateHirePagination();

        _hireData.forEach(function(merc) {
            var card = document.createElement('div');
            card.className = 'merc-card';
            card.appendChild(createPortrait());

            var info = document.createElement('div');
            info.className = 'merc-card-info';
            info.innerHTML =
                '<div class="merc-card-name">' + escHtml(merc.name) +
                ' <span class="merc-card-meta">Lv.' + merc.level + ' | ' + escHtml(merc.gender) +
                ' | <span class="merc-price-gold">' + (merc.goldPrice || 0).toLocaleString() + ' 金币</span>' +
                (merc.kPrice > 0 ? ' | <span class="merc-price-kpoint">' + merc.kPrice + ' K点</span>' : '') +
                '</span></div>';

            // 装备图标网格 — 11 槽固定渲染 (slot 6-16)
            var equipGrid = document.createElement('div');
            equipGrid.className = 'merc-equip-grid';
            var SLOTS = window.MercData.SLOTS;
            var SLOT_NAMES = window.MercData.SLOT_NAMES;
            var equipBySlot = {};
            if (merc.equips && merc.equips.length > 0) {
                for (var k = 0; k < merc.equips.length; k++) {
                    equipBySlot[merc.equips[k].slot] = merc.equips[k];
                }
            }
            for (var s = 0; s < SLOTS.length; s++) {
                var slot = SLOTS[s];
                var eq = equipBySlot[slot];
                if (eq) {
                    var raw = eq.raw || eq.name;
                    var iconKey = eq.icon || eq.name;
                    var displayName = eq.displayname || eq.name;
                    var iconUrl = (typeof Icons !== 'undefined') ? Icons.resolve(iconKey) : null;
                    var iconHtml = iconUrl
                        ? '<img src="' + escAttr(iconUrl) + '" alt="" onerror="this.style.display=\'none\'">'
                        : '<span class="merc-equip-fallback">' + escHtml(displayName.charAt(0)) + '</span>';
                    var cell = document.createElement('div');
                    cell.className = 'merc-equip-cell';
                    cell.setAttribute('data-eq-raw', raw);
                    cell.setAttribute('data-eq-displayname', displayName);
                    cell.setAttribute('data-eq-icon', iconKey);
                    cell.setAttribute('data-eq-level', eq.level);
                    cell.innerHTML = iconHtml +
                        '<span class="merc-equip-level">' + eq.level + '</span>';
                    cell.addEventListener('mouseenter', onEquipHover);
                    cell.addEventListener('mouseleave', onEquipLeave);
                    cell.addEventListener('mousemove', onEquipMove);
                    equipGrid.appendChild(cell);
                } else {
                    var emptyCell = document.createElement('div');
                    emptyCell.className = 'merc-equip-cell merc-equip-empty';
                    emptyCell.title = SLOT_NAMES[slot] || '';
                    equipGrid.appendChild(emptyCell);
                }
            }

            var actions = document.createElement('div');
            actions.className = 'merc-card-actions';
            var hireBtn = document.createElement('button');
            hireBtn.className = 'merc-hire-btn';
            hireBtn.textContent = '雇佣';
            // 佣兵槽位已满时禁用
            var slotsFull = _snapshot && _snapshot.maxSlots > 0 && _hiredMercs.length >= _snapshot.maxSlots;
            if (slotsFull) {
                hireBtn.disabled = true;
                hireBtn.title = '佣兵已满 (' + _hiredMercs.length + '/' + _snapshot.maxSlots + ')';
            }
            // 金币不足时禁用
            if (!slotsFull && _snapshot && _snapshot.gold < merc.goldPrice) {
                hireBtn.disabled = true;
                hireBtn.title = '金币不足';
            }
            if (!slotsFull && _snapshot && merc.kPrice > 0 && _snapshot.kpoint < merc.kPrice) {
                hireBtn.disabled = true;
                hireBtn.title = 'K点不足';
            }
            hireBtn.addEventListener('click', function() { onHire(merc.poolIndex, merc.name); });
            actions.appendChild(hireBtn);

            info.appendChild(equipGrid);
            info.insertAdjacentHTML('beforeend', '<div class="merc-ability-placeholder">战术能力 · 待接入</div>');
            card.appendChild(info);
            card.appendChild(actions);
            grid.appendChild(card);
        });
    }

    function updateHirePagination() {
        var firstBtn = _el.querySelector('#merc-hire-first');
        var skipPrevBtn = _el.querySelector('#merc-hire-skip-prev');
        var prevBtn = _el.querySelector('#merc-hire-prev');
        var nextBtn = _el.querySelector('#merc-hire-next');
        var skipNextBtn = _el.querySelector('#merc-hire-skip-next');
        var lastBtn = _el.querySelector('#merc-hire-last');
        var atFirst = (_hirePage <= 1);
        var atLast = (_hirePage >= _hireTotalPages);
        if (firstBtn) firstBtn.disabled = atFirst;
        if (skipPrevBtn) skipPrevBtn.disabled = atFirst;
        if (prevBtn) prevBtn.disabled = atFirst;
        if (nextBtn) nextBtn.disabled = atLast;
        if (skipNextBtn) skipNextBtn.disabled = atLast;
        if (lastBtn) lastBtn.disabled = atLast;
    }

    // ═══════════════════════════════════════════════════════════
    // 装备 Tooltip — kshop 范式：immediate basic html + async rich fetch + cache
    // ═══════════════════════════════════════════════════════════
    function onEquipHover(e) {
        var cell = e.currentTarget;
        var raw = cell.getAttribute('data-eq-raw');
        var displayName = cell.getAttribute('data-eq-displayname') || raw;
        var iconKey = cell.getAttribute('data-eq-icon') || '';
        var level = Number(cell.getAttribute('data-eq-level'));
        if (!raw) return;
        var key = raw + '|' + level;
        _ttHoverKey = key;
        var iconUrl = (iconKey && typeof Icons !== 'undefined') ? Icons.resolve(iconKey) : null;

        var cached = _ttCache[key];
        var html = cached
            ? buildRichTooltipHtml(cached, iconUrl)
            : buildBasicTooltipHtml(displayName, level, iconUrl);
        PanelTooltip.showAtMouse(html, e);
        if (!cached) requestEquipTooltip(raw, level, key, iconUrl);
    }

    function onEquipLeave() {
        _ttHoverKey = null;
        PanelTooltip.hide();
    }

    function onEquipMove(e) {
        PanelTooltip.followMouse(e);
    }

    function buildBasicTooltipHtml(displayName, level, iconUrl) {
        var iconBlock = iconUrl
            ? '<div class="kshop-tt-icon"><img src="' + iconUrl + '"></div>'
            : '';
        return '<div class="kshop-tt-rich merc-tt-basic">' +
                iconBlock +
                '<div class="kshop-tt-desc">' +
                    '<div class="kshop-tt-header"><b>' + escHtml(displayName) + '</b>' +
                        ' <span class="kshop-tt-dim">Lv.' + level + '</span></div>' +
                    '<div class="kshop-tt-loading">加载中...</div>' +
                '</div>' +
            '</div>';
    }

    function buildRichTooltipHtml(data, iconUrl) {
        return PanelTooltip.buildItemRichHtml({
            iconUrl:   iconUrl,
            introHTML: data.introHTML,
            descHTML:  data.descHTML,
            rootClass: 'merc-tt-rich'
        });
    }

    function requestEquipTooltip(raw, level, key, iconUrl) {
        var reqId = 'merc_tt_' + (++_reqSeq) + '_' + _session;
        _pendingReq[reqId] = function(resp) {
            if (!resp.success) return;
            _ttCache[key] = {
                descHTML: resp.descHTML || '',
                introHTML: resp.introHTML || '',
                displayname: resp.displayname || '',
                itemName: resp.itemName || raw
            };
            if (_ttHoverKey === key && PanelTooltip.isVisible() && Panels.isOpen()) {
                PanelTooltip.updateContent(buildRichTooltipHtml(_ttCache[key], iconUrl));
            }
        };
        Bridge.send({
            type: 'panel',
            panel: 'mercs',
            cmd: 'equip_tooltip',
            callId: reqId,
            raw: raw,
            level: level
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════
    function escHtml(s) {
        if (!s) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function escAttr(text) {
        return String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
    }

    function eqSlotLabel(slot) {
        var names = { 6:'头', 7:'衣', 8:'手', 9:'裤', 10:'鞋', 11:'颈', 12:'枪', 13:'手', 14:'枪2', 15:'刀', 16:'雷' };
        return names[slot] || '?';
    }

    function createPortrait() {
        var portrait = document.createElement('div');
        portrait.className = 'merc-card-portrait merc-card-portrait-fallback';
        portrait.innerHTML = '<img src="https://cfn-assets.local/portraits/profiles/%E6%97%A0%E5%A4%B4%E5%83%8F.png" alt="无头像">';
        var img = portrait.querySelector('img');
        img.addEventListener('load', function() { portrait.classList.remove('merc-card-portrait-fallback'); });
        img.addEventListener('error', function() { img.hidden = true; });
        return portrait;
    }

    // ═══════════════════════════════════════════════════════════
    // DOM 创建
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'merc-panel team-child team-merc-child';
        _el.innerHTML =
            '<div class="merc-toast" id="merc-toast"></div>' +

            // ═══════════════════════════════════════
            // 页面 1: 佣兵管理
            // ═══════════════════════════════════════
            '<div class="merc-page" id="merc-page-list">' +
                '<div class="merc-page-header">' +
                    '<h1 class="merc-page-title">佣兵管理</h1>' +
                    '<div class="merc-resources">' +
                        '<span class="merc-resource merc-resource-gold" id="merc-gold">--</span>' +
                        '<span class="merc-resource merc-resource-kpoint" id="merc-kpoint">--</span>' +
                        '<span class="merc-resource" id="merc-slot-count">0/0</span>' +
                    '</div>' +
                    '<button class="merc-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
                '</div>' +
                '<div class="merc-page-body">' +
                    '<div class="merc-grid" id="merc-grid"></div>' +
                    '<div class="merc-list-empty" id="merc-list-empty" hidden>暂无佣兵，快去雇佣一个吧！</div>' +
                '</div>' +
                '<div class="merc-page-footer">' +
                    '<button class="merc-nav-btn" type="button" id="merc-goto-hire">雇佣佣兵</button>' +
                '</div>' +
            '</div>' +

            // ═══════════════════════════════════════
            // 页面 2: 雇佣兵
            // ═══════════════════════════════════════
            '<div class="merc-page" id="merc-page-hire" hidden>' +
                '<div class="merc-page-header">' +
                    '<button class="merc-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<h2 class="merc-page-title">雇佣佣兵</h2>' +
                    '<div class="merc-page-header-spacer"></div>' +
                '</div>' +
                '<div class="merc-page-body">' +
                    '<div class="merc-hire-grid" id="merc-hire-grid"></div>' +
                    '<div class="merc-hire-empty" id="merc-hire-empty" hidden>暂时没有可雇佣的佣兵</div>' +
                    '<div class="merc-hire-loading" id="merc-hire-loading" hidden>加载中...</div>' +
                '</div>' +
                '<div class="merc-page-footer">' +
                    '<div class="merc-page-nav">' +
                        '<button class="merc-page-nav-btn merc-page-skip-btn" type="button" id="merc-hire-first" disabled>|‹</button>' +
                        '<button class="merc-page-nav-btn merc-page-skip-btn" type="button" id="merc-hire-skip-prev" disabled>«</button>' +
                        '<button class="merc-page-nav-btn" type="button" id="merc-hire-prev" disabled>上一页</button>' +
                        '<span class="merc-page-nav-info" id="merc-hire-page-info"></span>' +
                        '<button class="merc-page-nav-btn" type="button" id="merc-hire-next">下一页</button>' +
                        '<button class="merc-page-nav-btn merc-page-skip-btn" type="button" id="merc-hire-skip-next">»</button>' +
                        '<button class="merc-page-nav-btn merc-page-skip-btn" type="button" id="merc-hire-last">›|</button>' +
                    '</div>' +
                '</div>' +
            '</div>';

        _pageList  = _el.querySelector('#merc-page-list');
        _pageHire  = _el.querySelector('#merc-page-hire');
        _goldEl    = _el.querySelector('#merc-gold');
        _kpointEl     = _el.querySelector('#merc-kpoint');
	_slotCountEl  = _el.querySelector('#merc-slot-count');

        // 关闭按钮
        _el.querySelector('.merc-close-btn').addEventListener('click', requestClose);

        // 列表页 → 雇佣页
        _el.querySelector('#merc-goto-hire').addEventListener('click', function() {
            navigateTo('hire');
        });

        // 雇佣页 → 返回列表
        _el.querySelector('.merc-page-back').addEventListener('click', function() {
            navigateTo('list');
        });

        // 分页按钮
        _el.querySelector('#merc-hire-first').addEventListener('click', function() {
            if (_hirePage > 1) { _hirePage = 1; requestHireList(); }
        });
        _el.querySelector('#merc-hire-skip-prev').addEventListener('click', function() {
            if (_hirePage > 1) { _hirePage = Math.max(1, _hirePage - 5); requestHireList(); }
        });
        _el.querySelector('#merc-hire-prev').addEventListener('click', function() {
            if (_hirePage > 1) { _hirePage--; requestHireList(); }
        });
        _el.querySelector('#merc-hire-next').addEventListener('click', function() {
            if (_hirePage < _hireTotalPages) { _hirePage++; requestHireList(); }
        });
        _el.querySelector('#merc-hire-skip-next').addEventListener('click', function() {
            if (_hirePage < _hireTotalPages) { _hirePage = Math.min(_hireTotalPages, _hirePage + 5); requestHireList(); }
        });
        _el.querySelector('#merc-hire-last').addEventListener('click', function() {
            if (_hirePage < _hireTotalPages) { _hirePage = _hireTotalPages; requestHireList(); }
        });

        // 预加载图标 manifest（首次打开且未加载时发起 fetch，与其他面板共享缓存）
        if (typeof Icons !== 'undefined') Icons.load(function(){});

        return _el;
    }

    // ═══════════════════════════════════════════════════════════
    // 生命周期
    // ═══════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        _session++;
        _pendingReq = {};
        _busy = false;
        _snapshot = null;
        _hiredMercs = [];
        _ttCache = {};
        _ttHoverKey = null;
        _currentPage = 'list';
        navigateTo('list');
    }

    function requestClose() {
        if (_busy) return;  // 对齐 pet 模式：pending 操作期间阻止关闭，防止状态泄漏
        if (window.TeamPanelHost && TeamPanelHost.requestClose) {
            TeamPanelHost.requestClose();
            return;
        }
        Panels.close();     // 先触发 onClose 清理 JS 状态（tooltip/缓存/pendingReq），再通知 C#
        Bridge.send({ type: 'panel', panel: 'mercs', cmd: 'close' });
    }

    function onClose() {
        _session++;
        if (_toastTimer) clearTimeout(_toastTimer);
        _pendingReq = {};
        _busy = false;
        _ttCache = {};
        _ttHoverKey = null;
        PanelTooltip.hide();
    }
    window.MercTeamController = {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        requestClose: requestClose,
        resetToList: function() { navigateTo('list'); },
        isBusy: function() { return _busy; }
    };
})();
