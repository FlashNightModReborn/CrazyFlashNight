(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 状态
    // ═══════════════════════════════════════════════════════════
    var _el;
    var _listViewEl;
    var _detailViewEl;
    var _storeViewEl;
    var _pets = [];
    var _snapshot = null;
    var _activeView = 'list';
    var _activePetIdx = -1;
    var _storeCategoryIdx = 0;
    var _storeData = [];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _storeLoading = false;
    var _toastTimer = null;

    // ═══════════════════════════════════════════════════════════
    // Panel 注册
    // ═══════════════════════════════════════════════════════════
    Panels.register('pets', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
        onClose: onClose
    });

    // ═══════════════════════════════════════════════════════════
    // DOM 创建
    // ═══════════════════════════════════════════════════════════
    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'pet-panel';
        _el.innerHTML =
            '<div class="pet-header">' +
                '<h1 class="pet-title">战宠管理</h1>' +
                '<div class="pet-resources">' +
                    '<span class="pet-resource pet-resource-gold" id="pet-gold">--</span>' +
                    '<span class="pet-resource pet-resource-kpoint" id="pet-kpoint">--</span>' +
                '</div>' +
                '<button class="pet-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
            '</div>' +
            '<div class="pet-status-bar" id="pet-status-bar">' +
                '<span>出战: <strong id="pet-deploy-count">0/0</strong></span>' +
                '<span>宠物栏: <strong id="pet-slot-count">0/0</strong></span>' +
                '<button class="pet-expand-slot-btn" type="button" id="pet-expand-slot-btn" data-audio-cue="confirm">+开格子</button>' +
            '</div>' +
            // ── 列表视图 ──
            '<div class="pet-list-view" id="pet-list-view">' +
                '<div class="pet-grid" id="pet-grid"></div>' +
                '<div class="pet-list-empty" id="pet-list-empty" hidden>暂无战宠，点击下方按钮领养</div>' +
                '<div class="pet-list-footer">' +
                    '<button class="pet-adopt-btn" type="button" id="pet-adopt-btn" data-audio-cue="confirm">领养宠物</button>' +
                '</div>' +
            '</div>' +
            // ── 详情视图 ──
            '<div class="pet-detail-view" id="pet-detail-view" hidden>' +
                '<div class="pet-detail-header">' +
                    '<button class="pet-detail-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<div class="pet-detail-title-block">' +
                        '<h2 class="pet-detail-name" id="pet-detail-name">--</h2>' +
                        '<div class="pet-detail-meta" id="pet-detail-meta"></div>' +
                    '</div>' +
                '</div>' +
                '<div class="pet-detail-body">' +
                    '<div class="pet-stats-section">' +
                        '<h3 class="pet-section-title">属性信息</h3>' +
                        '<div class="pet-stats-grid" id="pet-stats-grid">' +
                            '<div class="pet-stat"><span class="pet-stat-label">等级</span><span class="pet-stat-value" id="pet-stat-level">--</span></div>' +
                            '<div class="pet-stat"><span class="pet-stat-label">体力</span><span class="pet-stat-value" id="pet-stat-stamina">--</span></div>' +
                            '<div class="pet-stat"><span class="pet-stat-label">经验</span><span class="pet-stat-value" id="pet-stat-xp">--</span></div>' +
                            '<div class="pet-stat"><span class="pet-stat-label">身高</span><span class="pet-stat-value" id="pet-stat-height">--</span></div>' +
                        '</div>' +
                    '</div>' +
                    '<div class="pet-promotions-section">' +
                        '<h3 class="pet-section-title">进阶方案</h3>' +
                        '<div class="pet-promotions-list" id="pet-promotions-list"></div>' +
                    '</div>' +
                '</div>' +
                '<div class="pet-detail-footer">' +
                    '<button class="pet-deploy-btn" type="button" id="pet-deploy-btn" data-audio-cue="confirm">出战</button>' +
                '</div>' +
            '</div>' +
            // ── 领养商店视图 ──
            '<div class="pet-store-view" id="pet-store-view" hidden>' +
                '<div class="pet-store-header">' +
                    '<button class="pet-store-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<h2 class="pet-store-title">领养宠物</h2>' +
                '</div>' +
                '<div class="pet-store-tabs" id="pet-store-tabs"></div>' +
                '<div class="pet-store-grid" id="pet-store-grid"></div>' +
                '<div class="pet-store-empty" id="pet-store-empty" hidden>该分类下暂无可领养宠物</div>' +
            '</div>' +
            // ── Toast ──
            '<div class="pet-toast" id="pet-toast"></div>';

        // 绑定事件
        _el.querySelector('.pet-close-btn').addEventListener('click', requestClose);
        _el.querySelector('.pet-detail-back').addEventListener('click', backToList);
        _el.querySelector('.pet-store-back').addEventListener('click', backToList);
        _el.querySelector('#pet-adopt-btn').addEventListener('click', openStore);
        _el.querySelector('#pet-expand-slot-btn').addEventListener('click', onExpandSlot);
        _el.querySelector('#pet-deploy-btn').addEventListener('click', onToggleDeploy);

        // 视图引用
        _listViewEl = _el.querySelector('#pet-list-view');
        _detailViewEl = _el.querySelector('#pet-detail-view');
        _storeViewEl = _el.querySelector('#pet-store-view');

        return _el;
    }

    // ═══════════════════════════════════════════════════════════
    // 生命周期
    // ═══════════════════════════════════════════════════════════
    function onOpen(el, initData) {
        _session++;
        _pendingReq = {};
        _busy = false;
        _storeLoading = false;
        _snapshot = null;
        _activePetIdx = -1;
        _activeView = 'list';
        _storeCategoryIdx = 0;
        _storeData = [];
        hideToast();
        showListView();
        requestSnapshot();
    }

    function requestClose() {
        if (_busy) return;
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'pets', cmd: 'close' });
    }

    function onClose() {
        _pendingReq = {};
        _busy = false;
        _storeLoading = false;
        _snapshot = null;
        _activePetIdx = -1;
        hideToast();
        if (_toastTimer) { clearTimeout(_toastTimer); _toastTimer = null; }
    }

    // ═══════════════════════════════════════════════════════════
    // 视图切换
    // ═══════════════════════════════════════════════════════════
    function showListView() {
        _activeView = 'list';
        _listViewEl.hidden = false;
        _detailViewEl.hidden = true;
        _storeViewEl.hidden = true;
    }

    function showDetailView(idx) {
        _activeView = 'detail';
        _activePetIdx = idx;
        _listViewEl.hidden = true;
        _detailViewEl.hidden = false;
        _storeViewEl.hidden = true;
    }

    function showStoreView() {
        _activeView = 'store';
        _listViewEl.hidden = true;
        _detailViewEl.hidden = true;
        _storeViewEl.hidden = false;
    }

    function backToList() {
        if (_busy) return;
        _activePetIdx = -1;
        showListView();
    }

    function openStore() {
        if (_busy || _storeLoading) return;
        showStoreView();
        if (_storeData.length === 0) {
            requestAdoptList(0);
        } else {
            renderStoreCategories();
            renderStoreGrid(_storeCategoryIdx);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 通信
    // ═══════════════════════════════════════════════════════════
    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'pets') return;
        var handler = _pendingReq[data.callId];
        if (handler) {
            delete _pendingReq[data.callId];
            if (typeof handler === 'function') {
                handler(data);
            }
        }
    });

    function sendPanelMsg(cmd, extra, cb) {
        var callId = 'pet_' + (++_reqSeq) + '_' + Date.now();
        if (cb) _pendingReq[callId] = cb;
        var msg = { type: 'panel', panel: 'pets', cmd: cmd, callId: callId };
        if (extra) {
            for (var k in extra) {
                if (extra.hasOwnProperty(k)) msg[k] = extra[k];
            }
        }
        Bridge.send(msg);
        return callId;
    }

    // ═══════════════════════════════════════════════════════════
    // Snapshot
    // ═══════════════════════════════════════════════════════════
    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (!data.success) {
                showToast('获取战宠数据失败: ' + (data.error || '未知错误'));
                return;
            }
            if (snapSession !== _session) return;
            _snapshot = data.snapshot;
            _pets = data.snapshot.pets || [];
            updateResourceDisplay();
            updateStatusBar();
            renderPetGrid();
        });
    }

    function requestAdoptList(catIdx) {
        _storeLoading = true;
        sendPanelMsg('adopt_list', { categoryIndex: catIdx }, function(data) {
            _storeLoading = false;
            if (!data.success) {
                showToast('获取领养列表失败: ' + (data.error || '超时'));
                return;
            }
            _storeData = data.adoptable || [];
            renderStoreCategories();
            renderStoreGrid(catIdx);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：列表视图
    // ═══════════════════════════════════════════════════════════
    function renderPetGrid() {
        var gridEl = _el.querySelector('#pet-grid');
        var emptyEl = _el.querySelector('#pet-list-empty');
        gridEl.innerHTML = '';

        if (_pets.length === 0) {
            emptyEl.hidden = false;
            return;
        }
        emptyEl.hidden = true;

        for (var i = 0; i < _pets.length; i++) {
            var pet = _pets[i];
            var card = document.createElement('div');
            card.className = 'pet-card' + (pet.deployed ? ' pet-card-deployed' : '');
            card.dataset.index = i;

            var staminaClass = pet.stamina <= 0 ? 'pet-stamina-depleted' :
                               pet.stamina <= 5 ? 'pet-stamina-low' : '';

            card.innerHTML =
                '<div class="pet-card-header">' +
                    '<span class="pet-card-name">' + escapeHtml(pet.name) + '</span>' +
                    (pet.deployed ? '<span class="pet-card-badge">出战中</span>' : '') +
                '</div>' +
                '<div class="pet-card-body">' +
                    '<div class="pet-card-row"><span class="pet-card-label">等级</span><span class="pet-card-value">Lv.' + pet.level + '</span></div>' +
                    '<div class="pet-card-row"><span class="pet-card-label">体力</span><span class="pet-card-value ' + staminaClass + '">' + pet.stamina + '/20</span></div>' +
                '</div>' +
                '<div class="pet-card-footer">' +
                    '<span class="pet-card-hint">点击查看详情</span>' +
                '</div>';

            card.addEventListener('click', function(e) {
                var idx = parseInt(this.dataset.index, 10);
                onPetCardClick(idx);
            });
            gridEl.appendChild(card);
        }
    }

    function updateResourceDisplay() {
        if (!_snapshot) return;
        _el.querySelector('#pet-gold').textContent = '金币: ' + formatMoney(_snapshot.gold);
        _el.querySelector('#pet-kpoint').textContent = 'K点: ' + formatMoney(_snapshot.kpoint);
    }

    function updateStatusBar() {
        if (!_snapshot) return;
        _el.querySelector('#pet-deploy-count').textContent = (_snapshot.currentDeployCount || 0) + '/' + (_snapshot.maxDeploy || 0);
        _el.querySelector('#pet-slot-count').textContent = (_pets.length || 0) + '/' + (_snapshot.maxSlots || 0);
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：详情视图
    // ═══════════════════════════════════════════════════════════
    function onPetCardClick(idx) {
        if (_busy) return;
        var pet = _pets[idx];
        if (!pet) return;

        showDetailView(idx);
        renderDetailView(pet);
    }

    function renderDetailView(pet) {
        _el.querySelector('#pet-detail-name').textContent = pet.name + ' Lv.' + pet.level;

        var metaHtml = '';
        if (pet.deployed) {
            metaHtml += '<span class="pet-meta-chip pet-meta-deployed">出战中</span>';
        } else {
            metaHtml += '<span class="pet-meta-chip pet-meta-resting">休息中</span>';
        }
        if (pet.stamina <= 0) {
            metaHtml += '<span class="pet-meta-chip pet-meta-exhausted">体力耗尽</span>';
        }
        _el.querySelector('#pet-detail-meta').innerHTML = metaHtml;

        // 属性
        _el.querySelector('#pet-stat-level').textContent = 'Lv.' + pet.level;
        _el.querySelector('#pet-stat-stamina').textContent = pet.stamina + '/20';
        _el.querySelector('#pet-stat-xp').textContent = (pet.xp || 0) + '/' + (pet.xpNeeded || '--');
        _el.querySelector('#pet-stat-height').textContent = (pet.height || '--') + 'cm';

        // 出战按钮
        var deployBtn = _el.querySelector('#pet-deploy-btn');
        deployBtn.textContent = pet.deployed ? '休息' : '出战';
        deployBtn.className = 'pet-deploy-btn' + (pet.deployed ? ' pet-deploy-btn-rest' : '');

        if (_snapshot && _snapshot.isCombatMap && !pet.deployed) {
            deployBtn.disabled = true;
            deployBtn.title = '战斗中无法出战';
        } else if (pet.stamina <= 0 && !pet.deployed) {
            deployBtn.disabled = true;
            deployBtn.title = '体力不足';
        } else {
            deployBtn.disabled = false;
            deployBtn.title = '';
        }

        // 进阶方案列表
        renderPromotions(pet);
    }

    function renderPromotions(pet) {
        var listEl = _el.querySelector('#pet-promotions-list');
        listEl.innerHTML = '';

        var petDef = window.PetData ? PetData.getPet(pet.petId) : null;
        if (!petDef || !petDef.promotions || petDef.promotions.length === 0) {
            listEl.innerHTML = '<div class="pet-promo-empty">该宠物暂无进阶方案</div>';
            return;
        }

        for (var i = 0; i < petDef.promotions.length; i++) {
            var schemeName = petDef.promotions[i];
            var scheme = window.PetData ? PetData.getScheme(schemeName) : null;
            if (!scheme) continue;

            // 查找当前进阶进度
            var currentTier = 0;
            if (pet.promotions) {
                for (var j = 0; j < pet.promotions.length; j++) {
                    if (pet.promotions[j].scheme === schemeName) {
                        currentTier = Number(pet.promotions[j].次数) || 0;
                        break;
                    }
                }
            }

            var maxTier = scheme.maxTier || 1;
            var isMaxed = currentTier >= maxTier;
            var canAfford = (_snapshot && _snapshot.gold >= (scheme.gold || 0)) || (scheme.gold || 0) === 0;
            var levelOk = pet.level >= (scheme.unlockLevel || 0);

            var promoEl = document.createElement('div');
            promoEl.className = 'pet-promo-item';
            if (isMaxed) promoEl.classList.add('pet-promo-maxed');
            else if (!levelOk) promoEl.classList.add('pet-promo-locked');
            else if (!canAfford) promoEl.classList.add('pet-promo-unaffordable');

            var tierText = maxTier > 1 ? ' Lv.' + currentTier + '/' + maxTier : '';
            var statusText = '';
            var actionBtn = '';

            if (isMaxed) {
                statusText = '已达上限';
                actionBtn = '<button class="pet-promo-btn" disabled>已完成</button>';
            } else if (!levelOk) {
                statusText = '需Lv.' + scheme.unlockLevel + '解锁';
                actionBtn = '<button class="pet-promo-btn" disabled>等级不足</button>';
            } else if (!canAfford && scheme.gold > 0) {
                statusText = '金币不足';
                actionBtn = '<button class="pet-promo-btn pet-promo-btn-buy" data-scheme="' + escapeHtml(schemeName) + '">' + formatMoney(scheme.gold) + '金 升级</button>';
            } else {
                statusText = scheme.gold > 0 ? formatMoney(scheme.gold) + '金币' : '免费';
                actionBtn = '<button class="pet-promo-btn pet-promo-btn-buy" data-scheme="' + escapeHtml(schemeName) + '">升级</button>';
            }

            promoEl.innerHTML =
                '<div class="pet-promo-info">' +
                    '<div class="pet-promo-name">' + escapeHtml(schemeName) + tierText + '</div>' +
                    '<div class="pet-promo-desc">' + escapeHtml(scheme.desc || '') + '</div>' +
                    '<div class="pet-promo-cost">' + statusText + '</div>' +
                '</div>' +
                '<div class="pet-promo-action">' + actionBtn + '</div>';

            var btnEl = promoEl.querySelector('.pet-promo-btn-buy');
            if (btnEl) {
                btnEl.addEventListener('click', function(e) {
                    e.stopPropagation();
                    var sName = this.dataset.scheme;
                    onAdvance(sName);
                });
            }

            listEl.appendChild(promoEl);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：领养商店
    // ═══════════════════════════════════════════════════════════
    function renderStoreCategories() {
        var tabsEl = _el.querySelector('#pet-store-tabs');
        tabsEl.innerHTML = '';
        var categories = window.PetData ? PetData.CATEGORIES : [];

        for (var c = 0; c < categories.length; c++) {
            var tab = document.createElement('button');
            tab.className = 'pet-store-tab' + (c === _storeCategoryIdx ? ' pet-store-tab-active' : '');
            tab.textContent = categories[c].name;
            tab.dataset.index = c;
            tab.addEventListener('click', function() {
                var ci = parseInt(this.dataset.index, 10);
                _storeCategoryIdx = ci;
                renderStoreCategories();
                requestAdoptList(ci);
            });
            tabsEl.appendChild(tab);
        }
    }

    function renderStoreGrid(catIdx) {
        var gridEl = _el.querySelector('#pet-store-grid');
        var emptyEl = _el.querySelector('#pet-store-empty');
        gridEl.innerHTML = '';

        if (_storeData.length === 0) {
            emptyEl.hidden = false;
            gridEl.hidden = true;
            return;
        }
        emptyEl.hidden = true;
        gridEl.hidden = false;

        for (var i = 0; i < _storeData.length; i++) {
            var pet = _storeData[i];
            var card = document.createElement('div');
            card.className = 'pet-store-card';

            var priceText = '';
            if (pet.price > 0) priceText += formatMoney(pet.price) + '金币';
            if (pet.kprice > 0) {
                if (priceText) priceText += ' / ';
                priceText += formatMoney(pet.kprice) + 'K点';
            }
            if (!priceText) priceText = '免费';

            var canAdopt = true;
            var cantReason = '';
            if (_snapshot && pet.price > 0 && _snapshot.gold < pet.price) {
                canAdopt = false;
                cantReason = '金币不足';
            }
            if (_snapshot && pet.kprice > 0 && _snapshot.kpoint < pet.kprice) {
                canAdopt = false;
                cantReason = 'K点不足';
            }
            if (_snapshot && _pets.length >= _snapshot.maxSlots) {
                canAdopt = false;
                cantReason = '宠物栏已满';
            }
            if (pet.unlockLevel > (_snapshot ? _snapshot.playerLevel : 1)) {
                canAdopt = false;
                cantReason = '需Lv.' + pet.unlockLevel;
            }

            card.innerHTML =
                '<div class="pet-store-card-header">' +
                    '<span class="pet-store-card-name">' + escapeHtml(pet.name) + '</span>' +
                    (pet.unique ? '<span class="pet-store-card-unique">唯一</span>' : '') +
                '</div>' +
                '<div class="pet-store-card-body">' +
                    '<div class="pet-store-card-row"><span class="pet-store-card-label">身高</span><span class="pet-store-card-value">' + (pet.height || '--') + 'cm</span></div>' +
                    '<div class="pet-store-card-row"><span class="pet-store-card-label">价格</span><span class="pet-store-card-value">' + priceText + '</span></div>' +
                '</div>' +
                '<div class="pet-store-card-footer">' +
                    (canAdopt
                        ? '<button class="pet-store-adopt-btn" data-pet-id="' + pet.petId + '">领养</button>'
                        : '<button class="pet-store-adopt-btn" disabled>' + cantReason + '</button>') +
                '</div>';

            if (canAdopt) {
                card.querySelector('.pet-store-adopt-btn').addEventListener('click', function(e) {
                    e.stopPropagation();
                    var pid = parseInt(this.dataset.petId, 10);
                    onAdopt(pid);
                });
            }

            gridEl.appendChild(card);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 操作处理
    // ═══════════════════════════════════════════════════════════
    function onToggleDeploy() {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;

        _busy = true;
        sendPanelMsg('deploy', { slotIndex: pet.slotIndex }, function(data) {
            _busy = false;
            if (data.success) {
                pet.deployed = data.deployed;
                if (_snapshot) {
                    _snapshot.currentDeployCount = data.currentDeployCount;
                }
                updateStatusBar();
                renderDetailView(pet);
                renderPetGrid();
                showToast(pet.deployed ? '已出战' : '已休息');
            } else {
                showToast('操作失败: ' + (data.error || '未知错误'));
            }
        });
    }

    function onAdvance(schemeName) {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;

        _busy = true;
        sendPanelMsg('advance', { slotIndex: pet.slotIndex, scheme: schemeName }, function(data) {
            _busy = false;
            if (data.success) {
                // 刷新快照
                if (_snapshot) {
                    _snapshot.gold = data.gold;
                    _snapshot.kpoint = data.kpoint;
                }
                updateResourceDisplay();
                requestSnapshot(); // 重新拉取宠物数据
            } else {
                var reason = data.reason || data.error || '未知错误';
                showToast('进阶失败: ' + reason);
            }
        });
    }

    function onAdopt(petId) {
        if (_busy) return;

        _busy = true;
        sendPanelMsg('adopt', { petId: petId }, function(data) {
            _busy = false;
            if (data.success) {
                if (_snapshot) {
                    _snapshot.gold = data.gold;
                    _snapshot.kpoint = data.kpoint;
                }
                updateResourceDisplay();
                requestSnapshot();
                requestAdoptList(_storeCategoryIdx);
                showToast('领养成功！');
            } else {
                showToast('领养失败: ' + (data.error || '未知错误'));
            }
        });
    }

    function onExpandSlot() {
        if (_busy) return;

        _busy = true;
        sendPanelMsg('expand_slot', null, function(data) {
            _busy = false;
            if (data.success) {
                if (_snapshot) {
                    _snapshot.gold = data.gold;
                    _snapshot.maxSlots = data.maxSlots;
                }
                updateResourceDisplay();
                updateStatusBar();
                showToast('宠物栏已扩充至' + data.maxSlots);
            } else {
                showToast('扩充失败: ' + (data.error || '未知错误'));
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════
    function formatMoney(n) {
        if (n == null || isNaN(n)) return '--';
        n = Number(n);
        if (n >= 100000000) return (n / 100000000).toFixed(2) + '亿';
        if (n >= 10000) return (n / 10000).toFixed(1) + '万';
        return n.toLocaleString ? n.toLocaleString() : String(n);
    }

    function escapeHtml(s) {
        if (!s) return '';
        s = String(s);
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function showToast(msg) {
        var toastEl = _el.querySelector('#pet-toast');
        if (!toastEl) return;
        toastEl.textContent = msg;
        toastEl.classList.add('pet-toast-visible');
        if (_toastTimer) clearTimeout(_toastTimer);
        _toastTimer = setTimeout(function() {
            toastEl.classList.remove('pet-toast-visible');
            _toastTimer = null;
        }, 2500);
    }

    function hideToast() {
        var toastEl = _el.querySelector('#pet-toast');
        if (toastEl) toastEl.classList.remove('pet-toast-visible');
        if (_toastTimer) { clearTimeout(_toastTimer); _toastTimer = null; }
    }
})();
