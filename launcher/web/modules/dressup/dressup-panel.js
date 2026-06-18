/**
 * DressupPanel — Web paper-doll preview panel for dialogue portrait migration.
 *
 * Runtime callers can pass initData.equipment, initData.keyMap, initData.appearance,
 * and initData.gender. Dev mode exposes local selectors backed by the baked manifest.
 */
var DressupPanel = (function() {
    'use strict';

    var MANIFEST_URL = 'assets/dressup/manifest.json';
    var CONTROL_USES = {
        upper: '上装装备',
        lower: '下装装备',
        hands: '手部装备',
        feet: '脚部装备',
        head: '头部装备',
        blade: '刀',
        spear: '长枪',
        pistol: '手枪',
        grenade: '手雷'
    };
    var CONTROL_LABELS = {
        upper: '上装',
        lower: '下装',
        hands: '手部',
        feet: '脚部',
        head: '头部',
        blade: '刀',
        spear: '长枪',
        pistol: '手枪',
        grenade: '手雷'
    };
    var CONTROL_ORDER = ['upper', 'lower', 'hands', 'feet', 'head', 'blade', 'spear', 'pistol', 'grenade'];
    var DEFAULT_APPEARANCE = {};

    var _el = null;
    var _refs = null;
    var _manifestPromise = null;
    var _manifestPromiseUrl = '';
    var _manifest = null;
    var _renderer = null;
    var _currentInitData = {};
    var _devMode = false;
    var _controlsReady = false;
    var _resizeHandler = null;

    Panels.register('dressup', {
        create: createDOM,
        onOpen: onOpen,
        onClose: onClose,
        onRequestClose: requestClose
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'dressup-panel';
        _el.innerHTML =
            '<div class="dressup-shell">' +
                '<header class="dressup-header">' +
                    '<div class="dressup-heading">' +
                        '<div class="dressup-title">纸娃娃预览</div>' +
                        '<div class="dressup-subtitle">离线烘焙素材 · Canvas 2D 复刻</div>' +
                    '</div>' +
                    '<div class="dressup-header-status"></div>' +
                    '<button class="dressup-close-btn" type="button" title="关闭" aria-label="关闭">×</button>' +
                '</header>' +
                '<main class="dressup-main">' +
                    '<section class="dressup-stage" aria-label="纸娃娃画布">' +
                        '<canvas class="dressup-canvas"></canvas>' +
                    '</section>' +
                    '<aside class="dressup-side">' +
                        '<div class="dressup-controls">' +
                            '<label class="dressup-field dressup-gender-field">性别<select class="dressup-gender">' +
                                '<option value="男">男</option>' +
                                '<option value="女">女</option>' +
                            '</select></label>' +
                            '<div class="dressup-equipment-grid"></div>' +
                            '<div class="dressup-actions">' +
                                '<button class="dressup-animated-btn" type="button">动效样本</button>' +
                                '<button class="dressup-reset-btn" type="button">默认样本</button>' +
                            '</div>' +
                        '</div>' +
                        '<pre class="dressup-status">加载中...</pre>' +
                    '</aside>' +
                '</main>' +
            '</div>';

        _refs = {
            shell: _el.querySelector('.dressup-shell'),
            canvas: _el.querySelector('.dressup-canvas'),
            headerStatus: _el.querySelector('.dressup-header-status'),
            status: _el.querySelector('.dressup-status'),
            controls: _el.querySelector('.dressup-controls'),
            equipmentGrid: _el.querySelector('.dressup-equipment-grid'),
            gender: _el.querySelector('.dressup-gender'),
            animatedBtn: _el.querySelector('.dressup-animated-btn'),
            resetBtn: _el.querySelector('.dressup-reset-btn'),
            closeBtn: _el.querySelector('.dressup-close-btn'),
            selects: {}
        };

        CONTROL_ORDER.forEach(function(key) {
            var label = document.createElement('label');
            label.className = 'dressup-field';
            label.textContent = CONTROL_LABELS[key];
            var select = document.createElement('select');
            select.className = 'dressup-equip-select';
            select.setAttribute('data-slot', key);
            label.appendChild(select);
            _refs.equipmentGrid.appendChild(label);
            _refs.selects[key] = select;
            select.addEventListener('change', renderFromControls);
        });

        _refs.gender.addEventListener('change', renderFromControls);
        _refs.animatedBtn.addEventListener('click', function() {
            selectByValue(_refs.selects.blade, '异形女王毒刺') || selectByValue(_refs.selects.blade, '异形毒刺');
            renderFromControls();
        });
        _refs.resetBtn.addEventListener('click', function() {
            applyDefaultSelections();
            renderFromControls();
        });
        _refs.closeBtn.addEventListener('click', requestClose);

        return _el;
    }

    function onOpen(el, initData) {
        _currentInitData = initData || {};
        _devMode = _currentInitData.mode === 'dev' || _currentInitData.debug === true;
        _refs.controls.hidden = !_devMode;
        _refs.headerStatus.textContent = _devMode ? 'DEV' : 'RUNTIME';
        _refs.status.textContent = '加载 dressup manifest...';
        _resizeHandler = function() { renderCurrent(); };
        window.addEventListener('resize', _resizeHandler);

        loadManifest().then(function(manifest) {
            if (!_el || _el.style.display === 'none') return;
            _manifest = manifest;
            ensureControls();
            if (_renderer) _renderer.destroy();
            _renderer = DressupDollRenderer.create(_refs.canvas, {
                manifest: _manifest,
                zoom: 0.9,
                debugPlaceholders: _currentInitData.debugPlaceholders === true
            });
            if (_devMode) {
                applyInitSelections(_currentInitData);
            }
            renderCurrent();
        }).catch(function(error) {
            showError(error);
        });
    }

    function onClose() {
        if (_resizeHandler) window.removeEventListener('resize', _resizeHandler);
        _resizeHandler = null;
        if (_renderer) {
            _renderer.destroy();
            _renderer = null;
        }
    }

    function requestClose() {
        Panels.close();
        if (typeof Bridge !== 'undefined' && Bridge && Bridge.send) {
            Bridge.send({ type: 'panel', cmd: 'close', panel: 'dressup' });
        }
    }

    function loadManifest() {
        var url = _currentInitData.manifestUrl || MANIFEST_URL;
        if (!_manifestPromise || _manifestPromiseUrl !== url) {
            _manifestPromiseUrl = url;
            _manifestPromise = DressupDollRenderer.loadManifest(url);
        }
        return _manifestPromise;
    }

    function ensureControls() {
        if (_controlsReady || !_manifest) return;
        var byUse = DressupDollRenderer.collectItemsByUse(_manifest);
        CONTROL_ORDER.forEach(function(key) {
            fillSelect(_refs.selects[key], byUse[CONTROL_USES[key]]);
        });
        _controlsReady = true;
    }

    function fillSelect(select, names) {
        select.innerHTML = '';
        var empty = document.createElement('option');
        empty.value = '';
        empty.textContent = '(none)';
        select.appendChild(empty);
        (names || []).forEach(function(name) {
            var option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            select.appendChild(option);
        });
    }

    function applyDefaultSelections() {
        _refs.gender.value = '男';
        CONTROL_ORDER.forEach(function(key) {
            var select = _refs.selects[key];
            select.selectedIndex = select.options.length > 1 ? 1 : 0;
        });
    }

    function clearSelections() {
        CONTROL_ORDER.forEach(function(key) {
            var select = _refs.selects[key];
            if (select) select.selectedIndex = 0;
        });
    }

    function applyInitSelections(initData) {
        var equipment = initData.equipment || {};
        if (!hasSelectedEquipment(equipment)) applyDefaultSelections();
        if (initData.gender) _refs.gender.value = initData.gender;
        Object.keys(equipment).forEach(function(slot) {
            if (_refs.selects[slot]) selectByValue(_refs.selects[slot], equipment[slot]);
        });
        if (initData.skinKey) {
            clearSelections();
        } else if (initData.sample === 'animated') {
            selectByValue(_refs.selects.blade, '异形女王毒刺') || selectByValue(_refs.selects.blade, '异形毒刺');
        } else if (initData.sample === 'nested') {
            applyDefaultSelections();
            selectByValue(_refs.selects.blade, '3XF电棍');
        } else if (initData.sample === 'nested-a') {
            clearSelections();
            selectByValue(_refs.selects.upper, 'A兵团精致战术背心');
        }
    }

    function hasSelectedEquipment(equipment) {
        return equipment && Object.keys(equipment).some(function(key) { return !!equipment[key]; });
    }

    function selectByValue(select, value) {
        if (!select || !value) return false;
        for (var i = 0; i < select.options.length; i++) {
            if (select.options[i].value === value) {
                select.selectedIndex = i;
                return true;
            }
        }
        return false;
    }

    function equipmentFromControls() {
        var result = {};
        CONTROL_ORDER.forEach(function(key) {
            var value = _refs.selects[key].value;
            if (value) result[key] = value;
        });
        return result;
    }

    function buildRuntimeState() {
        var initData = _currentInitData || {};
        return DressupDollRenderer.buildStateFromEquipment(_manifest, {
            gender: initData.gender || '男',
            equipment: initData.equipment || {},
            appearance: mergeObjects(DEFAULT_APPEARANCE, initData.appearance),
            keyMap: initData.keyMap || {},
            fitFields: initData.fitFields || null,
            zoom: typeof initData.zoom === 'number' ? initData.zoom : undefined,
            margin: typeof initData.margin === 'number' ? initData.margin : undefined,
            rig: initData.rig || '',
            stateLabel: initData.stateLabel || ''
        });
    }

    function buildDevState() {
        return DressupDollRenderer.buildStateFromEquipment(_manifest, {
            gender: _refs.gender.value || '男',
            equipment: equipmentFromControls(),
            appearance: DEFAULT_APPEARANCE,
            keyMap: (_currentInitData && _currentInitData.keyMap) || {},
            fitFields: (_currentInitData && _currentInitData.fitFields) || null,
            zoom: _currentInitData && typeof _currentInitData.zoom === 'number' ? _currentInitData.zoom : undefined,
            margin: _currentInitData && typeof _currentInitData.margin === 'number' ? _currentInitData.margin : undefined,
            rig: (_currentInitData && _currentInitData.rig) || '',
            stateLabel: (_currentInitData && _currentInitData.stateLabel) || ''
        });
    }

    function renderFromControls() {
        if (!_devMode) return;
        renderCurrent();
    }

    function renderCurrent() {
        if (!_manifest || !_renderer) return;
        var state = _devMode ? buildDevState() : buildRuntimeState();
        var meta = _renderer.render(state);
        if (!meta) return;
        var report = {
            gender: state.gender,
            rig: meta.rig,
            stateLabel: meta.stateLabel,
            holders: meta.holders,
            scale: Number(meta.scale.toFixed(3)),
            animated: meta.animated,
            missing: meta.missing,
            equipment: _devMode ? equipmentFromControls() : (_currentInitData.equipment || {}),
            keyMap: state.keyMap
        };
        _refs.headerStatus.textContent = (meta.animated ? 'ANIM' : 'STATIC') + ' · missing ' + meta.missing;
        _refs.status.textContent = JSON.stringify(report, null, 2);
    }

    function mergeObjects(base, extra) {
        var result = {};
        Object.keys(base || {}).forEach(function(key) { result[key] = base[key]; });
        Object.keys(extra || {}).forEach(function(key) { result[key] = extra[key]; });
        return result;
    }

    function showError(error) {
        var text = String(error && error.stack || error);
        _refs.headerStatus.textContent = 'ERROR';
        _refs.status.textContent = text;
    }

    return {};
})();
