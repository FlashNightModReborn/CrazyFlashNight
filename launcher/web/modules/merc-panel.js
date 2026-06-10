(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 状态
    // ═══════════════════════════════════════════════════════════
    var _el;
    var _snapshot = null;
    var _hiredMercs = [];
    var _currentPage = 'list';
    var _detailSlot = -1;         // 培养页当前佣兵 slotIndex
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
    var _confirmSlot = -1;        // 解雇确认弹窗目标
    var _firstListRender = true;  // 仅首次渲染播放卡片入场动画（对齐战宠静默刷新）

    var _pageList, _pageHire, _pageDetail;

    // 卡片技能图标行最多显示 2 行（与装备网格同规格 6 列）：超出折叠为 +N，全量看培养页
    var SKILL_CELL_CAP = 12;

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
    // 按钮 pending 态
    // ═══════════════════════════════════════════════════════════
    function setPending(btn, on) {
        if (!btn) return;
        btn.classList.toggle('merc-btn-pending', !!on);
    }

    // ═══════════════════════════════════════════════════════════
    // 页面导航
    // ═══════════════════════════════════════════════════════════
    function navigateTo(page, params) {
        if (_busy) return;
        var back = (page === 'list' && _currentPage !== 'list');
        _currentPage = page;
        hideAllTooltips();

        _pageList.hidden   = (page !== 'list');
        _pageHire.hidden   = (page !== 'hire');
        _pageDetail.hidden = (page !== 'detail');

        var active = page === 'list' ? _pageList : page === 'hire' ? _pageHire : _pageDetail;
        playPageEnter(active, back);

        if (page === 'list') {
            requestSnapshot();
        } else if (page === 'hire') {
            _hirePage = 1;
            requestHireList();
        } else if (page === 'detail') {
            if (params && typeof params.slotIndex === 'number') _detailSlot = params.slotIndex;
            renderDetailPage();
        }
    }

    function playPageEnter(node, back) {
        if (!node) return;
        node.classList.add(back ? 'merc-page-enter-back' : 'merc-page-enter');
        void node.offsetWidth;
        requestAnimationFrame(function() {
            node.classList.remove('merc-page-enter');
            node.classList.remove('merc-page-enter-back');
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 数据请求
    // ═══════════════════════════════════════════════════════════
    function requestSnapshot(cb) {
        sendPanelMsg('snapshot', null, function(data) {
            if (!data.success) {
                _busy = false;
                showToast('加载失败: ' + (data.error || '未知错误'));
                return;
            }
            _snapshot = data.snapshot;
            _hiredMercs = _snapshot.hiredMercs || [];
            updateResources();
            if (_currentPage === 'list') renderListPage();
            else if (_currentPage === 'detail') renderDetailPage();
            if (cb) cb();
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
        var goldVals = _el.querySelectorAll('.merc-res-gold-val');
        var kVals = _el.querySelectorAll('.merc-res-kpoint-val');
        var i;
        for (i = 0; i < goldVals.length; i++) goldVals[i].textContent = (_snapshot.gold || 0).toLocaleString();
        for (i = 0; i < kVals.length; i++) kVals[i].textContent = String(_snapshot.kpoint || 0);
        var deployed = 0;
        for (i = 0; i < _hiredMercs.length; i++) { if (_hiredMercs[i].deployed) deployed++; }
        var deployEl = _el.querySelector('#merc-deploy-count');
        var slotEl = _el.querySelector('#merc-slot-count');
        if (deployEl) deployEl.textContent = String(deployed);
        if (slotEl) slotEl.textContent = _hiredMercs.length + '/' + (_snapshot.maxSlots || 0);
    }

    function findMercBySlot(slotIndex) {
        for (var i = 0; i < _hiredMercs.length; i++) {
            if (_hiredMercs[i].slotIndex === slotIndex) return _hiredMercs[i];
        }
        return null;
    }

    // ═══════════════════════════════════════════════════════════
    // 操作
    // ═══════════════════════════════════════════════════════════
    function onDeploy(mercIndex, btn) {
        if (_busy) return;
        _busy = true;
        setPending(btn, true);
        sendPanelMsg('deploy', { mercIndex: mercIndex }, function(data) {
            _busy = false;
            setPending(btn, false);
            if (!data.success) {
                showToast('操作失败: ' + (data.error || '未知错误'));
                return;
            }
            for (var i = 0; i < _hiredMercs.length; i++) {
                if (_hiredMercs[i].slotIndex === mercIndex) {
                    _hiredMercs[i].deployed = data.deployed;
                    break;
                }
            }
            if (_currentPage === 'detail') renderDetailPage();
            else renderListPage();
            updateResources();
        });
    }

    function askDismiss(slotIndex) {
        if (_busy) return;
        var merc = findMercBySlot(slotIndex);
        if (!merc) return;
        _confirmSlot = slotIndex;
        var overlay = _el.querySelector('#merc-confirm-overlay');
        _el.querySelector('#merc-confirm-body').innerHTML =
            '确定要解雇 <strong>' + escHtml(merc.name) + '</strong> (Lv.' + merc.level + ') 吗？<br>解雇后将回到雇佣市场。';
        overlay.hidden = false;
    }

    function onDismissConfirm(btn) {
        if (_busy || _confirmSlot < 0) return;
        var slotIndex = _confirmSlot;
        _busy = true;
        setPending(btn, true);
        sendPanelMsg('dismiss', { mercIndex: slotIndex }, function(data) {
            _busy = false;
            setPending(btn, false);
            _el.querySelector('#merc-confirm-overlay').hidden = true;
            _confirmSlot = -1;
            if (!data.success) {
                showToast('解雇失败: ' + (data.error || '未知错误'));
                return;
            }
            showToast('已解雇 ' + data.mercName);
            if (_currentPage === 'detail') {
                _currentPage = 'list';
                _pageList.hidden = false;
                _pageDetail.hidden = true;
            }
            requestSnapshot();
        });
    }

    function onHire(poolIndex, btn) {
        if (_busy) return;
        _busy = true;
        setPending(btn, true);
        sendPanelMsg('hire', { poolIndex: poolIndex }, function(data) {
            _busy = false;
            setPending(btn, false);
            if (!data.success) {
                showToast('雇佣失败: ' + (data.error || '未知错误'));
                return;
            }
            showToast('成功雇佣 ' + data.mercName + '！');
            if (_snapshot) {
                _snapshot.gold = data.goldRemaining;
                _snapshot.kpoint = data.kpointRemaining;
            }
            // 同步雇佣数（影响槽位上限判断），再刷新雇佣列表
            requestSnapshot(function() { requestHireList(); });
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：卡片（列表/雇佣共用骨架）
    // mode: 'list' | 'hire'
    // ═══════════════════════════════════════════════════════════
    function buildMercCard(merc, mode) {
        var card = document.createElement('div');
        card.className = 'merc-card' + (mode === 'list' && merc.deployed ? ' merc-card-deployed' : '');

        // ── 卡头：头像 + 名字/等级/副信息 ──
        var top = document.createElement('div');
        top.className = 'merc-card-top';
        top.appendChild(createPortrait());

        var headinfo = document.createElement('div');
        headinfo.className = 'merc-card-headinfo';
        var subHtml;
        if (mode === 'hire') {
            subHtml = '<div class="merc-card-price">' +
                '<span class="merc-price-gold">' + (merc.goldPrice || 0).toLocaleString() + ' 金币</span>' +
                (merc.kPrice > 0 ? '<span class="merc-price-kpoint">' + merc.kPrice + ' K点</span>' : '') +
            '</div>';
        } else {
            subHtml = '<div class="merc-card-badges">' +
                (merc.deployed ? '<span class="merc-badge merc-badge-deployed">出战中</span>' : '') +
            '</div>';
        }
        headinfo.innerHTML =
            '<div class="merc-card-nameline">' +
                '<span class="merc-card-name">' + escHtml(merc.name) + '</span>' +
                '<span class="merc-card-lv">Lv.' + merc.level + '</span>' +
            '</div>' +
            '<div class="merc-card-sub">' + escHtml(merc.gender || '') +
                (merc.height ? ' · ' + merc.height + 'cm' : '') + '</div>' +
            subHtml;
        top.appendChild(headinfo);
        card.appendChild(top);

        // ── 装备 ──
        card.insertAdjacentHTML('beforeend', '<div class="merc-card-seclabel">装备</div>');
        card.appendChild(buildEquipGrid(merc));

        // ── 技能（占位图标，规格与装备一致）──
        card.insertAdjacentHTML('beforeend', '<div class="merc-card-seclabel">技能</div>');
        card.appendChild(buildSkillGrid(merc, SKILL_CELL_CAP));

        // ── 操作 ──
        var actions = document.createElement('div');
        actions.className = 'merc-card-actions';
        if (mode === 'list') {
            var deployBtn = document.createElement('button');
            deployBtn.type = 'button';
            deployBtn.className = 'merc-mini-btn ' + (merc.deployed ? 'merc-mini-btn-rest' : 'merc-mini-btn-deploy');
            deployBtn.textContent = merc.deployed ? '休息' : '出战';
            deployBtn.addEventListener('click', function() { onDeploy(merc.slotIndex, this); });
            actions.appendChild(deployBtn);

            var trainBtn = document.createElement('button');
            trainBtn.type = 'button';
            trainBtn.className = 'merc-mini-btn merc-mini-btn-train';
            trainBtn.textContent = '培养';
            trainBtn.addEventListener('click', function() { navigateTo('detail', { slotIndex: merc.slotIndex }); });
            actions.appendChild(trainBtn);

            var dismissBtn = document.createElement('button');
            dismissBtn.type = 'button';
            dismissBtn.className = 'merc-mini-btn merc-mini-btn-dismiss';
            dismissBtn.textContent = '解雇';
            dismissBtn.addEventListener('click', function() { askDismiss(merc.slotIndex); });
            actions.appendChild(dismissBtn);
        } else {
            var hireBtn = document.createElement('button');
            hireBtn.type = 'button';
            hireBtn.className = 'merc-mini-btn merc-mini-btn-hire';
            hireBtn.textContent = '雇佣';
            var slotsFull = _snapshot && _snapshot.maxSlots > 0 && _hiredMercs.length >= _snapshot.maxSlots;
            if (slotsFull) {
                hireBtn.disabled = true;
                hireBtn.title = '佣兵已满 (' + _hiredMercs.length + '/' + _snapshot.maxSlots + ')';
            }
            if (!slotsFull && _snapshot && _snapshot.gold < merc.goldPrice) {
                hireBtn.disabled = true;
                hireBtn.title = '金币不足';
            }
            if (!slotsFull && _snapshot && merc.kPrice > 0 && _snapshot.kpoint < merc.kPrice) {
                hireBtn.disabled = true;
                hireBtn.title = 'K点不足';
            }
            hireBtn.addEventListener('click', function() { onHire(merc.poolIndex, this); });
            actions.appendChild(hireBtn);
        }
        card.appendChild(actions);
        return card;
    }

    // 装备图标网格 — 11 槽固定渲染 (slot 6-16)
    function buildEquipGrid(merc) {
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
                equipGrid.appendChild(buildEquipCell(eq));
            } else {
                var emptyCell = document.createElement('div');
                emptyCell.className = 'merc-equip-cell merc-equip-empty';
                emptyCell.title = SLOT_NAMES[slot] || '';
                equipGrid.appendChild(emptyCell);
            }
        }
        return equipGrid;
    }

    function buildEquipCell(eq) {
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
        return cell;
    }

    // 技能图标网格（图标素材未采集 → 类型首字占位，规格与装备图标一致）
    // cap: 最多渲染单元数（含可能的 +N 折叠格）；0/undefined = 不限
    function buildSkillGrid(merc, cap) {
        var grid = document.createElement('div');
        grid.className = 'merc-skill-grid';
        var skills = merc.skills;
        if (!skills || !skills.length) {
            grid.insertAdjacentHTML('beforeend',
                '<div class="merc-skill-none">' + (skills ? '暂无技能' : '技能情报暂不可用') + '</div>');
            return grid;
        }
        var shown = skills.length;
        var folded = 0;
        if (cap && skills.length > cap) {
            shown = cap - 1;
            folded = skills.length - shown;
        }
        for (var i = 0; i < shown; i++) {
            grid.appendChild(buildSkillCell(skills[i]));
        }
        if (folded > 0) {
            var more = document.createElement('div');
            more.className = 'merc-skill-cell merc-skill-more';
            more.innerHTML = '<span class="merc-skill-glyph">+' + folded + '</span>';
            more.setAttribute('data-tip-skill', '其余 ' + folded + ' 个技能见「培养」页');
            grid.appendChild(more);
        }
        return grid;
    }

    function buildSkillCell(sk) {
        var cell = document.createElement('div');
        cell.className = 'merc-skill-cell';
        cell.innerHTML =
            '<span class="merc-skill-glyph">' + escHtml(String(sk.type || '技').charAt(0)) + '</span>' +
            '<span class="merc-skill-level">' + (sk.level || 1) + '</span>';
        cell.setAttribute('data-tip-skill', skillTipHtml(sk));
        cell.addEventListener('mouseenter', onSkillHover);
        cell.addEventListener('mouseleave', onSkillLeave);
        cell.addEventListener('mousemove', onEquipMove);
        return cell;
    }

    function skillTipHtml(sk) {
        return '<b>' + escHtml(sk.name) + '</b> <span class="kshop-tt-dim">Lv.' + (sk.level || 1) + '</span><br>' +
            escHtml((sk.type || '') + ' · ' + (sk.trait || '')) + '<br>' +
            '<span class="kshop-tt-dim">冷却 ' + (sk.cooldown || 0) + 's · 消耗 ' + (sk.cost || 0) + ' MP</span>';
    }

    function onSkillHover(e) {
        var html = e.currentTarget.getAttribute('data-tip-skill');
        if (html) PanelTooltip.showAtMouse(html, e);
    }
    function onSkillLeave() {
        PanelTooltip.hide();
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：列表页（佣兵管理）
    // ═══════════════════════════════════════════════════════════
    function renderListPage() {
        hideAllTooltips();
        var grid = _el.querySelector('#merc-grid');
        var emptyEl = _el.querySelector('#merc-list-empty');
        if (!grid) return;

        grid.innerHTML = '';
        updateResources();

        if (_hiredMercs.length === 0) {
            if (emptyEl) emptyEl.hidden = false;
            return;
        }
        if (emptyEl) emptyEl.hidden = true;

        var animate = _firstListRender;
        _firstListRender = false;
        _hiredMercs.forEach(function(merc, i) {
            var card = buildMercCard(merc, 'list');
            if (animate) card.style.animationDelay = Math.min(i * 0.03, 0.36) + 's';
            else card.style.animation = 'none';
            grid.appendChild(card);
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：雇佣页
    // ═══════════════════════════════════════════════════════════
    function renderHirePage() {
        hideAllTooltips();
        var grid = _el.querySelector('#merc-hire-grid');
        var emptyEl = _el.querySelector('#merc-hire-empty');
        var pageInfo = _el.querySelector('#merc-hire-page-info');
        if (!grid) return;

        grid.innerHTML = '';
        updateResources();

        if (_hireData.length === 0) {
            if (emptyEl) emptyEl.hidden = false;
            if (pageInfo) pageInfo.textContent = '';
            return;
        }
        if (emptyEl) emptyEl.hidden = true;
        if (pageInfo) pageInfo.textContent = '第 ' + _hirePage + ' / ' + _hireTotalPages + ' 页';

        updateHirePagination();

        _hireData.forEach(function(merc, i) {
            var card = buildMercCard(merc, 'hire');
            card.style.animationDelay = Math.min(i * 0.03, 0.36) + 's';
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
    // 渲染：培养页（对标战宠进阶页；装备更换功能预留占位）
    // ═══════════════════════════════════════════════════════════
    function renderDetailPage() {
        hideAllTooltips();
        var merc = findMercBySlot(_detailSlot);
        if (!merc) {
            // 佣兵不存在（被解雇/数据刷新）→ 回列表
            _currentPage = 'list';
            _pageList.hidden = false;
            _pageDetail.hidden = true;
            renderListPage();
            return;
        }

        // ── header ──
        _el.querySelector('#merc-detail-title').textContent = merc.name;
        var meta = _el.querySelector('#merc-detail-meta');
        meta.innerHTML =
            '<span class="merc-meta-chip">Lv.' + merc.level + '</span>' +
            '<span class="merc-meta-chip">' + escHtml(merc.gender || '') + '</span>' +
            (merc.height ? '<span class="merc-meta-chip">' + merc.height + 'cm</span>' : '') +
            (merc.deployed ? '<span class="merc-meta-chip merc-meta-deployed">出战中</span>' : '');

        var deployBtn = _el.querySelector('#merc-detail-deploy');
        deployBtn.textContent = merc.deployed ? '休息' : '出战';
        deployBtn.classList.toggle('merc-hdr-rest', !!merc.deployed);

        // ── 性格特质 ──
        var traitsGrid = _el.querySelector('#merc-traits-grid');
        traitsGrid.innerHTML = '';
        var traits = merc.personality;
        if (traits && traits.length) {
            var topVal = -1;
            var t;
            for (t = 0; t < traits.length; t++) {
                if (traits[t].value > topVal) topVal = traits[t].value;
            }
            for (t = 0; t < traits.length; t++) {
                var tr = traits[t];
                var isTop = tr.value >= topVal - 0.0001;
                var row = document.createElement('div');
                row.className = 'merc-trait' + (isTop ? ' merc-trait-top' : '');
                row.innerHTML =
                    '<span class="merc-trait-name">' + escHtml(tr.name) + '</span>' +
                    '<div class="merc-trait-bar"><div class="merc-trait-fill" style="--w:' + Math.round(tr.value * 100) + '%"></div></div>' +
                    '<span class="merc-trait-val">' + Math.round(tr.value * 100) + '</span>' +
                    (isTop ? '<span class="merc-trait-tag">主导</span>' : '');
                traitsGrid.appendChild(row);
            }
        } else {
            traitsGrid.innerHTML = '<div class="merc-skill-empty-row">性格情报暂不可用</div>';
        }

        // ── 战斗技能（完整列表）──
        var skillRows = _el.querySelector('#merc-skill-rows');
        skillRows.innerHTML = '';
        var skills = merc.skills;
        if (skills && skills.length) {
            for (var s = 0; s < skills.length; s++) {
                var sk = skills[s];
                var srow = document.createElement('div');
                srow.className = 'merc-skill-row';
                srow.appendChild(buildSkillCell(sk));
                srow.insertAdjacentHTML('beforeend',
                    '<div class="merc-skill-row-info">' +
                        '<div class="merc-skill-row-name">' + escHtml(sk.name) +
                            '<span class="merc-skill-row-lv">Lv.' + (sk.level || 1) + '</span></div>' +
                        '<div class="merc-skill-row-desc">' + escHtml((sk.type || '') + ' · ' + (sk.trait || '')) + '</div>' +
                    '</div>' +
                    '<div class="merc-skill-row-stats">冷却 ' + (sk.cooldown || 0) + 's<br>消耗 ' + (sk.cost || 0) + ' MP</div>');
                skillRows.appendChild(srow);
            }
        } else {
            skillRows.innerHTML = '<div class="merc-skill-empty-row">' +
                (skills ? '该佣兵尚未习得技能' : '技能情报暂不可用') + '</div>';
        }

        // ── 装备调配（更换功能预留）──
        var manageGrid = _el.querySelector('#merc-equip-manage-grid');
        manageGrid.innerHTML = '';
        var SLOTS = window.MercData.SLOTS;
        var SLOT_NAMES = window.MercData.SLOT_NAMES;
        var equipBySlot = {};
        if (merc.equips) {
            for (var e = 0; e < merc.equips.length; e++) equipBySlot[merc.equips[e].slot] = merc.equips[e];
        }
        for (var i = 0; i < SLOTS.length; i++) {
            var slot = SLOTS[i];
            var eq = equipBySlot[slot];
            var cellWrap = document.createElement('div');
            cellWrap.className = 'merc-equip-slot';
            if (eq) {
                cellWrap.appendChild(buildEquipCell(eq));
                cellWrap.insertAdjacentHTML('beforeend',
                    '<div class="merc-equip-slot-info">' +
                        '<span class="merc-equip-slot-label">' + escHtml(SLOT_NAMES[slot] || '') + '</span>' +
                        '<span class="merc-equip-slot-name">' + escHtml(eq.displayname || eq.name) + ' +' + eq.level + '</span>' +
                    '</div>');
            } else {
                cellWrap.insertAdjacentHTML('beforeend',
                    '<div class="merc-equip-cell merc-equip-empty"></div>' +
                    '<div class="merc-equip-slot-info">' +
                        '<span class="merc-equip-slot-label">' + escHtml(SLOT_NAMES[slot] || '') + '</span>' +
                        '<span class="merc-equip-slot-name merc-equip-slot-vacant">空</span>' +
                    '</div>');
            }
            cellWrap.insertAdjacentHTML('beforeend',
                '<button class="merc-equip-swap-btn" type="button" disabled title="装备更换功能筹备中">更换</button>');
            manageGrid.appendChild(cellWrap);
        }
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

    function hideAllTooltips() {
        _ttHoverKey = null;
        if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide();
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

    function createPortrait() {
        var portrait = document.createElement('div');
        portrait.className = 'merc-card-portrait merc-card-portrait-fallback';
        portrait.innerHTML = '<img src="https://cfn-assets.local/portraits/profiles/%E6%97%A0%E5%A4%B4%E5%83%8F.png" alt="无头像">';
        var img = portrait.querySelector('img');
        img.addEventListener('load', function() { portrait.classList.remove('merc-card-portrait-fallback'); });
        img.addEventListener('error', function() { img.hidden = true; });
        return portrait;
    }

    function resourcesHtml() {
        return '<div class="merc-resources">' +
            '<span class="merc-resource merc-resource-gold"><span class="merc-resource-label">金币</span><span class="merc-res-gold-val">--</span></span>' +
            '<span class="merc-resource merc-resource-kpoint"><span class="merc-resource-label">K点</span><span class="merc-res-kpoint-val">--</span></span>' +
        '</div>';
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
                    '<span class="merc-title-mark"></span>' +
                    '<h1 class="merc-page-title">佣兵管理</h1>' +
                    '<div class="merc-page-header-spacer"></div>' +
                    resourcesHtml() +
                    '<button class="merc-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
                '</div>' +
                '<div class="merc-toolbar">' +
                    '<span class="merc-status-item">出战 <strong id="merc-deploy-count">0</strong></span>' +
                    '<span class="merc-status-item">佣兵栏 <strong id="merc-slot-count">0/0</strong></span>' +
                    '<div class="merc-toolbar-spacer"></div>' +
                    resourcesHtml() +
                    '<button class="merc-btn-primary" type="button" id="merc-goto-hire" data-audio-cue="confirm">＋ 雇佣佣兵</button>' +
                '</div>' +
                '<div class="merc-grid-wrap">' +
                    '<div class="merc-grid" id="merc-grid"></div>' +
                    '<div class="merc-list-empty" id="merc-list-empty" hidden>' +
                        '<span class="merc-empty-mark"></span>' +
                        '<span>暂无佣兵 · 点击右上「雇佣佣兵」</span>' +
                    '</div>' +
                '</div>' +
            '</div>' +

            // ═══════════════════════════════════════
            // 页面 2: 雇佣兵
            // ═══════════════════════════════════════
            '<div class="merc-page" id="merc-page-hire" hidden>' +
                '<div class="merc-page-header">' +
                    '<button class="merc-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<span class="merc-title-mark"></span>' +
                    '<h2 class="merc-page-title merc-page-title-sub">雇佣佣兵</h2>' +
                    '<div class="merc-page-header-spacer"></div>' +
                    resourcesHtml() +
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
            '</div>' +

            // ═══════════════════════════════════════
            // 页面 3: 培养（对标战宠进阶页）
            // ═══════════════════════════════════════
            '<div class="merc-page" id="merc-page-detail" hidden>' +
                '<div class="merc-page-header">' +
                    '<button class="merc-page-back" type="button" data-audio-cue="cancel">‹ 返回</button>' +
                    '<span id="merc-detail-portrait-host"></span>' +
                    '<div class="merc-title-block">' +
                        '<h2 class="merc-page-title merc-page-title-sub" id="merc-detail-title">--</h2>' +
                        '<div class="merc-detail-meta" id="merc-detail-meta"></div>' +
                    '</div>' +
                    '<div class="merc-page-header-spacer"></div>' +
                    '<div class="merc-header-actions">' +
                        '<button class="merc-hdr-btn merc-hdr-deploy" type="button" id="merc-detail-deploy" data-audio-cue="confirm">出战</button>' +
                        '<button class="merc-hdr-btn merc-hdr-dismiss" type="button" id="merc-detail-dismiss">解雇</button>' +
                    '</div>' +
                '</div>' +
                '<div class="merc-page-body">' +
                    '<div class="merc-section">' +
                        '<h3 class="merc-section-title">性格特质</h3>' +
                        '<div class="merc-traits-grid" id="merc-traits-grid"></div>' +
                    '</div>' +
                    '<div class="merc-section">' +
                        '<h3 class="merc-section-title">战斗技能</h3>' +
                        '<div class="merc-skill-rows" id="merc-skill-rows"></div>' +
                    '</div>' +
                    '<div class="merc-section">' +
                        '<h3 class="merc-section-title">装备调配</h3>' +
                        '<span class="merc-section-hint">装备更换功能筹备中——当前仅展示，后续将在此调整佣兵装备。</span>' +
                        '<div class="merc-equip-manage-grid" id="merc-equip-manage-grid"></div>' +
                    '</div>' +
                '</div>' +
            '</div>' +

            // ═══════════════════════════════════════
            // 解雇确认弹窗
            // ═══════════════════════════════════════
            '<div class="merc-confirm-overlay" id="merc-confirm-overlay" hidden>' +
                '<div class="merc-confirm-dialog">' +
                    '<div class="merc-confirm-icon"></div>' +
                    '<div class="merc-confirm-title">确认解雇</div>' +
                    '<div class="merc-confirm-body" id="merc-confirm-body"></div>' +
                    '<div class="merc-confirm-footer">' +
                        '<button class="merc-confirm-btn merc-confirm-btn-yes" type="button" id="merc-confirm-yes">确认解雇</button>' +
                        '<button class="merc-confirm-btn merc-confirm-btn-no" type="button" id="merc-confirm-no">取消</button>' +
                    '</div>' +
                '</div>' +
            '</div>';

        _pageList   = _el.querySelector('#merc-page-list');
        _pageHire   = _el.querySelector('#merc-page-hire');
        _pageDetail = _el.querySelector('#merc-page-detail');

        // 培养页头像（克隆卡片头像组件，52px 规格）
        var detailPortrait = createPortrait();
        detailPortrait.classList.add('merc-detail-portrait');
        _el.querySelector('#merc-detail-portrait-host').appendChild(detailPortrait);

        // 关闭按钮
        _el.querySelector('.merc-close-btn').addEventListener('click', requestClose);

        // 列表页 → 雇佣页
        _el.querySelector('#merc-goto-hire').addEventListener('click', function() {
            navigateTo('hire');
        });

        // 返回列表（雇佣页/培养页共用）
        var backBtns = _el.querySelectorAll('.merc-page-back');
        for (var b = 0; b < backBtns.length; b++) {
            backBtns[b].addEventListener('click', function() { navigateTo('list'); });
        }

        // 培养页操作
        _el.querySelector('#merc-detail-deploy').addEventListener('click', function() {
            if (_detailSlot >= 0) onDeploy(_detailSlot, this);
        });
        _el.querySelector('#merc-detail-dismiss').addEventListener('click', function() {
            if (_detailSlot >= 0) askDismiss(_detailSlot);
        });

        // 解雇确认弹窗
        var confirmOverlay = _el.querySelector('#merc-confirm-overlay');
        _el.querySelector('#merc-confirm-yes').addEventListener('click', function() { onDismissConfirm(this); });
        _el.querySelector('#merc-confirm-no').addEventListener('click', function() {
            if (_busy) return;
            confirmOverlay.hidden = true;
            _confirmSlot = -1;
        });
        confirmOverlay.addEventListener('click', function(e) {
            if (e.target === confirmOverlay && !_busy) { confirmOverlay.hidden = true; _confirmSlot = -1; }
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

        container.appendChild(_el);
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
        _detailSlot = -1;
        _confirmSlot = -1;
        _firstListRender = true;
        var overlay = _el.querySelector('#merc-confirm-overlay');
        if (overlay) overlay.hidden = true;
        _currentPage = 'list';
        _pageList.hidden = false;
        _pageHire.hidden = true;
        _pageDetail.hidden = true;
        requestSnapshot();
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
        _confirmSlot = -1;
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
