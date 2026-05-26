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

    var _pageList, _pageHire;
    var _goldEl, _kpointEl;

    // ═══════════════════════════════════════════════════════════
    // Panel 注册
    // ═══════════════════════════════════════════════════════════
    Panels.register('mercs', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
        onClose: onClose
    });

    // ═══════════════════════════════════════════════════════════
    // Bridge 通信
    // ═══════════════════════════════════════════════════════════
    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'merc_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = { cmd: cmd, cb: cb, ts: Date.now() };
        var msg = { type: 'panel', panel: 'mercs', cmd: cmd, callId: callId };
        if (extra) {
            Object.keys(extra).forEach(function(k) { msg[k] = extra[k]; });
        }
        Bridge.send(msg);
    }

    Bridge.on('panel_resp', function(data) {
        if (data.panel !== 'mercs') return;
        var entry = _pendingReq[data.callId];
        if (entry && entry.cb) entry.cb(data);
        delete _pendingReq[data.callId];
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
        _currentPage = page;
        _busy = false;  // 切换页面时清除任何残留的 busy 状态
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

            // 基本信息区
            var info = document.createElement('div');
            info.className = 'merc-card-info';
            info.innerHTML =
                '<div class="merc-card-name">' + escHtml(merc.name) + '</div>' +
                '<div class="merc-card-meta">Lv.' + merc.level + ' | ' + escHtml(merc.gender) +
                (merc.deployed ? ' | <span class="merc-deployed">已出战</span>' : '') +
                '</div>';

            // 装备图标网格
            var equipGrid = document.createElement('div');
            equipGrid.className = 'merc-equip-grid';
            if (merc.equips && merc.equips.length > 0) {
                merc.equips.forEach(function(eq) {
                    var icon = document.createElement('div');
                    icon.className = 'merc-equip-icon';
                    icon.title = eq.displayname + ' Lv.' + eq.level;
                    icon.textContent = eqSlotLabel(eq.slot);
                    icon.dataset.raw = eq.raw;
                    icon.dataset.level = eq.level;
                    icon.addEventListener('mouseenter', function() { showEquipTooltip(icon, eq); });
                    icon.addEventListener('mouseleave', hideEquipTooltip);
                    equipGrid.appendChild(icon);
                });
            } else {
                var noEquip = document.createElement('span');
                noEquip.className = 'merc-no-equip';
                noEquip.textContent = '无装备';
                equipGrid.appendChild(noEquip);
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

            var info = document.createElement('div');
            info.className = 'merc-card-info';
            info.innerHTML =
                '<div class="merc-card-name">' + escHtml(merc.name) + '</div>' +
                '<div class="merc-card-meta">Lv.' + merc.level + ' | ' + escHtml(merc.gender) +
                ' | <span class="merc-price-gold">' + (merc.goldPrice || 0).toLocaleString() + ' 金币</span>' +
                (merc.kPrice > 0 ? ' | <span class="merc-price-kpoint">' + merc.kPrice + ' K点</span>' : '') +
                '</div>';

            // 装备图标网格
            var equipGrid = document.createElement('div');
            equipGrid.className = 'merc-equip-grid';
            if (merc.equips && merc.equips.length > 0) {
                merc.equips.forEach(function(eq) {
                    var icon = document.createElement('div');
                    icon.className = 'merc-equip-icon';
                    icon.title = eq.displayname + ' Lv.' + eq.level;
                    icon.textContent = eqSlotLabel(eq.slot);
                    icon.dataset.raw = eq.raw;
                    icon.dataset.level = eq.level;
                    icon.addEventListener('mouseenter', function() { showEquipTooltip(icon, eq); });
                    icon.addEventListener('mouseleave', hideEquipTooltip);
                    equipGrid.appendChild(icon);
                });
            } else {
                var noEquip = document.createElement('span');
                noEquip.className = 'merc-no-equip';
                noEquip.textContent = '无装备';
                equipGrid.appendChild(noEquip);
            }

            var actions = document.createElement('div');
            actions.className = 'merc-card-actions';
            var hireBtn = document.createElement('button');
            hireBtn.className = 'merc-hire-btn';
            hireBtn.textContent = '雇佣';
            // 金币不足时禁用
            if (_snapshot && _snapshot.gold < merc.goldPrice) {
                hireBtn.disabled = true;
                hireBtn.title = '金币不足';
            }
            if (_snapshot && merc.kPrice > 0 && _snapshot.kpoint < merc.kPrice) {
                hireBtn.disabled = true;
                hireBtn.title = 'K点不足';
            }
            hireBtn.addEventListener('click', function() { onHire(merc.poolIndex, merc.name); });
            actions.appendChild(hireBtn);

            info.appendChild(equipGrid);
            card.appendChild(info);
            card.appendChild(actions);
            grid.appendChild(card);
        });
    }

    function updateHirePagination() {
        var prevBtn = _el.querySelector('#merc-hire-prev');
        var nextBtn = _el.querySelector('#merc-hire-next');
        if (prevBtn) prevBtn.disabled = (_hirePage <= 1);
        if (nextBtn) nextBtn.disabled = (_hirePage >= _hireTotalPages);
    }

    // ═══════════════════════════════════════════════════════════
    // 装备 Tooltip
    // ═══════════════════════════════════════════════════════════
    function showEquipTooltip(iconEl, eq) {
        var tip = _el.querySelector('#merc-tooltip');
        if (!tip) return;
        tip.innerHTML = '<div class="merc-tooltip-loading">加载中...</div>';
        var rect = iconEl.getBoundingClientRect();
        var panelRect = _el.getBoundingClientRect();
        tip.style.left = (rect.left - panelRect.left + 30) + 'px';
        tip.style.top = (rect.top - panelRect.top - 10) + 'px';
        tip.hidden = false;

        sendPanelMsg('equip_tooltip', { raw: eq.raw, level: eq.level }, function(data) {
            if (!data.success) {
                tip.innerHTML = '<div class="merc-tooltip-error">' + escHtml(eq.displayname) + ' Lv.' + eq.level + '</div>';
                return;
            }
            tip.innerHTML = (data.introHTML || data.descHTML || '') +
                '<div class="merc-tooltip-name">' + escHtml(data.displayname || eq.displayname) + '</div>';
        });
    }

    function hideEquipTooltip() {
        var tip = _el.querySelector('#merc-tooltip');
        if (tip) tip.hidden = true;
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════
    function escHtml(s) {
        if (!s) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function eqSlotLabel(slot) {
        var names = { 6:'头', 7:'衣', 8:'手', 9:'裤', 10:'鞋', 11:'颈', 12:'枪', 13:'手', 14:'枪2', 15:'刀', 16:'雷' };
        return names[slot] || '?';
    }

    // ═══════════════════════════════════════════════════════════
    // DOM 创建
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'merc-panel';
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
                        '<button class="merc-page-nav-btn" type="button" id="merc-hire-prev" disabled>上一页</button>' +
                        '<span class="merc-page-nav-info" id="merc-hire-page-info"></span>' +
                        '<button class="merc-page-nav-btn" type="button" id="merc-hire-next">下一页</button>' +
                    '</div>' +
                '</div>' +
            '</div>' +

            // Tooltip 浮层
            '<div class="merc-tooltip" id="merc-tooltip" hidden></div>';

        _pageList  = _el.querySelector('#merc-page-list');
        _pageHire  = _el.querySelector('#merc-page-hire');
        _goldEl    = _el.querySelector('#merc-gold');
        _kpointEl  = _el.querySelector('#merc-kpoint');

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
        _el.querySelector('#merc-hire-prev').addEventListener('click', function() {
            if (_hirePage > 1) { _hirePage--; requestHireList(); }
        });
        _el.querySelector('#merc-hire-next').addEventListener('click', function() {
            if (_hirePage < _hireTotalPages) { _hirePage++; requestHireList(); }
        });

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
        _currentPage = 'list';
        navigateTo('list');
    }

    function requestClose() {
        Bridge.send({ type: 'panel', panel: 'mercs', cmd: 'close' });
    }

    function onClose() {
        _session++;
        if (_toastTimer) clearTimeout(_toastTimer);
        _pendingReq = {};
        _busy = false;
    }
})();
