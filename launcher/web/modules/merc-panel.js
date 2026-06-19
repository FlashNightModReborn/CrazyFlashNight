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
    var _selectedSlot = -1;       // 列表页选中佣兵（底部详情栏）
    var _selectedPoolIdx = -1;    // 雇佣页选中佣兵（底部详情栏）
    var _hirePage = 1;
    var _hireTotalPages = 1;
    var _hireTotalCount = 0;
    var _hireMinLevel = 0;        // 等级快速定位：0=全部，>0 时首次请求带 minLevel 让 AS2 跳页
    var _hireMaxLevel = 0;        // 可见池最高等级（回包下发，用于禁用超出范围的定位钮）
    var _hireData = [];

    var LEVEL_JUMPS = [20, 40, 60, 80];
    var _pendingReq = {};
    var _reqSeq = 0;
    var _session = 0;
    var _busy = false;
    var _toastTimer = null;
    var _ttCache = {};            // (raw|level) → {descHTML, introHTML, displayname}
    var _ttHoverKey = null;       // current hover cache key
    var _confirmSlot = -1;        // 解雇确认弹窗目标
    var _firstListRender = true;  // 仅首次渲染播放卡片入场动画（对齐战宠静默刷新）
    var _resizeObserver = null;

    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var DRESSUP_MANIFEST_URL = 'assets/dressup/manifest.json';
    var DRESSUP_SLOT_BY_INDEX = {
        6: 'head',
        7: 'body',
        8: 'hand',
        9: 'leg',
        10: 'foot',
        11: 'neck',
        12: 'primary',
        13: 'secondary1',
        14: 'secondary2',
        15: 'melee',
        16: 'grenade'
    };
    var DRESSUP_BODY_FIT_FIELDS = [
        '身体', '上臂', '左下臂', '右下臂', '左手', '右手',
        '屁股', '左大腿', '右大腿', '小腿', '脚',
        '脸型', '发型', '面具'
    ];
    var DRESSUP_HEAD_FIT_FIELDS = ['脸型', '发型', '面具'];
    var DRESSUP_HEAD_DRAW_FIELDS = DRESSUP_HEAD_FIT_FIELDS.slice(0);
    var DRESSUP_FACE_BY_ID_FALLBACK = {
        '0': '女变装-基本脸型',
        '1': '男变装-基本脸型'
    };
    var DRESSUP_HAIR_COMPAT_ALIASES = {
        '发型-女式-红马尾': '发型-女式-玫红色马尾',
        '发型-女式-白长发': '发型-女式-银色清爽直发',
        '发型-男式-黑尖长发': '发型-男式-黑长发',
        '发型-男式-黑短发': '发型-男式-精武短发'
    };
    var _dressupManifest = null;
    var _dressupManifestPromise = null;
    var _dressupThumbCache = {};
    var _dressupDetailRenderer = null;
    var _dressupDetailCanvas = null;

    var _pageList, _pageHire, _pageDetail;

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
        if (page !== 'detail') destroyDetailDressup();

        var active = page === 'list' ? _pageList : page === 'hire' ? _pageHire : _pageDetail;
        playPageEnter(active, back);

        if (page === 'list') {
            requestSnapshot();
        } else if (page === 'hire') {
            _hireMinLevel = 0;
            updateLevelChips();
            resetHireList();
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

    // ── 雇佣列表：无缝下滑加载（滚动触底拉下一页并追加，替代分页按钮）──
    function resetHireList() {
        _hirePage = 1;
        _hireTotalPages = 1;
        _hireTotalCount = 0;
        _hireData = [];
        _selectedPoolIdx = -1;
        var grid = _el.querySelector('#merc-hire-grid');
        if (grid) grid.innerHTML = '';
        var body = _el.querySelector('#merc-hire-body');
        if (body) body.scrollTop = 0;
        renderSelbar(_el.querySelector('#merc-hire-selbar'), null, false);
        requestHireList(true);
    }

    function requestHireList(reset) {
        if (_busy) return;
        _busy = true;
        setHireSentinel('loading');

        // minLevel 仅随 reset 请求发送（AS2 据此跳页覆盖页码）；
        // 后续触底翻页按返回页码顺延，再带 minLevel 会被反复拽回跳转页
        var req = { page: _hirePage };
        if (reset && _hireMinLevel > 0) req.minLevel = _hireMinLevel;

        sendPanelMsg('hire_list', req, function(data) {
            _busy = false;
            if (!data.success) {
                // 翻页请求失败要回退触底时的页码自增，否则下次触底再 ++ 会静默跳过一页
                if (!reset && _hirePage > 1) _hirePage--;
                setHireSentinel('idle');
                showToast('加载失败: ' + (data.error || '未知错误'));
                return;
            }
            var hl = data.hireList;
            _hirePage = hl.page;
            _hireTotalPages = hl.totalPages;
            _hireTotalCount = hl.totalCount || 0;
            if (typeof hl.maxLevel === 'number') _hireMaxLevel = hl.maxLevel;
            updateLevelChips();
            var items = hl.hireable || [];
            if (reset) {
                _hireData = items;
                renderHirePage();
                anchorToMinLevel();
            } else {
                appendHireCards(items);
            }
            setHireSentinel('idle');
            maybeAutoFill();
        });
    }

    // 等级定位 chip：激活态 + 超出池内最高等级的钮禁用
    function updateLevelChips() {
        var chips = _el.querySelectorAll('.merc-lvl-chip');
        for (var i = 0; i < chips.length; i++) {
            var min = Number(chips[i].dataset.min) || 0;
            chips[i].classList.toggle('merc-lvl-chip-active', min === _hireMinLevel);
            chips[i].disabled = (min > 0 && _hireMaxLevel > 0 && min > _hireMaxLevel);
            if (chips[i].disabled) chips[i].title = '佣兵池内暂无 Lv.' + min + ' 以上的佣兵';
            else chips[i].removeAttribute('title');
        }
    }

    // 跳页是页粒度（AS2 只定位到所在页），页内精确定位：滚动到首个达标卡片
    function anchorToMinLevel() {
        if (_hireMinLevel <= 0) return;
        var body = _el.querySelector('#merc-hire-body');
        var grid = _el.querySelector('#merc-hire-grid');
        if (!body || !grid) return;
        for (var i = 0; i < _hireData.length; i++) {
            if ((_hireData[i].level || 0) >= _hireMinLevel) {
                var card = grid.children[i];
                if (card) body.scrollTop = Math.max(0, card.offsetTop - body.offsetTop - 8);
                return;
            }
        }
    }

    // 经典无限滚动陷阱守卫：首屏没被内容撑满（无法产生滚动）且仍有后续页时自动续载
    function maybeAutoFill() {
        if (_busy || _currentPage !== 'hire') return;
        if (_hirePage >= _hireTotalPages) return;
        var body = _el.querySelector('#merc-hire-body');
        if (body && body.scrollHeight <= body.clientHeight + 4) {
            _hirePage++;
            requestHireList(false);
        }
    }

    function onHireScroll() {
        if (_busy || _currentPage !== 'hire') return;
        if (_hirePage >= _hireTotalPages) return;
        var body = _el.querySelector('#merc-hire-body');
        if (!body) return;
        if (body.scrollTop + body.clientHeight >= body.scrollHeight - 220) {
            _hirePage++;
            requestHireList(false);
        }
    }

    // 触底哨兵：加载中 / 还有更多 / 已全部加载
    function setHireSentinel(state) {
        var el = _el.querySelector('#merc-hire-more');
        if (!el) return;
        if (_hireData.length === 0 && state !== 'loading') { el.hidden = true; return; }
        el.hidden = false;
        el.classList.toggle('merc-hire-more-loading', state === 'loading');
        if (state === 'loading') {
            el.textContent = '加载中...';
        } else if (_hirePage < _hireTotalPages) {
            el.textContent = '↓ 下滑加载更多（已加载 ' + _hireData.length + ' 名）';
        } else {
            el.textContent = '已全部加载（' + _hireData.length + ' 名）';
        }
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
        var coinEl = _el.querySelector('#merc-revive-coins');
        if (deployEl) deployEl.textContent = String(deployed);
        if (slotEl) slotEl.textContent = _hiredMercs.length + '/' + (_snapshot.maxSlots || 0);
        if (coinEl) coinEl.textContent = String(_snapshot.reviveCoins || 0);
    }

    function findMercBySlot(slotIndex) {
        for (var i = 0; i < _hiredMercs.length; i++) {
            if (_hiredMercs[i].slotIndex === slotIndex) return _hiredMercs[i];
        }
        return null;
    }

    function findHireByPoolIdx(poolIndex) {
        for (var i = 0; i < _hireData.length; i++) {
            if (_hireData[i].poolIndex === poolIndex) return _hireData[i];
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
            _selectedSlot = -1;
            requestSnapshot();
        });
    }

    function onHire(poolIndex, btn) {
        if (_busy) return;
        _busy = true;
        setPending(btn, true);
        // 带 mercId 让 AS2 做身份校验：列表刷新前的快速连点会携带已位移的
        // stale poolIndex（hire splice / 解雇回池重排），只靠索引会雇错人
        var picked = findHireByPoolIdx(poolIndex);
        sendPanelMsg('hire', { poolIndex: poolIndex, mercId: picked ? picked.id : '' }, function(data) {
            _busy = false;
            setPending(btn, false);
            if (!data.success) {
                if (data.error === 'pool_changed') {
                    showToast('佣兵列表已变化，已为你刷新');
                    resetHireList();
                    return;
                }
                showToast('雇佣失败: ' + (data.error || '未知错误'));
                return;
            }
            showToast('成功雇佣 ' + data.mercName + '！');
            if (_snapshot) {
                _snapshot.gold = data.goldRemaining;
                _snapshot.kpoint = data.kpointRemaining;
            }
            // 同步雇佣数（影响槽位上限判断）；雇佣会 splice 佣兵池导致后续 poolIndex
            // 整体位移，已加载分页全部失效 → 必须回到第一页重拉，不能局部删卡
            requestSnapshot(function() { resetHireList(); });
        });
    }

    function onRevive(slotIndex, btn) {
        if (_busy) return;
        _busy = true;
        setPending(btn, true);
        sendPanelMsg('revive', { mercIndex: slotIndex }, function(data) {
            _busy = false;
            setPending(btn, false);
            if (typeof data.reviveCoins === 'number' && _snapshot) _snapshot.reviveCoins = data.reviveCoins;
            if (!data.success) {
                showToast('复活失败: ' + (data.error === 'no_revive_coin' ? '复活币不足' : (data.error || '未知错误')));
                updateResources();
                return;
            }
            for (var i = 0; i < _hiredMercs.length; i++) {
                if (_hiredMercs[i].slotIndex === slotIndex) {
                    _hiredMercs[i].dead = false;
                    _hiredMercs[i].deployed = false;
                    break;
                }
            }
            showToast('已复活 ' + data.mercName + '（剩余复活币 ' + (_snapshot ? (_snapshot.reviveCoins || 0) : 0) + '）');
            if (_currentPage === 'detail') renderDetailPage();
            else renderListPage();
            updateResources();
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 纸娃娃预览：卡片/底栏使用一次性缓存图，培养页使用单个 live canvas。
    // ═══════════════════════════════════════════════════════════
    function ensureDressupManifest() {
        if (_dressupManifest) return Promise.resolve(_dressupManifest);
        if (typeof DressupDollRenderer === 'undefined' || !DressupDollRenderer) {
            return Promise.reject(new Error('DressupDollRenderer is not loaded'));
        }
        if (!_dressupManifestPromise) {
            _dressupManifestPromise = DressupDollRenderer.loadManifest(DRESSUP_MANIFEST_URL)
                .then(function(manifest) {
                    _dressupManifest = manifest;
                    return manifest;
                });
        }
        return _dressupManifestPromise;
    }

    function normalizeMercGender(merc) {
        var g = (merc && merc.gender !== undefined && merc.gender !== null) ? String(merc.gender) : '男';
        return (g === '女' || g === '主角-女' || g === '0') ? '女' : '男';
    }

    function firstNonEmptyMercValue(merc, keys) {
        if (!merc) return '';
        for (var i = 0; i < keys.length; i++) {
            var value = merc[keys[i]];
            if (value !== undefined && value !== null && String(value).trim() !== '') return value;
        }
        return '';
    }

    function mercAppearanceValue(merc, type) {
        if (type === 'face') {
            return firstNonEmptyMercValue(merc, ['face', '脸型']) ||
                firstNonEmptyMercValue(merc, ['faceId', 'faceIndex', '脸型ID']);
        }
        return firstNonEmptyMercValue(merc, ['hair', '发型']) ||
            firstNonEmptyMercValue(merc, ['hairId', 'hairIndex', '发型ID']);
    }

    function stripEquipName(value) {
        if (value === undefined || value === null) return '';
        return String(value).split('#', 1)[0];
    }

    function setDressupEquipmentSlot(equipment, slot, value) {
        var slotName = DRESSUP_SLOT_BY_INDEX[Number(slot)] || slot;
        var name = stripEquipName(value);
        if (slotName && name) equipment[slotName] = name;
    }

    function dressupEquipmentFromMerc(merc) {
        var equipment = {};
        var equips = merc && merc.equips ? merc.equips : [];
        for (var i = 0; i < equips.length; i++) {
            var eq = equips[i];
            setDressupEquipmentSlot(equipment, eq.slot, eq.name || eq.raw || eq.displayname);
        }
        var direct = merc && merc.equipment ? merc.equipment : null;
        if (direct) {
            Object.keys(direct).forEach(function(slot) {
                if (!equipment[DRESSUP_SLOT_BY_INDEX[Number(slot)] || slot]) {
                    setDressupEquipmentSlot(equipment, slot, direct[slot]);
                }
            });
        }
        return equipment;
    }

    function dressupSkinCovered(key) {
        return !!(key && _dressupManifest && _dressupManifest.skinKeys && _dressupManifest.skinKeys[key] && _dressupManifest.skinKeys[key].covered);
    }

    function normalizeAppearanceKey(value, type, gender) {
        var raw = value === undefined || value === null ? '' : String(value).trim();
        var appearance = _dressupManifest && _dressupManifest.appearance ? _dressupManifest.appearance : {};
        if (type === 'face') {
            if (/^\d+$/.test(raw)) {
                return (appearance.faceById && appearance.faceById[raw]) ||
                    DRESSUP_FACE_BY_ID_FALLBACK[raw] ||
                    (gender === '女' ? '女变装-基本脸型' : '男变装-基本脸型');
            }
            if (dressupSkinCovered(raw)) return raw;
            return gender === '女' ? '女变装-基本脸型' : '男变装-基本脸型';
        }
        if (!raw || raw === '光头') return '';
        if (/^\d+$/.test(raw)) {
            raw = appearance.hairById && appearance.hairById[raw] ? appearance.hairById[raw] : raw;
        }
        if (dressupSkinCovered(raw)) return raw;
        var alias = DRESSUP_HAIR_COMPAT_ALIASES[raw];
        if (alias && dressupSkinCovered(alias)) return alias;
        return '';
    }

    function dressupAppearanceFromMerc(merc, equipment) {
        var gender = normalizeMercGender(merc);
        var appearance = {};
        var face = normalizeAppearanceKey(mercAppearanceValue(merc, 'face'), 'face', gender);
        var hair = normalizeAppearanceKey(mercAppearanceValue(merc, 'hair'), 'hair', gender);
        var headItem = equipment && equipment.head ? equipment.head : '';
        var item = headItem && _dressupManifest && _dressupManifest.items ? _dressupManifest.items[headItem] : null;
        var helmetSuppressesHair = !!(item && item.helmet === true);
        appearance['脸型'] = face;
        if (hair && hair !== '光头' && !helmetSuppressesHair) appearance['发型'] = hair;
        return appearance;
    }

    function buildMercDressupState(merc, fitFields, zoom, margin, drawFields) {
        if (!_dressupManifest) return null;
        var equipment = dressupEquipmentFromMerc(merc);
        return DressupDollRenderer.buildStateFromEquipment(_dressupManifest, {
            gender: normalizeMercGender(merc),
            equipment: equipment,
            appearance: dressupAppearanceFromMerc(merc, equipment),
            fitFields: fitFields,
            drawFields: drawFields,
            zoom: zoom,
            margin: margin
        });
    }

    function dressupCacheKey(merc, variant) {
        var parts = [variant, normalizeMercGender(merc), mercAppearanceValue(merc, 'face'), mercAppearanceValue(merc, 'hair')];
        var equipment = dressupEquipmentFromMerc(merc);
        Object.keys(equipment).sort().forEach(function(slot) {
            parts.push(slot + ':' + equipment[slot]);
        });
        return parts.join('|');
    }

    function canvasAlphaPixels(canvas) {
        if (!canvas || !canvas.width || !canvas.height) return 0;
        var data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        var count = 0;
        for (var i = 3; i < data.length; i += 4) {
            if (data[i] > 8) count++;
        }
        return count;
    }

    function renderDressupSnapshot(state, width, height, callback) {
        var canvas = document.createElement('canvas');
        canvas.style.width = width + 'px';
        canvas.style.height = height + 'px';
        var renderer = DressupDollRenderer.create(canvas, {
            manifest: _dressupManifest,
            width: width,
            height: height,
            fps: 24
        });
        var attempts = 0;
        function tick() {
            var meta = renderer.render(state);
            var alpha = canvasAlphaPixels(canvas);
            if (alpha > 120 || attempts >= 14) {
                var url = '';
                if (alpha > 120) {
                    try { url = canvas.toDataURL('image/png'); } catch (ignore) {}
                }
                renderer.destroy();
                callback(url, meta);
                return;
            }
            attempts++;
            setTimeout(tick, 80);
        }
        tick();
    }

    function clearDressupPortrait(portrait) {
        if (!portrait) return;
        portrait.classList.add('merc-card-portrait-fallback');
        portrait.classList.remove('merc-dressup-ready');
        var img = portrait.querySelector('img');
        if (img) {
            img.removeAttribute('src');
            img.hidden = true;
        }
    }

    function applyDressupPortrait(portrait, merc, variant) {
        if (!portrait || !merc) {
            clearDressupPortrait(portrait);
            return;
        }
        var token = String(Date.now()) + Math.random();
        portrait._dressupToken = token;
        clearDressupPortrait(portrait);
        ensureDressupManifest().then(function() {
            if (portrait._dressupToken !== token) return;
            var key = dressupCacheKey(merc, variant);
            var cached = _dressupThumbCache[key];
            var img = portrait.querySelector('img');
            if (cached) {
                if (img) {
                    img.hidden = false;
                    img.src = cached;
                }
                portrait.classList.remove('merc-card-portrait-fallback');
                portrait.classList.add('merc-dressup-ready');
                return;
            }
            var size = variant === 'selbar' ? 140 : 112;
            var state = buildMercDressupState(
                merc,
                DRESSUP_HEAD_FIT_FIELDS,
                variant === 'selbar' ? 1.16 : 1.12,
                10,
                DRESSUP_HEAD_DRAW_FIELDS
            );
            if (!state) return;
            renderDressupSnapshot(state, size, size, function(url) {
                if (portrait._dressupToken !== token || !url) return;
                _dressupThumbCache[key] = url;
                if (img) {
                    img.hidden = false;
                    img.src = url;
                }
                portrait.classList.remove('merc-card-portrait-fallback');
                portrait.classList.add('merc-dressup-ready');
            });
        }).catch(function() {
            clearDressupPortrait(portrait);
        });
    }

    function updatePortraitHost(host, merc, variant) {
        if (!host) return;
        var portrait = host.querySelector('.merc-card-portrait');
        if (!portrait) {
            portrait = createPortrait(null, variant);
            if (variant === 'selbar') portrait.classList.add('merc-selbar-portrait');
            if (variant === 'detail') portrait.classList.add('merc-detail-portrait');
            host.appendChild(portrait);
        }
        applyDressupPortrait(portrait, merc, variant);
    }

    function destroyDetailDressup() {
        if (_dressupDetailRenderer) {
            _dressupDetailRenderer.destroy();
            _dressupDetailRenderer = null;
        }
        _dressupDetailCanvas = null;
    }

    function renderDetailDressup(merc) {
        var host = _el.querySelector('#merc-detail-dressup-host');
        if (!host) return;
        destroyDetailDressup();
        host.classList.add('merc-dressup-loading');
        host.textContent = '加载造型...';
        var token = String(Date.now()) + Math.random();
        host._dressupToken = token;
        ensureDressupManifest().then(function() {
            if (host._dressupToken !== token || _currentPage !== 'detail') return;
            host.textContent = '';
            host.classList.remove('merc-dressup-loading');
            var canvas = document.createElement('canvas');
            canvas.className = 'merc-detail-dressup-canvas';
            host.appendChild(canvas);
            _dressupDetailCanvas = canvas;
            _dressupDetailRenderer = DressupDollRenderer.create(canvas, {
                manifest: _dressupManifest,
                width: 360,
                height: 380,
                fps: 24
            });
            var state = buildMercDressupState(merc, DRESSUP_BODY_FIT_FIELDS, 0.92, 16, null);
            if (state) _dressupDetailRenderer.render(state);
        }).catch(function() {
            if (host._dressupToken !== token) return;
            host.classList.remove('merc-dressup-loading');
            host.textContent = '造型素材暂不可用';
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：卡片（列表/雇佣共用骨架）
    // 2 列横版：与战宠卡同高（150px）、双倍宽度，装备 11 槽收进一行；
    // 技能不上卡（数量不可控），看底部详情栏 / 培养页。
    // 操作按钮占满右侧整列（纵向均分），不再挤在右上角。
    // 阵亡佣兵（dead）：出战位换成「复活 · 复活币×1」，不耗体力概念。
    // mode: 'list' | 'hire'
    // ═══════════════════════════════════════════════════════════
    function buildMercCard(merc, mode) {
        var card = document.createElement('div');
        card.className = 'merc-card' +
            (mode === 'list' && merc.deployed ? ' merc-card-deployed' : '') +
            (mode === 'list' && merc.dead ? ' merc-card-dead' : '');
        card.innerHTML = '<span class="merc-card-frame"></span>';

        // ── 左列：头像/名字行 + 装备行 ──
        var main = document.createElement('div');
        main.className = 'merc-card-main';

        var top = document.createElement('div');
        top.className = 'merc-card-top';
        top.appendChild(createPortrait(merc, 'card'));

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
                (merc.dead ? '<span class="merc-badge merc-badge-dead">阵亡</span>' : '') +
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
        main.appendChild(top);

        main.insertAdjacentHTML('beforeend', '<div class="merc-card-seclabel">装备</div>');
        main.appendChild(buildEquipGrid(merc));
        card.appendChild(main);

        // ── 右列：操作（占满卡片高度）──
        var actions = document.createElement('div');
        actions.className = 'merc-card-actions';
        if (mode === 'list') {
            if (merc.dead) {
                actions.appendChild(buildReviveBtn(merc.slotIndex));
            } else {
                var deployBtn = document.createElement('button');
                deployBtn.type = 'button';
                deployBtn.className = 'merc-mini-btn ' + (merc.deployed ? 'merc-mini-btn-rest' : 'merc-mini-btn-deploy');
                deployBtn.textContent = merc.deployed ? '休息' : '出战';
                deployBtn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    onDeploy(merc.slotIndex, this);
                });
                actions.appendChild(deployBtn);
            }

            var dismissBtn = document.createElement('button');
            dismissBtn.type = 'button';
            dismissBtn.className = 'merc-mini-btn merc-mini-btn-dismiss';
            dismissBtn.textContent = '解雇';
            dismissBtn.addEventListener('click', function(e) {
                e.stopPropagation();
                askDismiss(merc.slotIndex);
            });
            actions.appendChild(dismissBtn);
        } else {
            var hireBtn = document.createElement('button');
            hireBtn.type = 'button';
            hireBtn.className = 'merc-mini-btn merc-mini-btn-hire';
            hireBtn.textContent = '雇佣';
            // 禁用时按钮文字直接写原因（仅 title 提示传达不了不可点）
            var blockReason = '';
            var slotsFull = _snapshot && _snapshot.maxSlots > 0 && _hiredMercs.length >= _snapshot.maxSlots;
            if (slotsFull) blockReason = '佣兵已满';
            else if (_snapshot && _snapshot.gold < merc.goldPrice) blockReason = '金币不足';
            else if (_snapshot && merc.kPrice > 0 && _snapshot.kpoint < merc.kPrice) blockReason = 'K点不足';
            if (blockReason) {
                hireBtn.disabled = true;
                hireBtn.textContent = blockReason;
                hireBtn.title = slotsFull
                    ? '佣兵已满 (' + _hiredMercs.length + '/' + _snapshot.maxSlots + ')，请先解雇腾出空位'
                    : blockReason;
            }
            hireBtn.addEventListener('click', function(e) {
                e.stopPropagation();
                onHire(merc.poolIndex, this);
            });
            actions.appendChild(hireBtn);
        }
        card.appendChild(actions);

        // ── 选中（底部详情栏）──
        card.addEventListener('click', function() {
            if (_busy) return;
            if (mode === 'list') selectMerc(merc.slotIndex);
            else selectHire(merc.poolIndex);
        });
        return card;
    }

    // 复活按钮（卡片右列 / 培养页 header 共用构造）
    function buildReviveBtn(slotIndex, hdrStyle) {
        var coins = _snapshot ? (_snapshot.reviveCoins || 0) : 0;
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = hdrStyle ? 'merc-hdr-btn merc-hdr-revive' : 'merc-mini-btn merc-mini-btn-revive';
        btn.textContent = '复活';
        if (coins <= 0) {
            btn.disabled = true;
            btn.title = '复活币不足（商城/战利品可获得）';
        } else {
            btn.title = '消耗 1 枚复活币（持有 ' + coins + '）';
        }
        btn.addEventListener('click', function(e) {
            e.stopPropagation();
            onRevive(slotIndex, this);
        });
        return btn;
    }

    // 装备图标网格 — 11 槽固定渲染 (slot 6-16)，卡片内单行
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
        var iconHtml = (typeof Icons !== 'undefined' && Icons.html)
            ? Icons.html(iconKey, '', ' onerror="this.style.display=\'none\'"')
            : '';
        iconHtml = iconHtml
            ? iconHtml
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

    // 技能图标：manifest 以裸技能名为键（IconBaker 烘焙时剥掉「图标-」linkage 前缀，
    // 与物品图标共用命名空间）。命中 → 烘焙图盖在占位字上（实线样式）；
    // 未命中 / 图片加载失败 → 回退类型首字占位（虚线样式），规格与装备图标一致 32px。
    function buildSkillCell(sk) {
        var cell = document.createElement('div');
        cell.className = 'merc-skill-cell';
        var iconHtml = (typeof Icons !== 'undefined' && Icons.html)
            ? Icons.html(sk.name, 'merc-skill-icon')
            : '';
        cell.innerHTML =
            '<span class="merc-skill-glyph">' + escHtml(String(sk.type || '技').charAt(0)) + '</span>' +
            iconHtml +
            '<span class="merc-skill-level">' + (sk.level || 1) + '</span>';
        if (iconHtml) {
            cell.classList.add('merc-skill-cell-baked');
            var img = cell.querySelector('.merc-skill-icon');
            img.addEventListener('error', function() {
                img.parentNode.removeChild(img);
                cell.classList.remove('merc-skill-cell-baked'); // 露出占位字 + 还原虚线样式
            });
        }
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
    // 选中 + 底部详情栏（对齐战宠 selbar：技能图标流 + 培养入口）
    // ═══════════════════════════════════════════════════════════
    function selectMerc(slotIndex) {
        _selectedSlot = slotIndex;
        applySelection('#merc-grid', slotIndex);
        renderSelbar(_el.querySelector('#merc-selbar'), findMercBySlot(slotIndex), true);
    }

    function selectHire(poolIndex) {
        _selectedPoolIdx = poolIndex;
        applySelection('#merc-hire-grid', poolIndex);
        renderSelbar(_el.querySelector('#merc-hire-selbar'), findHireByPoolIdx(poolIndex), false);
    }

    function applySelection(gridSel, key) {
        var cards = _el.querySelectorAll(gridSel + ' .merc-card');
        for (var i = 0; i < cards.length; i++) {
            cards[i].classList.toggle('merc-card-selected', Number(cards[i].dataset.key) === key);
        }
    }

    function renderSelbar(selbar, merc, withTrain) {
        if (!selbar) return;
        hideAllTooltips();
        if (!merc) {
            updatePortraitHost(selbar.querySelector('.merc-selbar-portrait-host'), null, 'selbar');
            selbar.classList.add('merc-selbar-empty');
            return;
        }
        selbar.classList.remove('merc-selbar-empty');
        updatePortraitHost(selbar.querySelector('.merc-selbar-portrait-host'), merc, 'selbar');
        selbar.querySelector('.merc-selbar-name').textContent = merc.name;
        selbar.querySelector('.merc-selbar-lv').textContent = 'Lv.' + merc.level;
        var chips = selbar.querySelector('.merc-selbar-chips');
        chips.innerHTML =
            '<span class="merc-meta-chip">' + escHtml(merc.gender || '') + '</span>' +
            (merc.dead ? '<span class="merc-meta-chip merc-meta-dead">阵亡</span>' : '') +
            (merc.deployed ? '<span class="merc-meta-chip merc-meta-deployed">出战中</span>' : '');

        // 技能图标流（全量，区域内换行滚动）
        var flow = selbar.querySelector('.merc-selbar-skills');
        flow.innerHTML = '';
        var skills = merc.skills;
        if (skills && skills.length) {
            for (var i = 0; i < skills.length; i++) flow.appendChild(buildSkillCell(skills[i]));
        } else {
            flow.innerHTML = '<span class="merc-skill-flow-empty">' +
                (skills ? '暂无技能' : '技能情报暂不可用') + '</span>';
        }

        if (withTrain) {
            var trainBtn = selbar.querySelector('.merc-act-train');
            if (trainBtn) trainBtn.disabled = false;
        }
    }

    function selbarHtml(id, withTrain) {
        return '<div class="merc-selbar merc-selbar-empty" id="' + id + '">' +
            '<span class="merc-selbar-hint">▾ 选择一名佣兵查看技能详情</span>' +
            '<span class="merc-selbar-portrait-host"></span>' +
            '<div class="merc-selbar-main">' +
                '<div class="merc-selbar-titlerow">' +
                    '<span class="merc-selbar-name"></span>' +
                    '<span class="merc-selbar-lv"></span>' +
                    '<span class="merc-selbar-chips merc-detail-meta"></span>' +
                '</div>' +
                '<div class="merc-selbar-skill-label">技能</div>' +
            '</div>' +
            '<div class="merc-selbar-skills"></div>' +
            (withTrain
                ? '<div class="merc-selbar-actions">' +
                      '<button class="merc-act-btn merc-act-train" type="button" data-audio-cue="confirm" title="性格特质 / 技能详情 / 装备调配">' +
                          '<span class="merc-act-ico">⚙</span><span>培养</span>' +
                      '</button>' +
                  '</div>'
                : '') +
        '</div>';
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
            _selectedSlot = -1;
            renderSelbar(_el.querySelector('#merc-selbar'), null, true);
            return;
        }
        if (emptyEl) emptyEl.hidden = true;

        var animate = _firstListRender;
        _firstListRender = false;
        _hiredMercs.forEach(function(merc, i) {
            var card = buildMercCard(merc, 'list');
            card.dataset.key = merc.slotIndex;
            if (animate) card.style.animationDelay = Math.min(i * 0.03, 0.36) + 's';
            else card.style.animation = 'none';
            grid.appendChild(card);
        });

        // 默认选中：保留旧选中（若仍在），否则选首个
        if (!findMercBySlot(_selectedSlot)) _selectedSlot = _hiredMercs[0].slotIndex;
        selectMerc(_selectedSlot);
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染：雇佣页（无缝滚动：reset 全量渲染 / append 增量追加）
    // ═══════════════════════════════════════════════════════════
    function renderHirePage() {
        hideAllTooltips();
        var grid = _el.querySelector('#merc-hire-grid');
        var emptyEl = _el.querySelector('#merc-hire-empty');
        if (!grid) return;

        grid.innerHTML = '';
        updateResources();

        if (_hireData.length === 0) {
            if (emptyEl) emptyEl.hidden = false;
            _selectedPoolIdx = -1;
            renderSelbar(_el.querySelector('#merc-hire-selbar'), null, false);
            return;
        }
        if (emptyEl) emptyEl.hidden = true;

        _hireData.forEach(function(merc, i) {
            var card = buildMercCard(merc, 'hire');
            card.dataset.key = merc.poolIndex;
            card.style.animationDelay = Math.min(i * 0.03, 0.36) + 's';
            grid.appendChild(card);
        });

        if (!findHireByPoolIdx(_selectedPoolIdx)) _selectedPoolIdx = _hireData[0].poolIndex;
        selectHire(_selectedPoolIdx);
    }

    function appendHireCards(items) {
        var grid = _el.querySelector('#merc-hire-grid');
        if (!grid || !items.length) return;
        for (var i = 0; i < items.length; i++) {
            _hireData.push(items[i]);
            var card = buildMercCard(items[i], 'hire');
            card.dataset.key = items[i].poolIndex;
            card.style.animationDelay = Math.min(i * 0.03, 0.24) + 's';
            grid.appendChild(card);
        }
        if (!findHireByPoolIdx(_selectedPoolIdx)) {
            _selectedPoolIdx = _hireData[0].poolIndex;
            selectHire(_selectedPoolIdx);
        }
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
        updatePortraitHost(_el.querySelector('#merc-detail-portrait-host'), merc, 'detail');
        renderDetailDressup(merc);
        _el.querySelector('#merc-detail-title').textContent = merc.name;
        var meta = _el.querySelector('#merc-detail-meta');
        meta.innerHTML =
            '<span class="merc-meta-chip">Lv.' + merc.level + '</span>' +
            '<span class="merc-meta-chip">' + escHtml(merc.gender || '') + '</span>' +
            (merc.height ? '<span class="merc-meta-chip">' + merc.height + 'cm</span>' : '') +
            (merc.dead ? '<span class="merc-meta-chip merc-meta-dead">阵亡</span>' : '') +
            (merc.deployed ? '<span class="merc-meta-chip merc-meta-deployed">出战中</span>' : '');

        // 出战钮三态：阵亡 → 复活（复活币门控）；否则 出战/休息
        var deployBtn = _el.querySelector('#merc-detail-deploy');
        deployBtn.classList.toggle('merc-hdr-revive', !!merc.dead);
        if (merc.dead) {
            deployBtn.textContent = '复活';
            deployBtn.classList.remove('merc-hdr-rest');
            var coins = _snapshot ? (_snapshot.reviveCoins || 0) : 0;
            deployBtn.disabled = coins <= 0;
            deployBtn.title = coins <= 0 ? '复活币不足（商城/战利品可获得）' : '消耗 1 枚复活币（持有 ' + coins + '）';
        } else {
            deployBtn.disabled = false;
            deployBtn.title = '';
            deployBtn.textContent = merc.deployed ? '休息' : '出战';
            deployBtn.classList.toggle('merc-hdr-rest', !!merc.deployed);
        }

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

    function createPortrait(merc, variant) {
        var portrait = document.createElement('div');
        portrait.className = 'merc-card-portrait merc-card-portrait-fallback merc-dressup-portrait';
        portrait.innerHTML = '<img alt="佣兵造型" hidden>';
        var img = portrait.querySelector('img');
        img.addEventListener('load', function() {
            if (img.getAttribute('src')) {
                portrait.classList.remove('merc-card-portrait-fallback');
                portrait.classList.add('merc-dressup-ready');
            }
        });
        img.addEventListener('error', function() { clearDressupPortrait(portrait); });
        if (merc) applyDressupPortrait(portrait, merc, variant || 'card');
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
        _el.className = 'team-child team-merc-child';
        // 固定 1024×576 设计画布 + 整体缩放（照搬 pet/task scale-shell 机制），
        // 保证与战宠子视图在任意视口下缩放行为一致
        _el.innerHTML =
            '<div class="merc-scale-shell">' +
            '<div class="merc-panel">' +
            '<div class="merc-toast" id="merc-toast"></div>' +

            // ═══════════════════════════════════════
            // 页面 1: 佣兵管理
            // header 标题位让给战队 tab 条（.team-tabs-slot），徽标/资源/关闭保留
            // ═══════════════════════════════════════
            '<div class="merc-page" id="merc-page-list">' +
                '<div class="merc-page-header">' +
                    '<span class="merc-title-mark"></span>' +
                    '<h1 class="merc-page-title">佣兵管理</h1>' +
                    '<div class="team-tabs-slot"></div>' +
                    '<div class="merc-page-header-spacer"></div>' +
                    resourcesHtml() +
                    '<button class="merc-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="cancel">✕</button>' +
                '</div>' +
                '<div class="merc-toolbar">' +
                    '<span class="merc-status-item">出战 <strong id="merc-deploy-count">0</strong></span>' +
                    '<span class="merc-status-item">佣兵栏 <strong id="merc-slot-count">0/0</strong></span>' +
                    '<span class="merc-status-item" title="阵亡佣兵消耗 1 枚复活币复活">复活币 <strong id="merc-revive-coins">0</strong></span>' +
                    '<div class="merc-toolbar-spacer"></div>' +
                    '<button class="merc-btn-primary" type="button" id="merc-goto-hire" data-audio-cue="confirm">＋ 雇佣佣兵</button>' +
                '</div>' +
                '<div class="merc-grid-wrap">' +
                    '<div class="merc-grid" id="merc-grid"></div>' +
                    '<div class="merc-list-empty" id="merc-list-empty" hidden>' +
                        '<span class="merc-empty-mark"></span>' +
                        '<span>暂无佣兵 · 点击右上「雇佣佣兵」</span>' +
                    '</div>' +
                '</div>' +
                selbarHtml('merc-selbar', true) +
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
                // 等级快速定位：池按等级升序，chip 跳到对应区间起点（保持无缝下滑）
                '<div class="merc-toolbar merc-hire-toolbar">' +
                    '<span class="merc-status-item">等级定位</span>' +
                    '<div class="merc-lvl-chips" id="merc-lvl-chips">' +
                        '<button class="merc-lvl-chip merc-lvl-chip-active" type="button" data-min="0">全部</button>' +
                        '<button class="merc-lvl-chip" type="button" data-min="20">Lv.20+</button>' +
                        '<button class="merc-lvl-chip" type="button" data-min="40">Lv.40+</button>' +
                        '<button class="merc-lvl-chip" type="button" data-min="60">Lv.60+</button>' +
                        '<button class="merc-lvl-chip" type="button" data-min="80">Lv.80+</button>' +
                    '</div>' +
                    '<div class="merc-toolbar-spacer"></div>' +
                    '<span class="merc-status-item">按等级升序</span>' +
                '</div>' +
                // 无缝下滑：滚动触底自动加载下一页（哨兵行提示进度），无分页按钮
                '<div class="merc-page-body" id="merc-hire-body">' +
                    '<div class="merc-hire-grid" id="merc-hire-grid"></div>' +
                    '<div class="merc-hire-more" id="merc-hire-more" hidden></div>' +
                    '<div class="merc-hire-empty" id="merc-hire-empty" hidden>暂时没有可雇佣的佣兵</div>' +
                '</div>' +
                selbarHtml('merc-hire-selbar', false) +
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
                    '<div class="merc-detail-overview">' +
                        '<div class="merc-section merc-dressup-section">' +
                            '<h3 class="merc-section-title">造型预览</h3>' +
                            '<div class="merc-detail-dressup-host" id="merc-detail-dressup-host"></div>' +
                        '</div>' +
                        '<div class="merc-section merc-traits-section">' +
                            '<h3 class="merc-section-title">性格特质</h3>' +
                            '<div class="merc-traits-grid" id="merc-traits-grid"></div>' +
                        '</div>' +
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
            '</div>' +

            '</div>' + // .merc-panel
            '</div>';  // .merc-scale-shell

        _pageList   = _el.querySelector('#merc-page-list');
        _pageHire   = _el.querySelector('#merc-page-hire');
        _pageDetail = _el.querySelector('#merc-page-detail');

        // 选中栏 / 培养页头像（克隆卡片头像组件）
        var selbars = _el.querySelectorAll('.merc-selbar-portrait-host');
        for (var p = 0; p < selbars.length; p++) {
            var sp = createPortrait();
            sp.classList.add('merc-selbar-portrait');
            selbars[p].appendChild(sp);
        }
        var detailPortrait = createPortrait();
        detailPortrait.classList.add('merc-detail-portrait');
        _el.querySelector('#merc-detail-portrait-host').appendChild(detailPortrait);

        // 关闭按钮
        _el.querySelector('.merc-close-btn').addEventListener('click', requestClose);

        // 列表页 → 雇佣页
        _el.querySelector('#merc-goto-hire').addEventListener('click', function() {
            navigateTo('hire');
        });

        // 选中栏「培养」入口
        _el.querySelector('#merc-selbar .merc-act-train').addEventListener('click', function() {
            if (_selectedSlot >= 0 && findMercBySlot(_selectedSlot)) {
                navigateTo('detail', { slotIndex: _selectedSlot });
            }
        });

        // 返回列表（雇佣页/培养页共用）
        var backBtns = _el.querySelectorAll('.merc-page-back');
        for (var b = 0; b < backBtns.length; b++) {
            backBtns[b].addEventListener('click', function() { navigateTo('list'); });
        }

        // 培养页操作（出战钮按佣兵状态分流：阵亡 → 复活，否则出战/休息）
        _el.querySelector('#merc-detail-deploy').addEventListener('click', function() {
            if (_detailSlot < 0) return;
            var m = findMercBySlot(_detailSlot);
            if (m && m.dead) onRevive(_detailSlot, this);
            else onDeploy(_detailSlot, this);
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

        // 无缝下滑：雇佣页滚动触底加载下一页
        _el.querySelector('#merc-hire-body').addEventListener('scroll', onHireScroll);

        // 等级定位 chip
        var lvlChips = _el.querySelectorAll('.merc-lvl-chip');
        for (var lc = 0; lc < lvlChips.length; lc++) {
            lvlChips[lc].addEventListener('click', function() {
                if (_busy || _currentPage !== 'hire') return;
                var min = Number(this.dataset.min) || 0;
                if (min === _hireMinLevel) return;
                _hireMinLevel = min;
                updateLevelChips();
                resetHireList();
            });
        }

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
        _selectedSlot = -1;
        _selectedPoolIdx = -1;
        _confirmSlot = -1;
        _firstListRender = true;
        var overlay = _el.querySelector('#merc-confirm-overlay');
        if (overlay) overlay.hidden = true;
        _currentPage = 'list';
        _pageList.hidden = false;
        _pageHire.hidden = true;
        _pageDetail.hidden = true;
        updateFitScale();
        bindScaleWatcher();
        requestSnapshot();
    }

    // ═══════════════════════════════════════════════════════════
    // 缩放（设计 1024×576 → 容器自适应；照搬 pet/task panel）
    // ═══════════════════════════════════════════════════════════
    function scheduleScaleUpdate() {
        if (typeof requestAnimationFrame === 'function') requestAnimationFrame(updateFitScale);
        else setTimeout(updateFitScale, 0);
    }
    function updateFitScale() {
        if (!_el) return;
        var width = _el.clientWidth || _el.offsetWidth || 0;
        var height = _el.clientHeight || _el.offsetHeight || 0;
        if (!width || !height) return;
        var scale = Math.min(width / DESIGN_W, height / DESIGN_H);
        if (!isFinite(scale) || scale <= 0) scale = 1;
        _el.style.setProperty('--merc-scale', scale.toFixed(4));
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
        if (_resizeObserver) { _resizeObserver.disconnect(); _resizeObserver = null; }
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
        _toastTimer = null;
        // timer 被取消后 visible 类不会自动摘除，必须手动清，否则 toast 跨会话残留
        var toast = _el ? _el.querySelector('#merc-toast') : null;
        if (toast) toast.classList.remove('visible');
        _pendingReq = {};
        _busy = false;
        _ttCache = {};
        _ttHoverKey = null;
        _confirmSlot = -1;
        destroyDetailDressup();
        unbindScaleWatcher();
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
