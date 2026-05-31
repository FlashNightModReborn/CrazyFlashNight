(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 状态
    // ═══════════════════════════════════════════════════════════
    var _el;
    var _pets = [];
    var _snapshot = null;
    var _currentPage = 'list';
    var _activePetIdx = -1;
    var _storeCategoryIdx = 0;
    var _storeData = [];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _toastTimer = null;

    // DOM refs (set in createDOM)
    var _pageList, _pageStore, _pageAdvance;
    var _goldEl, _kpointEl;
    var _deployCountEl, _slotCountEl;
    var _toastEl;

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
            // ── Toast（共享） ──
            '<div class="pet-toast" id="pet-toast"></div>' +

            // ═══════════════════════════════════════════════════
            // 页面 1：战宠列表
            // ═══════════════════════════════════════════════════
            '<div class="pet-page" id="pet-page-list">' +
                '<div class="pet-page-header">' +
                    '<h1 class="pet-page-title">战宠管理</h1>' +
                    '<div class="pet-resources">' +
                        '<span class="pet-resource pet-resource-gold" id="pet-gold">--</span>' +
                        '<span class="pet-resource pet-resource-kpoint" id="pet-kpoint">--</span>' +
                    '</div>' +
                    '<button class="pet-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
                '</div>' +
                '<div class="pet-status-bar" id="pet-status-bar">' +
                    '<span>出战: <strong id="pet-deploy-count">0/0</strong></span>' +
                    '<span>宠物栏: <strong id="pet-slot-count">0/0</strong></span>' +
                '</div>' +
                '<div class="pet-page-body">' +
                    '<div class="pet-grid" id="pet-grid"></div>' +
                    '<div class="pet-list-empty" id="pet-list-empty" hidden>暂无战宠，点击下方按钮领养</div>' +
                '</div>' +
                '<div class="pet-page-footer">' +
                    '<button class="pet-adopt-btn" type="button" id="pet-adopt-btn" data-audio-cue="confirm">领养宠物</button>' +
                '</div>' +
            '</div>' +

            // ═══════════════════════════════════════════════════
            // 页面 2：领养商店
            // ═══════════════════════════════════════════════════
            '<div class="pet-page" id="pet-page-store" hidden>' +
                '<div class="pet-page-header">' +
                    '<button class="pet-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<h2 class="pet-page-title">领养宠物</h2>' +
                    '<div class="pet-page-header-spacer"></div>' +
                '</div>' +
                '<div class="pet-page-body">' +
                    '<div class="pet-store-tabs" id="pet-store-tabs"></div>' +
                    '<div class="pet-store-grid" id="pet-store-grid"></div>' +
                    '<div class="pet-store-empty" id="pet-store-empty" hidden>该分类下暂无可领养宠物</div>' +
                    '<div class="pet-store-loading" id="pet-store-loading" hidden>加载中...</div>' +
                '</div>' +
            '</div>' +

            // ═══════════════════════════════════════════════════
            // 页面 3：战宠进阶
            // ═══════════════════════════════════════════════════
            '<div class="pet-page" id="pet-page-advance" hidden>' +
                '<div class="pet-page-header">' +
                    '<button class="pet-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<img class="pet-advance-avatar" id="pet-advance-avatar" src="assets/pets/pet_locked.png" width="64" height="64" alt="">' +
                    '<div class="pet-page-title-block">' +
                        '<h2 class="pet-page-title" id="pet-advance-title">--</h2>' +
                        '<div class="pet-advance-meta" id="pet-advance-meta"></div>' +
                    '</div>' +
                    '<div class="pet-header-actions">' +
                        '<button class="pet-deploy-btn" type="button" id="pet-deploy-btn" data-audio-cue="confirm">出战</button>' +
                        '<button class="pet-restore-btn" type="button" id="pet-restore-btn">恢复体力</button>' +
                        '<button class="pet-levelup-btn" type="button" id="pet-levelup-btn" title="">强化</button>' +
                        '<button class="pet-delete-btn" type="button" id="pet-delete-btn" title="永久删除此宠物">删除</button>' +
                    '</div>' +
                '</div>' +
                '<div class="pet-page-body">' +
                    '<div class="pet-stats-section">' +
                        '<h3 class="pet-section-title">属性信息</h3>' +
                        '<div class="pet-stats-grid" id="pet-stats-grid">' +
                            '<div class="pet-stat"><span class="pet-stat-label">体力</span><span class="pet-stat-value" id="pet-stat-stamina">--</span></div>' +
                            '<div class="pet-stat"><span class="pet-stat-label">经验</span><span class="pet-stat-value" id="pet-stat-xp">--</span></div>' +
                        '</div>' +
                    '</div>' +
                    '<div class="pet-promotions-section">' +
                        '<h3 class="pet-section-title">进阶方案</h3>' +
                        '<div class="pet-promotions-list" id="pet-promotions-list"></div>' +
                    '</div>' +
                '</div>' +
            '</div>' +

            // ── 删除确认弹窗（共享） ──
            '<div class="pet-confirm-overlay" id="pet-confirm-overlay" hidden>' +
                '<div class="pet-confirm-dialog">' +
                    '<div class="pet-confirm-icon">!</div>' +
                    '<div class="pet-confirm-title">确认删除</div>' +
                    '<div class="pet-confirm-body" id="pet-confirm-body"></div>' +
                    '<div class="pet-confirm-footer">' +
                        '<button class="pet-confirm-btn pet-confirm-btn-yes" id="pet-confirm-yes">确认</button>' +
                        '<button class="pet-confirm-btn pet-confirm-btn-no" id="pet-confirm-no">取消</button>' +
                    '</div>' +
                '</div>' +
            '</div>';

        // 缓存 DOM 引用
        _pageList    = _el.querySelector('#pet-page-list');
        _pageStore   = _el.querySelector('#pet-page-store');
        _pageAdvance = _el.querySelector('#pet-page-advance');
        _goldEl      = _el.querySelector('#pet-gold');
        _kpointEl    = _el.querySelector('#pet-kpoint');
        _deployCountEl = _el.querySelector('#pet-deploy-count');
        _slotCountEl   = _el.querySelector('#pet-slot-count');
        _toastEl     = _el.querySelector('#pet-toast');

        // 关闭按钮
        _el.querySelector('.pet-close-btn').addEventListener('click', requestClose);

        // 列表页：领养宠物按钮
        _el.querySelector('#pet-adopt-btn').addEventListener('click', function() {
            navigateTo('store');
        });


        // 进阶页：出战/休息按钮
        _el.querySelector('#pet-deploy-btn').addEventListener('click', onToggleDeploy);

        // 进阶页：恢复体力按钮
        _el.querySelector('#pet-restore-btn').addEventListener('click', function() {
            if (_activePetIdx >= 0 && _pets[_activePetIdx]) {
                onRestoreStamina(_pets[_activePetIdx].slotIndex);
            }
        });

        // 进阶页：强化按钮（战宠灵石升级）
        _el.querySelector('#pet-levelup-btn').addEventListener('click', onLevelUp);

        // 进阶页：删除按钮 → 弹出确认弹窗
        _el.querySelector('#pet-delete-btn').addEventListener('click', onDeleteClick);

        // 删除确认弹窗
        var confirmOverlay = _el.querySelector('#pet-confirm-overlay');
        _el.querySelector('#pet-confirm-yes').addEventListener('click', onDeleteConfirm);
        _el.querySelector('#pet-confirm-no').addEventListener('click', function() {
            confirmOverlay.hidden = true;
        });
        confirmOverlay.addEventListener('click', function(e) {
            if (e.target === confirmOverlay) confirmOverlay.hidden = true;
        });

        // 返回按钮（商店和进阶页共享 .pet-page-back 类名，需按页面分别绑定）
        var backBtns = _el.querySelectorAll('.pet-page-back');
        for (var b = 0; b < backBtns.length; b++) {
            backBtns[b].addEventListener('click', function() {
                navigateTo('list');
            });
        }

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
        _activePetIdx = -1;
        _storeCategoryIdx = 0;
        _storeData = [];
        hideToast();
        navigateTo('list');
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
        _snapshot = null;
        _activePetIdx = -1;
        hideToast();
        if (_toastTimer) { clearTimeout(_toastTimer); _toastTimer = null; }
    }

    // ═══════════════════════════════════════════════════════════
    // 页面导航
    // ═══════════════════════════════════════════════════════════
    function navigateTo(page, params) {
        if (page === _currentPage && !params) return;

        _currentPage = page;
        _pageList.hidden    = (page !== 'list');
        _pageStore.hidden   = (page !== 'store');
        _pageAdvance.hidden = (page !== 'advance');

        switch (page) {
            case 'list':
                _activePetIdx = -1;
                updateResourceDisplay();
                updateStatusBar();
                renderPetGrid();
                break;
            case 'store':
                _storeCategoryIdx = 0;
                _storeData = [];
                renderStoreContent();
                break;
            case 'advance':
                if (params && typeof params.petIdx === 'number') {
                    _activePetIdx = params.petIdx;
                    renderAdvancePage();
                }
                break;
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
    // Snapshot（全局数据拉取）
    // ═══════════════════════════════════════════════════════════
    function requestSnapshot() {
        var snapSession = _session;
        sendPanelMsg('snapshot', null, function(data) {
            if (snapSession !== _session) return;
            if (!data.success) {
                showToast('获取战宠数据失败: ' + (data.error || '未知错误'));
                return;
            }
            _snapshot = data.snapshot;
            _pets = data.snapshot.pets || [];
            updateResourceDisplay();
            updateStatusBar();
            renderPetGrid();
            if (_currentPage === 'advance') renderAdvancePage();
        });
    }

    function requestAdoptList(catIdx, cb) {
        sendPanelMsg('adopt_list', { categoryIndex: catIdx }, function(data) {
            if (!data.success) {
                showToast('获取领养列表失败: ' + (data.error || '超时'));
                if (cb) cb(false);
                return;
            }
            _storeData = data.adoptable || [];
            if (cb) cb(true);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：列表页
    // ═══════════════════════════════════════════════════════════
    function renderPetGrid() {
        var gridEl = _el.querySelector('#pet-grid');
        var emptyEl = _el.querySelector('#pet-list-empty');
        gridEl.innerHTML = '';

        if (!_pets) _pets = [];
        emptyEl.hidden = true;

        for (var i = 0; i < _pets.length; i++) {
            var pet = _pets[i];
            var card = document.createElement('div');
            card.className = 'pet-card' + (pet.deployed ? ' pet-card-deployed' : '');
            card.dataset.index = i;

            var staminaClass = pet.stamina <= 0 ? 'pet-stamina-depleted' :
                               pet.stamina <= 5 ? 'pet-stamina-low' : '';

            var isCombatMap = _snapshot && _snapshot.isCombatMap;
            var deployDisabled = false;
            if (isCombatMap && !pet.deployed) deployDisabled = true;
            else if (pet.stamina <= 0 && !pet.deployed) deployDisabled = true;

            var deployBtnClass = 'pet-card-deploy-btn' + (pet.deployed ? ' pet-card-deploy-btn-rest' : '');
            var deployLabel = pet.deployed ? '休息' : '出战';

            var staminaFull = pet.stamina >= (pet.maxStamina || 200);

            card.innerHTML =
                '<img class="pet-card-icon" src="assets/pets/pet_' + pet.petId + '.png" onerror="this.onerror=null;this.src=\'assets/pets/pet_locked.png\'" width="80" height="80" alt="">' +
                '<div class="pet-card-info">' +
                    '<div class="pet-card-header">' +
                        '<span class="pet-card-name">' + escapeHtml(pet.name) + '</span>' +
                        (pet.deployed ? '<span class="pet-card-badge">出战中</span>' : '') +
                    '</div>' +
                    '<div class="pet-card-body">' +
                        '<div class="pet-card-row"><span class="pet-card-label">等级</span><span class="pet-card-value">Lv.' + pet.level + '</span></div>' +
                        '<div class="pet-card-row"><span class="pet-card-label">体力</span><span class="pet-card-value ' + staminaClass + '">' + pet.stamina + '/' + (pet.maxStamina || 200) + '</span></div>' +
                    '</div>' +
                '</div>' +
                '<div class="pet-card-actions">' +
                    '<button class="' + deployBtnClass + '" data-slot="' + pet.slotIndex + '"' + (deployDisabled ? ' disabled' : '') + '>' + deployLabel + '</button>' +
                    '<button class="pet-card-restore-btn" data-slot="' + pet.slotIndex + '"' + (staminaFull ? ' disabled' : '') + '>恢复体力</button>' +
                '</div>';

            // 点击卡片信息区 → 进入进阶页
            card.addEventListener('click', function(e) {
                var idx = parseInt(this.dataset.index, 10);
                if (!_busy && _pets[idx]) {
                    navigateTo('advance', { petIdx: idx });
                }
            });

            // 出战/休息按钮
            var btnEl = card.querySelector('.pet-card-deploy-btn');
            if (btnEl && !deployDisabled) {
                btnEl.addEventListener('click', function(e) {
                    e.stopPropagation();
                    var slotIdx = parseInt(this.dataset.slot, 10);
                    onDeployFromList(slotIdx);
                });
            } else if (btnEl && deployDisabled) {
                btnEl.addEventListener('click', function(e) {
                    e.stopPropagation();
                });
            }

            // 恢复体力按钮
            var restoreBtn = card.querySelector('.pet-card-restore-btn');
            if (restoreBtn && !staminaFull) {
                restoreBtn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    var slotIdx = parseInt(this.dataset.slot, 10);
                    onRestoreStamina(slotIdx);
                });
            } else if (restoreBtn && staminaFull) {
                restoreBtn.addEventListener('click', function(e) {
                    e.stopPropagation();
                });
            }

            gridEl.appendChild(card);
        }

        // 开格子按钮卡片（跟在最后一个战宠卡片后面）
        var maxSlots = _snapshot ? _snapshot.maxSlots : 0;
        var slotsFull = maxSlots > 0 && _pets.length >= maxSlots;
        var expandCard = document.createElement('div');
        expandCard.className = 'pet-expand-slot-card' + (slotsFull ? ' pet-expand-slot-card-full' : '');
        expandCard.innerHTML =
            '<button class="pet-expand-slot-btn" type="button"' + (slotsFull ? ' disabled' : '') + '>' +
                (slotsFull ? '栏位已满' : '+ 开格子') +
            '</button>';
        if (!slotsFull) {
            expandCard.querySelector('.pet-expand-slot-btn').addEventListener('click', function(e) {
                e.stopPropagation();
                onExpandSlot();
            });
        }
        gridEl.appendChild(expandCard);
    }

    function updateResourceDisplay() {
        if (!_snapshot) return;
        _goldEl.textContent = '金币: ' + formatMoney(_snapshot.gold);
        _kpointEl.textContent = 'K点: ' + formatMoney(_snapshot.kpoint);
    }

    function updateStatusBar() {
        if (!_snapshot) return;
        _deployCountEl.textContent = (_snapshot.currentDeployCount || 0) + '/' + (_snapshot.maxDeploy || 0);
        _slotCountEl.textContent = (_pets.length || 0) + '/' + (_snapshot.maxSlots || 0);
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：进阶页
    // ═══════════════════════════════════════════════════════════
    function renderAdvancePage() {
        var pet = _pets[_activePetIdx];
        if (!pet) return;

        _el.querySelector('#pet-advance-title').textContent = pet.name + ' Lv.' + pet.level;

        var avatarEl = _el.querySelector('#pet-advance-avatar');
        avatarEl.src = 'assets/pets/pet_' + pet.petId + '.png';
        avatarEl.onerror = function() { this.onerror = null; this.src = 'assets/pets/pet_locked.png'; };

        var metaHtml = '';
        if (pet.deployed) {
            metaHtml += '<span class="pet-meta-chip pet-meta-deployed">出战中</span>';
        } else {
            metaHtml += '<span class="pet-meta-chip pet-meta-resting">休息中</span>';
        }
        if (pet.stamina <= 0) {
            metaHtml += '<span class="pet-meta-chip pet-meta-exhausted">体力耗尽</span>';
        }
        _el.querySelector('#pet-advance-meta').innerHTML = metaHtml;

        _el.querySelector('#pet-stat-stamina').textContent = pet.stamina + '/' + (pet.maxStamina || 200);
        _el.querySelector('#pet-stat-xp').textContent = (pet.xp || 0) + '/' + (pet.xpNeeded || '--');

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

        var restoreBtn = _el.querySelector('#pet-restore-btn');
        if (pet.stamina >= (pet.maxStamina || 200)) {
            restoreBtn.disabled = true;
            restoreBtn.title = '体力已满';
        } else if (_snapshot && _snapshot.gold < 1000) {
            restoreBtn.disabled = true;
            restoreBtn.title = '金币不足';
        } else {
            restoreBtn.disabled = false;
            restoreBtn.title = '消耗1000金币恢复体力至满值';
        }

        var levelupBtn = _el.querySelector('#pet-levelup-btn');
        var levelLimit = _snapshot ? (_snapshot.levelLimit || 100) : 100;
        if (pet.level >= levelLimit) {
            levelupBtn.disabled = true;
            levelupBtn.title = '已达等级上限';
            levelupBtn.textContent = '已满级';
        } else {
            levelupBtn.disabled = false;
            var xpNeededForCost = pet.xpNeeded || 0;
            var stoneCost = pet.level * 2 + Math.floor(xpNeededForCost / 10000);
            if (stoneCost < 1) stoneCost = 1;
            levelupBtn.title = '消耗战宠灵石:' + stoneCost + '  |  经验:' + (pet.xp || 0) + '/' + (xpNeededForCost || '--');
            levelupBtn.textContent = '强化 Lv.' + (pet.level + 1);
        }

        renderPromotions(pet);
    }

    // 从 snapshot.petLib 查宠物库定义（权威来自 data/merc/pets.xml，经 AS2 下发）
    function getPetLibDef(petId) {
        if (!_snapshot || !_snapshot.petLib) return null;
        for (var i = 0; i < _snapshot.petLib.length; i++) {
            if (_snapshot.petLib[i].id === petId) return _snapshot.petLib[i];
        }
        return null;
    }

    function renderPromotions(pet) {
        var listEl = _el.querySelector('#pet-promotions-list');
        listEl.innerHTML = '';

        var petDef = getPetLibDef(pet.petId);
        if (!petDef || !petDef.promotions || petDef.promotions.length === 0) {
            listEl.innerHTML = '<div class="pet-promo-empty">该宠物暂无进阶方案</div>';
            return;
        }

        for (var i = 0; i < petDef.promotions.length; i++) {
            var schemeName = petDef.promotions[i];
            var scheme = (_snapshot && _snapshot.schemes) ? _snapshot.schemes[schemeName] : null;
            if (!scheme) continue;

            // 完成/锁定状态来自 AS2 权威 schemeStatus（三件套共用计数、布尔方案查标志，JS 不再自行推断）
            var status = (pet.schemeStatus && pet.schemeStatus[schemeName]) ? pet.schemeStatus[schemeName] : null;
            var isMaxed = status ? !!status.completed : false;
            var levelOk = status ? !status.locked : (pet.level >= (scheme.unlockLevel || 0));
            var canAfford = (_snapshot && _snapshot.gold >= (scheme.gold || 0)) || (scheme.gold || 0) === 0;

            var promoEl = document.createElement('div');
            promoEl.className = 'pet-promo-item';
            if (isMaxed) promoEl.classList.add('pet-promo-maxed');
            else if (!levelOk) promoEl.classList.add('pet-promo-locked');
            else if (!canAfford) promoEl.classList.add('pet-promo-unaffordable');

            var statusText = '';
            var actionBtn = '';

            if (isMaxed) {
                statusText = '已完成';
                actionBtn = '<button class="pet-promo-btn" disabled>已完成</button>';
            } else if (!levelOk) {
                statusText = '需Lv.' + (scheme.unlockLevel || 0) + '解锁';
                actionBtn = '<button class="pet-promo-btn" disabled>未解锁</button>';
            } else if (!canAfford && scheme.gold > 0) {
                statusText = '金币不足';
                actionBtn = '<button class="pet-promo-btn pet-promo-btn-buy" data-scheme="' + escapeHtml(schemeName) + '">' + formatMoney(scheme.gold) + '金 ' + (scheme.buttonText || '执行') + '</button>';
            } else {
                statusText = scheme.gold > 0 ? formatMoney(scheme.gold) + '金币' : '免费';
                actionBtn = '<button class="pet-promo-btn pet-promo-btn-buy" data-scheme="' + escapeHtml(schemeName) + '">' + (scheme.buttonText || '执行') + '</button>';
            }

            promoEl.innerHTML =
                '<div class="pet-promo-info">' +
                    '<div class="pet-promo-name">' + escapeHtml(schemeName) + '</div>' +
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
    // 渲染：领养商店页
    // ═══════════════════════════════════════════════════════════
    function renderStoreContent() {
        // 显示 loading，隐藏 grid 和 empty
        _el.querySelector('#pet-store-loading').hidden = false;
        _el.querySelector('#pet-store-grid').hidden = true;
        _el.querySelector('#pet-store-empty').hidden = true;
        _el.querySelector('#pet-store-tabs').innerHTML = '';

        requestAdoptList(_storeCategoryIdx, function(ok) {
            _el.querySelector('#pet-store-loading').hidden = true;
            if (ok) {
                renderStoreCategories();
                renderStoreGrid(_storeCategoryIdx);
            }
        });
    }

    function renderStoreCategories() {
        var tabsEl = _el.querySelector('#pet-store-tabs');
        tabsEl.innerHTML = '';
        var categories = (_snapshot && _snapshot.categories) ? _snapshot.categories : [];

        for (var c = 0; c < categories.length; c++) {
            var tab = document.createElement('button');
            tab.className = 'pet-store-tab' + (c === _storeCategoryIdx ? ' pet-store-tab-active' : '');
            tab.textContent = categories[c].name;
            tab.dataset.index = c;
            tab.addEventListener('click', function() {
                var ci = parseInt(this.dataset.index, 10);
                _storeCategoryIdx = ci;
                renderStoreCategories();
                // 重新加载该分类数据
                _el.querySelector('#pet-store-loading').hidden = false;
                _el.querySelector('#pet-store-grid').hidden = true;
                _el.querySelector('#pet-store-empty').hidden = true;
                requestAdoptList(ci, function(ok) {
                    _el.querySelector('#pet-store-loading').hidden = true;
                    if (ok) {
                        renderStoreGrid(ci);
                    }
                });
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
            var btnText = priceText;
            var taskLocked = false;
            if (_snapshot && pet.unlockTask > 0 && pet.unlockTask > (_snapshot.playerTask || 0)) {
                canAdopt = false;
                taskLocked = true;
                btnText = '需主线进度 ' + pet.unlockTask;
            } else if (pet.unlockLevel > (_snapshot ? _snapshot.playerLevel : 1)) {
                canAdopt = false;
                btnText = '需Lv.' + pet.unlockLevel;
            } else if (pet.unique && hasPet(pet.petId)) {
                canAdopt = false;
                btnText = '已拥有';
            } else if (_snapshot && _pets.length >= _snapshot.maxSlots) {
                canAdopt = false;
                btnText = '宠物栏已满';
            } else if (_snapshot && pet.price > 0 && _snapshot.gold < pet.price) {
                canAdopt = false;
                // 不改变text
            } else if (_snapshot && pet.kprice > 0 && _snapshot.kpoint < pet.kprice) {
                canAdopt = false;
                // 不改变text
            }

            card.innerHTML =
                '<div class="pet-store-card-header">' +
                    '<span class="pet-store-card-name">' + escapeHtml(pet.name) + '</span>' +
                    (pet.unique ? '<span class="pet-store-card-unique">唯一</span>' : '') +
                '</div>' +
                (taskLocked
                    ? '<img class="pet-store-card-icon" src="assets/pets/pet_locked.png" width="80" height="80" alt="">'
                    : '<img class="pet-store-card-icon" src="assets/pets/pet_' + pet.petId + '.png" onerror="this.onerror=null;this.src=\'assets/pets/pet_locked.png\'" width="80" height="80" alt="">') +
                '<div class="pet-store-card-footer">' +
                    '<button class="pet-store-adopt-btn" data-pet-id="' + pet.petId + '"' + (canAdopt ? '' : ' disabled') + '>' + btnText + '</button>' +
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
                renderPetGrid();
                renderAdvancePage();
                showToast(pet.deployed ? '已出战' : '已休息');
            } else {
                showToast('操作失败: ' + (data.error || '未知错误'));
            }
        });
    }

    function onDeployFromList(slotIndex) {
        if (_busy) return;
        // 从 _pets 中查找对应 slot 的宠物
        var pet = null;
        for (var i = 0; i < _pets.length; i++) {
            if (_pets[i].slotIndex === slotIndex) {
                pet = _pets[i];
                break;
            }
        }
        if (!pet) return;

        _busy = true;
        sendPanelMsg('deploy', { slotIndex: slotIndex }, function(data) {
            _busy = false;
            if (data.success) {
                pet.deployed = data.deployed;
                if (_snapshot) {
                    _snapshot.currentDeployCount = data.currentDeployCount;
                }
                updateStatusBar();
                renderPetGrid();
                showToast(pet.deployed ? '已出战' : '已休息');
            } else {
                showToast('操作失败: ' + (data.error || '未知错误'));
            }
        });
    }

    function onRestoreStamina(slotIndex) {
        if (_busy) return;
        // 找到对应宠物
        var pet = null;
        for (var i = 0; i < _pets.length; i++) {
            if (_pets[i].slotIndex === slotIndex) {
                pet = _pets[i];
                break;
            }
        }
        if (!pet) return;
        if (pet.stamina >= (pet.maxStamina || 200)) return;

        _busy = true;
        sendPanelMsg('restore_stamina', { slotIndex: slotIndex }, function(data) {
            _busy = false;
            if (data.success) {
                pet.stamina = data.stamina;
                if (_snapshot) {
                    _snapshot.gold = data.gold;
                }
                updateResourceDisplay();
                updateStatusBar();
                renderPetGrid();
                if (_currentPage === 'advance') renderAdvancePage();
                showToast('体力已恢复至' + data.stamina);
            } else {
                var errMsg = '恢复失败';
                if (data.error === 'insufficient_gold') errMsg = '金币不足，需要1000金币';
                else if (data.error === 'stamina_full') errMsg = '体力已满';
                else if (data.error) errMsg = data.error;
                showToast(errMsg);
            }
        });
    }

    function onLevelUp() {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;

        _busy = true;
        sendPanelMsg('level_up', { slotIndex: pet.slotIndex }, function(data) {
            _busy = false;
            if (data.success) {
                // 升级会改变等级门槛（强化药剂 Lv.25 / 超级血清 Lv.50 等），schemeStatus 由 AS2 按等级
                // 重算，必须重拉快照刷新，不能只本地改 pet.level（否则解锁判定停留在旧等级）
                requestSnapshot();
                showToast('战宠升级！战宠灵石 -' + data.stoneCost);
            } else {
                var errMsg = '升级失败';
                if (data.error === 'level_maxed') errMsg = '已达等级上限';
                else if (data.error === 'insufficient_stones') errMsg = '战宠灵石不足，需要' + (data.cost || '?') + '个';
                else if (data.error) errMsg = data.error;
                showToast(errMsg);
            }
        });
    }

    function onDeleteClick() {
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;

        var xpNeededForRefund = pet.xpNeeded || 0;
        var refund = Math.floor(Math.sqrt(pet.level) * 0.8 * xpNeededForRefund / 10000);
        if (isNaN(refund) || refund < 0) refund = 0;

        _el.querySelector('#pet-confirm-body').textContent =
            '确认要永久删除 ' + pet.name + ' (Lv.' + pet.level + ') 吗？\n返还战宠灵石: ' + refund + ' 个';
        _el.querySelector('#pet-confirm-overlay').hidden = false;
    }

    function onDeleteConfirm() {
        _el.querySelector('#pet-confirm-overlay').hidden = true;
        if (_busy || _activePetIdx < 0) return;
        var pet = _pets[_activePetIdx];
        if (!pet) return;

        _busy = true;
        sendPanelMsg('delete', { slotIndex: pet.slotIndex }, function(data) {
            _busy = false;
            if (data.success) {
                var refundText = data.stoneRefund > 0 ? '，返还战宠灵石' + data.stoneRefund + '个' : '';
                showToast('已删除战宠' + refundText);
                requestSnapshot();
                navigateTo('list');
            } else {
                showToast('删除失败: ' + (data.error || '未知错误'));
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
                if (_snapshot) {
                    _snapshot.gold = data.gold;
                    _snapshot.kpoint = data.kpoint;
                }
                updateResourceDisplay();
                requestSnapshot(); // 重新拉取宠物数据后刷新进阶页
                showToast('进阶成功！');
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
                showToast('领养成功！');
                // 领养成功后返回列表页
                navigateTo('list');
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

    function hasPet(petId) {
        for (var i = 0; i < _pets.length; i++) {
            if (_pets[i].petId === petId) return true;
        }
        return false;
    }

    function showToast(msg) {
        if (!_toastEl) return;
        _toastEl.textContent = msg;
        _toastEl.classList.add('pet-toast-visible');
        if (_toastTimer) clearTimeout(_toastTimer);
        _toastTimer = setTimeout(function() {
            _toastEl.classList.remove('pet-toast-visible');
            _toastTimer = null;
        }, 2500);
    }

    function hideToast() {
        if (_toastEl) _toastEl.classList.remove('pet-toast-visible');
        if (_toastTimer) { clearTimeout(_toastTimer); _toastTimer = null; }
    }
})();
