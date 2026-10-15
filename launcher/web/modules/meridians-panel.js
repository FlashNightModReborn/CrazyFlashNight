/**
 * MeridiansPanel — 经脉系统 Web 面板。
 *
 * 数据权威在 AS2（MeridianPanelService）：配置、点亮集、K点余额、情报持有全部经
 * meridiansState 回包；点亮经 meridianLight 提交，Web 只做呈现与意图收集，
 * 不本地判定价格/门槛/结果（见 workbench-ui-system §1）。
 */
var MeridiansPanel = (function() {
    'use strict';

    var DESIGN_WIDTH = 1404;
    var DESIGN_HEIGHT = 790;

    var _el, _refs;
    var _reqSeq = 0;
    var _pending = {};
    var _meridians = [];
    var _lit = {};
    var _kpoint = 0;
    var _infoValues = {};
    var _selectedIndex = 0;
    var _busyNodes = {};
    var _scaleHandle = null;

    Panels.register('meridians', {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        onRequestClose: doClose
    });

    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'meridians') return;
        var request = _pending[data.callId];
        if (!request) return;
        delete _pending[data.callId];
        request.callback(data);
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'meridians-panel';
        _el.setAttribute('data-workbench-skin', 'archive');
        _el.innerHTML =
            '<div class="mer-shell">' +
                '<header class="mer-header">' +
                    '<div class="mer-heading">' +
                        '<div class="mer-title">经脉</div>' +
                        '<div class="mer-subtitle">体内 θ-域耦合通道 · 以情报为引，K 点贯注</div>' +
                    '</div>' +
                    '<div class="mer-total-box">' +
                        '<div class="mer-total-label">经脉内力</div>' +
                        '<div class="mer-total-value">+0</div>' +
                    '</div>' +
                    '<div class="mer-kpoint-box">' +
                        '<div class="mer-kpoint-label">K点</div>' +
                        '<div class="mer-kpoint-value">0</div>' +
                    '</div>' +
                    '<button class="mer-close-btn" type="button" title="关闭" aria-label="关闭"></button>' +
                '</header>' +
                '<aside class="mer-catalog" aria-label="经脉目录">' +
                    '<div class="mer-catalog-list"></div>' +
                '</aside>' +
                '<main class="mer-reader">' +
                    '<div class="mer-status">正在读取经脉状态…</div>' +
                    '<div class="mer-meridian-head">' +
                        '<div class="mer-meridian-name"></div>' +
                        '<div class="mer-meridian-desc"></div>' +
                        '<div class="mer-require-list"></div>' +
                    '</div>' +
                    '<div class="mer-node-list" role="list"></div>' +
                '</main>' +
                '<footer class="mer-footer">' +
                    '<div class="mer-error" aria-live="polite"></div>' +
                '</footer>' +
            '</div>';
        collectRefs();
        return _el;
    }

    function collectRefs() {
        _refs = {
            shell: _el.querySelector('.mer-shell'),
            status: _el.querySelector('.mer-status'),
            totalValue: _el.querySelector('.mer-total-value'),
            kpointValue: _el.querySelector('.mer-kpoint-value'),
            catalogList: _el.querySelector('.mer-catalog-list'),
            meridianName: _el.querySelector('.mer-meridian-name'),
            meridianDesc: _el.querySelector('.mer-meridian-desc'),
            requireList: _el.querySelector('.mer-require-list'),
            nodeList: _el.querySelector('.mer-node-list'),
            error: _el.querySelector('.mer-error'),
            closeBtn: _el.querySelector('.mer-close-btn')
        };
        _refs.closeBtn.addEventListener('click', doClose);
    }

    function onOpen(el, initData) {
        _meridians = [];
        _lit = {};
        _selectedIndex = 0;
        _busyNodes = {};
        showStatus('正在读取经脉状态…');
        showError('');

        initData = initData || {};
        _scaleHandle = (typeof PanelScale !== 'undefined' && PanelScale && PanelScale.attach)
            ? PanelScale.attach(_refs.shell, DESIGN_WIDTH, DESIGN_HEIGHT)
            : null;
        requestState();
    }

    function onClose() {
        if (_scaleHandle && _scaleHandle.detach) _scaleHandle.detach();
        _scaleHandle = null;
        _pending = {};
    }

    function doClose() {
        if (window.BootstrapAudio) window.BootstrapAudio.cue('back');
        Panels.close();
    }

    // ========== 与 AS2 权威往返 ==========

    function sendRequest(cmd, payload, cb) {
        var callId = 'mer-' + (++_reqSeq);
        _pending[callId] = {
            cmd: String(cmd || ''),
            callback: typeof cb === 'function' ? cb : function() {}
        };
        var msg = payload || {};
        msg.type = 'panel';
        msg.panel = 'meridians';
        msg.cmd = cmd;
        msg.callId = callId;
        Bridge.send(msg);
    }

    function requestState() {
        sendRequest('state', {}, function(resp) {
            if (!resp || resp.success !== true) {
                showStatus('经脉数据暂不可用，稍后再试。');
                return;
            }
            applyState(resp);
            showStatus('');
        });
    }

    function applyState(resp) {
        _meridians = resp.meridians || [];
        _lit = resp.lit || {};
        _kpoint = Number(resp.kpoint) || 0;
        _infoValues = resp.infoValues || {};
        if (_selectedIndex >= _meridians.length) _selectedIndex = 0;
        renderAll();
    }

    function lightNode(nodeId) {
        if (_busyNodes[nodeId]) return;
        _busyNodes[nodeId] = true;
        sendRequest('light', { nodeId: nodeId }, function(resp) {
            delete _busyNodes[nodeId];
            if (resp && resp.applied === true) {
                _lit[nodeId] = true;
                if (typeof resp.totalInnerPower === 'number') {
                    _refs.totalValue.textContent = '+' + formatNumber(resp.totalInnerPower);
                }
                _kpoint = Number(resp.kpoint);
                if (resp.savePending === true) {
                    showError('已贯通，存档写入结果未确认；请勿重复点亮，稍后重开面板核对。');
                } else {
                    showError('');
                }
                renderAll();
                return;
            }
            showError(lightFailureText(resp));
            renderAll();
        });
    }

    function lightFailureText(resp) {
        if (!resp) return '经脉贯注没有回音，请重试。';
        var code = String(resp.error || '');
        if (code === 'insufficient_funds') return 'K点不足，无法贯注此节点。';
        if (code === 'info_missing') {
            var names = resp.missingInfo || [];
            return names.length ? '仍缺情报：' + names.join('、') : '情报尚未集齐，此脉未解锁。';
        }
        if (code === 'already_lit') return '此节点已贯通。';
        if (code === 'save_unavailable' || code === 'save_pending') return '存档系统暂不可用，本次贯注未生效。';
        if (code === 'config_unavailable' || code === 'node_unknown') return '经脉数据暂不可用。';
        return '贯注失败，请稍后重试。';
    }

    // ========== 渲染 ==========

    function renderAll() {
        renderHeaderNumbers();
        renderCatalog();
        renderReader();
    }

    function renderHeaderNumbers() {
        var total = 0;
        for (var m = 0; m < _meridians.length; m++) {
            var nodes = _meridians[m].nodes || [];
            for (var n = 0; n < nodes.length; n++) {
                if (_lit[nodes[n].id]) total += Number(nodes[n].innerPower) || 0;
            }
        }
        _refs.totalValue.textContent = '+' + formatNumber(total);
        _refs.kpointValue.textContent = formatNumber(_kpoint);
    }

    function renderCatalog() {
        _refs.catalogList.innerHTML = '';
        for (var i = 0; i < _meridians.length; i++) {
            _refs.catalogList.appendChild(buildCatalogItem(_meridians[i], i));
        }
    }

    function buildCatalogItem(meridian, index) {
        var item = document.createElement('button');
        item.type = 'button';
        item.className = 'mer-catalog-item' + (index === _selectedIndex ? ' active' : '');
        var unlocked = meridianUnlocked(meridian);
        var litCount = 0;
        var nodes = meridian.nodes || [];
        for (var n = 0; n < nodes.length; n++) {
            if (_lit[nodes[n].id]) litCount++;
        }
        var head = document.createElement('div');
        head.className = 'mer-catalog-name';
        head.textContent = meridian.name || meridian.id;
        var meta = document.createElement('div');
        meta.className = 'mer-catalog-meta';
        meta.textContent = unlocked ? litCount + '/' + nodes.length : '未解锁';
        if (!unlocked) meta.className += ' is-locked';
        item.appendChild(head);
        item.appendChild(meta);
        item.addEventListener('click', function() {
            _selectedIndex = index;
            renderAll();
        });
        return item;
    }

    function renderReader() {
        var meridian = _meridians[_selectedIndex];
        if (!meridian) {
            _refs.meridianName.textContent = '';
            _refs.meridianDesc.textContent = '';
            _refs.requireList.innerHTML = '';
            _refs.nodeList.innerHTML = '';
            if (!_refs.status.textContent) showStatus('经脉数据为空。');
            return;
        }
        _refs.meridianName.textContent = meridian.name || meridian.id;
        _refs.meridianDesc.textContent = meridian.desc || '';
        renderRequireList(meridian);
        _refs.nodeList.innerHTML = '';
        var nodes = meridian.nodes || [];
        for (var n = 0; n < nodes.length; n++) {
            _refs.nodeList.appendChild(buildNodeCard(meridian, nodes[n]));
        }
    }

    function renderRequireList(meridian) {
        _refs.requireList.innerHTML = '';
        var required = meridian.requiredInfo || [];
        for (var r = 0; r < required.length; r++) {
            var chip = document.createElement('span');
            var held = (Number(_infoValues[required[r]]) || 0) > 0;
            chip.className = 'mer-require-chip' + (held ? ' is-held' : ' is-missing');
            chip.textContent = (held ? '✓ ' : '✗ ') + required[r];
            _refs.requireList.appendChild(chip);
        }
    }

    function buildNodeCard(meridian, node) {
        var card = document.createElement('div');
        card.className = 'mer-node';
        card.setAttribute('role', 'listitem');
        var lit = !!_lit[node.id];
        var unlocked = meridianUnlocked(meridian);
        var affordable = _kpoint >= (Number(node.cost) || 0);
        if (lit) card.className += ' is-lit';
        else if (!unlocked) card.className += ' is-locked';
        else if (!affordable) card.className += ' is-poor';

        var name = document.createElement('div');
        name.className = 'mer-node-name';
        name.textContent = node.name || node.id;
        var gain = document.createElement('div');
        gain.className = 'mer-node-gain';
        gain.textContent = '内力 +' + formatNumber(Number(node.innerPower) || 0);
        var cost = document.createElement('div');
        cost.className = 'mer-node-cost';
        cost.textContent = formatNumber(Number(node.cost) || 0) + ' K';
        card.appendChild(name);
        card.appendChild(gain);
        card.appendChild(cost);

        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'mer-node-btn';
        if (lit) {
            btn.textContent = '已贯通';
            btn.disabled = true;
        } else if (_busyNodes[node.id]) {
            btn.textContent = '贯注中…';
            btn.disabled = true;
        } else if (!unlocked) {
            btn.textContent = '情报未集齐';
            btn.disabled = true;
        } else if (!affordable) {
            btn.textContent = 'K点不足';
            btn.disabled = true;
        } else {
            btn.textContent = '贯注';
            btn.addEventListener('click', function() { lightNode(node.id); });
        }
        card.appendChild(btn);
        return card;
    }

    function meridianUnlocked(meridian) {
        var required = meridian.requiredInfo || [];
        for (var r = 0; r < required.length; r++) {
            if (!((Number(_infoValues[required[r]]) || 0) > 0)) return false;
        }
        return true;
    }

    function formatNumber(value) {
        var n = Math.round(Number(value) || 0);
        var text = String(Math.abs(n));
        var out = '';
        while (text.length > 3) {
            out = ',' + text.slice(-3) + out;
            text = text.slice(0, -3);
        }
        return (n < 0 ? '-' : '') + text + out;
    }

    function showStatus(text) {
        _refs.status.textContent = text;
        _refs.status.hidden = !text;
    }

    function showError(text) {
        _refs.error.textContent = text;
        _refs.error.hidden = !text;
    }

    // ========== 键盘 ==========
    // Escape / 遮罩点击由宿主经 Panels onRequestClose 统一下发（panels.js 生命周期合同），
    // 面板内不重复监听 keydown，避免双重关闭。

    return {
        applyStateForTest: function(resp) { applyState(resp); },
        getStateForTest: function() {
            return { meridians: _meridians, lit: _lit, kpoint: _kpoint, selectedIndex: _selectedIndex };
        }
    };
})();
