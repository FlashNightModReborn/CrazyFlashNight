/** Bootstrap character-create DOM controller. Host remains authoritative. */
(function(root, factory) {
    'use strict';
    var api = factory(root, root && root.BootstrapCharacterCreateRuntime);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.BootstrapCharacterCreate = api;
})(typeof window !== 'undefined' ? window : globalThis, function(global, Runtime) {
    'use strict';

    var config = null;
    var rootEl = null;
    var snapshot = null;
    var model = null;
    var expectedMode = null;
    var expectedSlot = null;
    var phase = 'closed';
    var step = 0;
    var submitSent = false;
    var submittedPayload = null;
    var durable = false;
    var composing = false;
    var manifest = null;
    var manifestPromise = null;
    var renderer = null;
    var rendererIssue = '';
    var lastRendererMeta = null;
    var pendingNames = {characterName:'', displayName:'', displayNameCustomized:false};
    var activeOpenRequestId = null;
    var pendingAttemptId = null;
    var pendingSlotKey = null;
    var recoverySent = false;
    var openRequestSequence = 0;
    var appearanceTooltipScope = null;
    var appearanceTooltipCache = {};
    var iconsReady = false;
    var previewGeneration = 0;
    var preparationTimer = null;
    var appearanceView = 'equipment';
    var appearanceDensity = 'compact';
    var activeEquipmentIndex = 0;
    var scaleHandle = null;
    var previewResizeObserver = null;
    var rendererScaleRequest = null;
    var priorOverlayScale = '';
    var ownsOverlayScale = false;
    var PREVIEW_PRESENTATION_DEADLINE_MS = 12000;
    var MIN_PREVIEW_ALPHA_PIXELS = 501;
    var DESIGN_WIDTH = 1024;
    var DESIGN_HEIGHT = 576;
    var lastPreviewAlphaPixels = 0;
    var APPEARANCE_DENSITY_KEY = 'cf7.itemgrid.mode.character-create-appearance';

    var EQUIPMENT_PICKERS = [
        {key:'upperIdentifier', catalog:'upper', label:'上装'},
        {key:'lowerIdentifier', catalog:'lower', label:'下装'},
        {key:'footwearIdentifier', catalog:'footwear', label:'鞋子'}
    ];

    function byId(id) { return rootEl ? rootEl.querySelector('#' + id) : null; }
    function cue(name) { if (config && config.playUiCue) config.playUiCue(name); }
    function emit(message) {
        if (!config || typeof config.send !== 'function') return false;
        try { return config.send(message) !== false; } catch (e) { return false; }
    }
    function setText(id, value) {
        var node = byId(id);
        if (node) node.textContent = value == null ? '' : String(value);
    }

    function createOpenRequestId() {
        openRequestSequence = (openRequestSequence + 1) % 0x1000000;
        var randomPart = '';
        try {
            if (global.crypto && typeof global.crypto.getRandomValues === 'function') {
                var values = new Uint32Array(2);
                global.crypto.getRandomValues(values);
                randomPart = values[0].toString(36) + values[1].toString(36);
            }
        } catch (e) {}
        if (!randomPart) randomPart = Math.floor(Math.random() * 0x100000000).toString(36);
        return 'cc-open-' + Date.now().toString(36) + '-'
            + openRequestSequence.toString(36) + '-' + randomPart;
    }

    function clearOpenIdentity() {
        activeOpenRequestId = null;
        pendingAttemptId = null;
        pendingSlotKey = null;
    }

    function mount() {
        rootEl.innerHTML = ''
            + '<section class="cc-shell cc-scale-shell panel-scale-shell corner-brackets" aria-labelledby="cc-title">'
            + ' <header class="cc-header term-heading-rule">'
            + '  <div class="cc-heading"><span class="term-kicker">角色创建</span>'
            + '   <div class="cc-title-row"><h1 id="cc-title">建立角色</h1>'
            + '    <ol class="cc-steps" aria-label="建角步骤">'
            + '     <li data-cc-step="0" aria-current="step"><span>01</span>身份</li>'
            + '     <li data-cc-step="1"><span>02</span>外观</li>'
            + '     <li data-cc-step="2"><span>03</span>确认</li>'
            + '    </ol>'
            + '   </div></div>'
            + '  <div class="cc-state"><span id="cc-state-dot" class="term-status-dot" data-state="loading"></span>'
            + '   <span id="cc-state-text" role="status" aria-live="polite">正在准备角色...</span></div>'
            + ' </header>'
            + ' <div class="cc-main">'
            + '  <aside class="cc-preview term-card" aria-label="角色预览">'
            + '   <div class="cc-panel-label">角色预览</div>'
            + '   <div class="cc-canvas-wrap"><canvas id="cc-preview-canvas" role="img" aria-label="当前角色外观预览"></canvas>'
            + '    <p id="cc-preview-fallback" class="cc-preview-fallback" aria-live="polite">正在准备角色预览...</p></div>'
            + '   <label id="cc-preview-height-control" class="cc-preview-height" hidden><span id="cc-height-label">身高</span>'
            + '    <span class="cc-height-range"><input id="cc-height" type="range" min="150" max="200" step="1" aria-labelledby="cc-step-title-1 cc-height-label" aria-describedby="cc-height-value"><output id="cc-height-value" for="cc-height">—</output></span></label>'
            + '   <dl class="cc-preview-meta"><div><dt>性别</dt><dd id="cc-preview-gender">—</dd></div>'
            + '    <div><dt>发型</dt><dd id="cc-preview-hair">—</dd></div></dl>'
            + '  </aside>'
            + '  <form id="cc-form" class="cc-workflow" novalidate>'
            + '   <div id="cc-loading" class="cc-loading" role="status">正在准备角色创建...</div>'
            + '   <section class="cc-step-panel" data-cc-panel="0" aria-labelledby="cc-step-title-0">'
            + '    <h2 id="cc-step-title-0">身份登记</h2>'
            + '    <label class="cc-field cc-primary-name"><span>角色名 <button type="button" class="cc-help" id="cc-help-character" aria-label="说明角色名">?</button></span>'
            + '     <input id="cc-character-name" name="characterName" autocomplete="off" aria-describedby="cc-character-help cc-error-characterName">'
            + '     <small id="cc-character-help">这是游戏内最主要的姓名，最多 15 个字符。</small><em id="cc-error-characterName" class="cc-error"></em></label>'
            + '    <fieldset class="cc-field cc-gender"><legend>性别</legend>'
            + '     <label><input type="radio" name="cc-gender" value="male" checked><span>男性</span></label>'
            + '     <label><input type="radio" name="cc-gender" value="female"><span>女性</span></label>'
            + '    </fieldset>'
            + '    <details id="cc-advanced" class="cc-advanced">'
            + '     <summary>高级选项 <small>存档名默认跟随角色名</small></summary>'
            + '     <label class="cc-field"><span>存档显示名 <button type="button" class="cc-help" id="cc-help-display" aria-label="说明存档显示名">?</button></span>'
            + '      <input id="cc-display-name" name="displayName" autocomplete="off" placeholder="默认使用角色名" aria-describedby="cc-display-help cc-error-displayName">'
            + '      <small id="cc-display-help">只用于启动器辨认槽位，允许重名；留空或清空会恢复为角色名。</small><em id="cc-error-displayName" class="cc-error"></em></label>'
            + '     <button type="button" id="cc-display-reset" class="term-btn cc-display-reset">恢复跟随角色名</button>'
            + '    </details>'
            + '   </section>'
            + '   <section class="cc-step-panel" data-cc-panel="1" aria-labelledby="cc-step-title-1" hidden>'
            + '    <h2 id="cc-step-title-1" tabindex="-1">外观配置</h2>'
            + '    <div class="cc-appearance-toolbar">'
            + '     <div class="cc-appearance-tabs" role="tablist" aria-label="外观类别">'
            + '      <button type="button" class="cc-appearance-tab" id="cc-appearance-tab-equipment" role="tab" aria-selected="true" aria-controls="cc-equipment-view" data-appearance-view="equipment">初始装备</button>'
            + '      <button type="button" class="cc-appearance-tab" id="cc-appearance-tab-hair" role="tab" aria-selected="false" aria-controls="cc-hair-view" data-appearance-view="hair">发型</button>'
            + '     </div>'
            + '     <div class="cc-density-switch item-grid-mode-switch" role="group" aria-label="候选显示方式">'
            + '      <button type="button" class="cc-density-option item-grid-mode-option" data-density="full" aria-pressed="false">完整</button>'
            + '      <button type="button" class="cc-density-option item-grid-mode-option" data-density="compact" aria-pressed="true">紧凑</button>'
            + '     </div>'
            + '    </div>'
            + '    <section id="cc-equipment-view" class="cc-appearance-view" role="tabpanel" aria-labelledby="cc-appearance-tab-equipment">'
            + '     <div id="cc-equipment-slots" class="cc-equipped-slots" role="radiogroup" aria-label="初始装备槽位"></div>'
            + '     <div class="cc-pool-heading"><b id="cc-equipment-pool-title">可选装备</b><span>选择槽位后，从下方物品中更换</span></div>'
            + '     <div id="cc-equipment-pool" class="cc-choice-pool" role="listbox" aria-labelledby="cc-equipment-pool-title"></div>'
            + '    </section>'
            + '    <section id="cc-hair-view" class="cc-appearance-view" role="tabpanel" aria-labelledby="cc-appearance-tab-hair" hidden>'
            + '     <div class="cc-hair-slot-row"><div id="cc-hair-slot" class="cc-hair-slot" role="status" aria-live="polite"></div>'
            + '      <p>选择喜欢的发型；进入游戏后可在理发店免费更换。</p></div>'
            + '     <div id="cc-hair-list" class="cc-choice-pool cc-hair-list" role="listbox" aria-label="可选发型"></div>'
            + '     <em id="cc-error-hairIdentifier" class="cc-error"></em>'
            + '    </section>'
            + '   </section>'
            + '   <section class="cc-step-panel" data-cc-panel="2" aria-labelledby="cc-step-title-2" hidden>'
            + '    <div class="cc-confirm-layout">'
            + '     <section class="cc-confirm-modes">'
            + '      <h2 id="cc-step-title-2">选择难度</h2>'
            + '      <div id="cc-difficulties" class="cc-difficulties" role="radiogroup" aria-label="游戏难度"></div>'
            + '      <em id="cc-error-difficulty" class="cc-error"></em>'
            + '     </section>'
            + '     <section class="cc-confirm-summary" aria-labelledby="cc-review-title">'
            + '      <h2 id="cc-review-title">建立前确认</h2>'
            + '      <dl id="cc-review" class="cc-review"></dl>'
            + '     </section>'
            + '    </div>'
            + '   </section>'
            + '   <div id="cc-form-alert" class="cc-form-alert" role="alert" aria-live="assertive"></div>'
            + '   <footer class="cc-actions">'
            + '    <button type="button" id="cc-cancel" class="term-btn cc-cancel">取消</button>'
            + '    <span class="cc-action-spacer"></span>'
            + '    <button type="button" id="cc-back" class="term-btn cc-back" disabled>上一步</button>'
            + '    <button type="submit" id="cc-next" class="term-btn cc-next">下一步</button>'
            + '   </footer>'
            + '  </form>'
            + ' </div>'
            + '</section>';
        bindEvents();
        bindHelp();
        refreshUi();
    }

    function bindHelp() {
        if (!global.BootTooltip || typeof global.BootTooltip.bind !== 'function') return;
        global.BootTooltip.bind(byId('cc-help-display'), '存档显示名只用于启动器辨认槽位，允许与其他槽位重名。');
        global.BootTooltip.bind(byId('cc-help-character'), '角色名会显示在游戏资料与剧情中。');
    }

    function bindEvents() {
        var form = byId('cc-form');
        form.addEventListener('submit', function(event) {
            event.preventDefault();
            if (phase === 'durable_scene_error') {
                loadDurableSlot();
                return;
            }
            if (!snapshot || isLocked()) return;
            if (step < 2) nextStep(); else submit();
        });
        byId('cc-back').addEventListener('click', previousStep);
        byId('cc-cancel').addEventListener('click', cancel);
        bindNameInput(byId('cc-display-name'), 'display');
        bindNameInput(byId('cc-character-name'), 'character');
        byId('cc-display-reset').addEventListener('click', function() {
            if (phase !== 'starting' && isDraftLocked()) return;
            var characterName = byId('cc-character-name').value;
            byId('cc-display-name').value = characterName;
            if (model) {
                model.displayNameCustomized = false;
                model.displayName = characterName;
            } else {
                pendingNames.displayNameCustomized = false;
                pendingNames.displayName = characterName;
            }
            clearFieldError('displayName');
            refreshReview();
        });
        rootEl.querySelectorAll('input[name="cc-gender"]').forEach(function(input) {
            input.addEventListener('change', function() {
                if (!snapshot || !input.checked || isDraftLocked()) return;
                Runtime.applyGender(snapshot, model, input.value);
                rebuildAppearance();
                refreshUi();
                renderPreview();
            });
        });
        rootEl.querySelectorAll('[data-appearance-view]').forEach(function(button) {
            button.addEventListener('click', function() {
                if (!snapshot || isDraftLocked()) return;
                setAppearanceView(button.getAttribute('data-appearance-view'), true);
            });
            button.addEventListener('keydown', onAppearanceTabKeydown);
        });
        rootEl.querySelectorAll('[data-density]').forEach(function(button) {
            button.addEventListener('click', function() {
                setAppearanceDensity(button.getAttribute('data-density'), true);
            });
        });
        byId('cc-height').addEventListener('input', function(event) {
            if (!model || isDraftLocked()) return;
            model.draft.height = Number(event.target.value);
            refreshPreviewMeta();
            renderPreview();
            refreshReview();
        });
    }

    function bindNameInput(input, kind) {
        if (!input) return;
            input.addEventListener('compositionstart', function() { composing = true; });
            input.addEventListener('compositionend', function() { composing = false; syncNames(kind); });
            input.addEventListener('input', function() { syncNames(kind); });
            input.addEventListener('keydown', function(event) {
                if (event.key !== 'Enter') return;
                if (composing || event.isComposing || event.keyCode === 229) {
                    event.preventDefault();
                    return;
                }
                event.preventDefault();
                if (!isLocked() && snapshot) nextStep();
            });
    }

    function syncNames(source) {
        if (phase !== 'starting' && isDraftLocked()) return;
        var characterName = byId('cc-character-name').value;
        var displayName = byId('cc-display-name').value;
        var customized = model ? model.displayNameCustomized : pendingNames.displayNameCustomized;
        if (source === 'display') customized = displayName.replace(/^\s+|\s+$/g, '') !== '';
        if (source === 'character' && !customized) {
            displayName = characterName;
            byId('cc-display-name').value = displayName;
        } else if (source === 'display' && !customized) {
            displayName = characterName;
            byId('cc-display-name').value = displayName;
        }
        if (model) {
            model.displayNameCustomized = customized;
            model.displayName = displayName;
            model.draft.characterName = characterName;
        } else {
            pendingNames.displayNameCustomized = customized;
            pendingNames.displayName = displayName;
            pendingNames.characterName = characterName;
        }
        clearFieldError('displayName');
        clearFieldError('characterName');
        refreshReview();
    }

    function rebuildAppearance() {
        if (!snapshot || !model) return;
        ensureAppearanceTooltipScope();
        fillEquipmentSlots();
        fillEquipmentPool();
        fillHair();
        setAppearanceView(appearanceView, false);
        setAppearanceDensity(appearanceDensity, false);
        loadAppearanceIcons();
    }

    function loadAppearanceDensity() {
        try {
            var value = global.localStorage && global.localStorage.getItem(APPEARANCE_DENSITY_KEY);
            if (value === 'full' || value === 'compact') return value;
        } catch (e) {}
        return 'compact';
    }

    function setAppearanceDensity(mode, persist) {
        if (mode !== 'full' && mode !== 'compact') return false;
        var changed = appearanceDensity !== mode;
        appearanceDensity = mode;
        var panel = rootEl && rootEl.querySelector('[data-cc-panel="1"]');
        if (panel) panel.setAttribute('data-density', mode);
        [byId('cc-equipment-pool'), byId('cc-hair-list')].forEach(function(host) {
            if (!host) return;
            host.classList.toggle('item-grid-compact', mode === 'compact');
            host.classList.toggle('cc-choice-pool-full', mode === 'full');
        });
        rootEl.querySelectorAll('[data-density]').forEach(function(button) {
            button.setAttribute('aria-pressed', button.getAttribute('data-density') === mode ? 'true' : 'false');
        });
        if (persist) {
            try { global.localStorage.setItem(APPEARANCE_DENSITY_KEY, mode); } catch (e) {}
            cue('playSelect');
        }
        if (changed && snapshot && model) {
            fillHair();
        }
        return true;
    }

    function setAppearanceView(next, focus) {
        if (next !== 'equipment' && next !== 'hair') return false;
        appearanceView = next;
        rootEl.querySelectorAll('[data-appearance-view]').forEach(function(button) {
            var selected = button.getAttribute('data-appearance-view') === next;
            button.setAttribute('aria-selected', selected ? 'true' : 'false');
            button.tabIndex = selected ? 0 : -1;
        });
        byId('cc-equipment-view').hidden = next !== 'equipment';
        byId('cc-hair-view').hidden = next !== 'hair';
        if (focus) {
            var target = byId(next === 'equipment' ? 'cc-appearance-tab-equipment' : 'cc-appearance-tab-hair');
            if (target) target.focus();
            cue('playTransition');
        }
        return true;
    }

    function onAppearanceTabKeydown(event) {
        var next = null;
        if (event.key === 'ArrowLeft' || event.key === 'Home') next = 'equipment';
        else if (event.key === 'ArrowRight' || event.key === 'End') next = 'hair';
        if (!next) return;
        event.preventDefault();
        setAppearanceView(next, true);
    }

    function ensureAppearanceTooltipScope() {
        if (appearanceTooltipScope || !global.PanelTooltip
                || typeof global.PanelTooltip.createScope !== 'function') return;
        appearanceTooltipScope = global.PanelTooltip.createScope(
            'bootstrap-character-create-appearance',
            {profile:global.PanelTooltip.profiles ? global.PanelTooltip.profiles.dense : 'dense-inspect'});
    }

    function disposeAppearanceTooltip() {
        if (appearanceTooltipScope && typeof appearanceTooltipScope.dispose === 'function') {
            appearanceTooltipScope.dispose();
        }
        appearanceTooltipScope = null;
        appearanceTooltipCache = {};
        if (global.PanelTooltip && typeof global.PanelTooltip.hide === 'function') {
            global.PanelTooltip.hide();
        }
    }

    function loadAppearanceIcons() {
        if (iconsReady || !global.Icons || typeof global.Icons.load !== 'function') return;
        var expectedSnapshot = snapshot;
        global.Icons.load(function() {
            if (snapshot !== expectedSnapshot || !snapshot || !model) return;
            iconsReady = true;
            fillEquipmentSlots();
            fillEquipmentPool();
        });
    }

    function appearanceTooltipHtml(row) {
        if (!row || !global.PanelTooltip) return '';
        var iconHtml = typeof global.PanelTooltip.dynamicIconHtml === 'function'
            ? global.PanelTooltip.dynamicIconHtml(row.iconName, 'cc-tooltip-icon') : '';
        return global.PanelTooltip.buildItemRichHtml({
            iconHtml:iconHtml,
            iconUrl:typeof global.PanelTooltip.staticIconUrl === 'function'
                ? global.PanelTooltip.staticIconUrl(row.iconName) : null,
            introHTML:row.introHTML,
            descHTML:row.descHTML,
            layoutType:typeof global.PanelTooltip.inferLayoutType === 'function'
                ? global.PanelTooltip.inferLayoutType(row.itemType) : 'wide'
        });
    }

    function bindAppearanceTooltip(button, row) {
        if (!appearanceTooltipScope || typeof appearanceTooltipScope.bindAsync !== 'function') return;
        var key = 'appearance:' + row.identifier;
        appearanceTooltipCache[key] = {success:true};
        appearanceTooltipScope.bindAsync(button, {
            key:key,
            item:row,
            cache:appearanceTooltipCache,
            renderBasic:function(item) { return appearanceTooltipHtml(item); },
            renderRich:function(item) { return appearanceTooltipHtml(item); },
            placement:'left',
            profile:global.PanelTooltip.profiles ? global.PanelTooltip.profiles.dense : 'dense-inspect'
        });
    }

    function bindSimpleTooltip(button, key, value, placement) {
        if (!appearanceTooltipScope || typeof appearanceTooltipScope.bindAsync !== 'function') return;
        appearanceTooltipCache[key] = {success:true};
        appearanceTooltipScope.bindAsync(button, {
            key:key,
            item:String(value || ''),
            cache:appearanceTooltipCache,
            renderBasic:function(text) {
                var node = document.createElement('div');
                node.textContent = text;
                return '<div class="cc-simple-tooltip">' + node.innerHTML + '</div>';
            },
            renderRich:function(text) {
                var node = document.createElement('div');
                node.textContent = text;
                return '<div class="cc-simple-tooltip">' + node.innerHTML + '</div>';
            },
            placement:placement || 'left',
            profile:global.PanelTooltip && global.PanelTooltip.profiles
                ? global.PanelTooltip.profiles.dense : 'dense-inspect'
        });
    }

    function equipmentRows(picker) {
        return snapshot.appearanceCatalog[picker.catalog][model.draft.gender];
    }

    function equipmentRow(picker) {
        var rows = equipmentRows(picker);
        var index = Runtime.firstIndex(rows, model.draft[picker.key]);
        return index >= 0 ? rows[index] : rows[0];
    }

    function equipmentIcon(row) {
        var icon = document.createElement('span');
        icon.className = 'cc-item-icon';
        var iconHtml = iconsReady && global.Icons && typeof global.Icons.html === 'function'
            ? global.Icons.html(row.iconName, 'cc-item-icon-image') : '';
        if (iconHtml) icon.innerHTML = iconHtml;
        else {
            var fallback = document.createElement('span');
            fallback.className = 'cc-item-icon-fallback';
            fallback.textContent = row.name.charAt(0) || '?';
            icon.appendChild(fallback);
        }
        return icon;
    }

    function fillEquipmentSlots(focusIndex) {
        var host = byId('cc-equipment-slots');
        if (!host || !snapshot || !model) return;
        if (appearanceTooltipScope && appearanceTooltipScope.releaseTree) appearanceTooltipScope.releaseTree(host);
        host.innerHTML = '';
        EQUIPMENT_PICKERS.forEach(function(picker, index) {
            var row = equipmentRow(picker);
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'cc-equipped-slot';
            button.setAttribute('role', 'radio');
            button.setAttribute('data-index', String(index));
            button.setAttribute('aria-label', row.name + '。' + row.description);
            button.setAttribute('aria-checked', index === activeEquipmentIndex ? 'true' : 'false');
            button.setAttribute('aria-label', picker.label + '，当前' + row.name);
            button.tabIndex = index === activeEquipmentIndex ? 0 : -1;
            button.appendChild(equipmentIcon(row));
            var copy = document.createElement('span');
            copy.className = 'cc-slot-copy';
            var label = document.createElement('small'); label.textContent = picker.label;
            var name = document.createElement('b'); name.textContent = row.name;
            copy.appendChild(label); copy.appendChild(name); button.appendChild(copy);
            button.addEventListener('click', function() { selectEquipmentSlot(index, true); });
            button.addEventListener('keydown', onEquipmentSlotKeydown);
            host.appendChild(button);
            bindAppearanceTooltip(button, row);
        });
        if (focusIndex !== undefined) {
            var target = host.querySelector('[data-index="' + focusIndex + '"]');
            if (target) target.focus();
        }
    }

    function selectEquipmentSlot(index, focus) {
        if (!snapshot || !model || isDraftLocked()) return false;
        activeEquipmentIndex = Math.max(0, Math.min(EQUIPMENT_PICKERS.length - 1, Number(index) || 0));
        fillEquipmentSlots(focus ? activeEquipmentIndex : undefined);
        fillEquipmentPool();
        return true;
    }

    function onEquipmentSlotKeydown(event) {
        var current = Number(event.currentTarget.getAttribute('data-index'));
        var next = current;
        if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (current + 1) % EQUIPMENT_PICKERS.length;
        else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (current + EQUIPMENT_PICKERS.length - 1) % EQUIPMENT_PICKERS.length;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = EQUIPMENT_PICKERS.length - 1;
        else return;
        event.preventDefault();
        selectEquipmentSlot(next, true);
    }

    function sourceIndex(row, fallback) {
        return row && row.sourceIndex !== undefined ? row.sourceIndex : fallback;
    }

    function fillEquipmentPool(focusKey) {
        var host = byId('cc-equipment-pool');
        if (!host || !snapshot || !model) return;
        if (appearanceTooltipScope && appearanceTooltipScope.releaseTree) appearanceTooltipScope.releaseTree(host);
        host.innerHTML = '';
        var picker = EQUIPMENT_PICKERS[activeEquipmentIndex];
        var rows = equipmentRows(picker);
        setText('cc-equipment-pool-title', picker.label + '候选');
        rows.forEach(function(row, index) {
            var key = 'equip:' + picker.catalog + ':' + sourceIndex(row, index);
            var selected = row.identifier === model.draft[picker.key];
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'cc-choice-card cc-item-option';
            button.setAttribute('role', 'option');
            button.setAttribute('data-index', String(index));
            button.setAttribute('data-choice-key', key);
            button.setAttribute('aria-label', picker.label + '，' + row.name);
            button.setAttribute('aria-selected', selected ? 'true' : 'false');
            button.tabIndex = selected ? 0 : -1;
            button.appendChild(equipmentIcon(row));
            var copy = document.createElement('span'); copy.className = 'cc-item-copy';
            var name = document.createElement('b'); name.textContent = row.name;
            var type = document.createElement('small'); type.textContent = row.itemType || picker.label;
            copy.appendChild(name); copy.appendChild(type); button.appendChild(copy);
            var marker = document.createElement('span'); marker.className = 'cc-item-marker';
            marker.setAttribute('aria-hidden', 'true');
            marker.textContent = selected ? '◆' : ''; button.appendChild(marker);
            button.addEventListener('click', function() { chooseEquipment(index, true); });
            button.addEventListener('keydown', function(event) { onChoiceKeydown(event, 'equipment'); });
            host.appendChild(button);
            bindAppearanceTooltip(button, row);
        });
        setAppearanceDensity(appearanceDensity, false);
        if (focusKey) {
            var focusTarget = host.querySelector('[data-choice-key="' + focusKey + '"]');
            if (focusTarget) focusTarget.focus();
        }
    }

    function chooseEquipment(index, focus) {
        if (!snapshot || !model || isDraftLocked()) return;
        var picker = EQUIPMENT_PICKERS[activeEquipmentIndex];
        var rows = equipmentRows(picker);
        if (index < 0 || index >= rows.length) return;
        model.draft[picker.key] = rows[index].identifier;
        var key = 'equip:' + picker.catalog + ':' + sourceIndex(rows[index], index);
        fillEquipmentSlots();
        fillEquipmentPool(focus ? key : null);
        renderPreview();
        refreshReview();
        cue('playSelect');
    }

    function computedColumns(host) {
        try {
            var template = global.getComputedStyle(host).gridTemplateColumns;
            if (template && template !== 'none') {
                var columns = template.split(/\s+/).filter(Boolean).length;
                if (columns > 0) return columns;
            }
        } catch (e) {}
        var width = host && (host.clientWidth || host.getBoundingClientRect().width) || 300;
        return appearanceDensity === 'compact' ? Math.max(1, Math.floor(width / 52)) : Math.max(1, Math.floor(width / 170));
    }

    function onChoiceKeydown(event, kind) {
        var host = kind === 'hair' ? byId('cc-hair-list') : byId('cc-equipment-pool');
        var options = Array.from(host.querySelectorAll('[role="option"]'));
        var current = options.indexOf(event.currentTarget);
        var count = options.length;
        if (current < 0 || !count) return;
        var columns = computedColumns(host);
        var next = current;
        if (event.key === 'ArrowRight') next++;
        else if (event.key === 'ArrowLeft') next--;
        else if (event.key === 'ArrowDown') next += columns;
        else if (event.key === 'ArrowUp') next -= columns;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = count - 1;
        else return;
        event.preventDefault();
        next = Math.max(0, Math.min(count - 1, next));
        var absoluteIndex = Number(options[next].getAttribute('data-index'));
        if (kind === 'hair') chooseHair(absoluteIndex, true);
        else chooseEquipment(absoluteIndex, true);
    }

    function resolveHairEntry(identifier) {
        if (!manifest || !manifest.skinKeys) return null;
        var key = identifier;
        var entry = manifest.skinKeys[key];
        if (!entry || !entry.export) {
            var map = manifest.appearance && manifest.appearance.hairById;
            key = map && Object.prototype.hasOwnProperty.call(map, identifier) ? map[identifier] : '';
            entry = key && manifest.skinKeys[key];
        }
        return entry && entry.export ? entry : null;
    }

    function hairDisplayParts(row) {
        var raw = String(row && (row.name || row.identifier) || '未命名发型').replace(/^\s+|\s+$/g, '');
        var match = raw.match(/^发型[-－_\s]*(男式|女式)[-－_\s]*(.*)$/);
        if (match) {
            return {
                raw:raw,
                name:(match[2] || match[1] + '发型').replace(/^\s+|\s+$/g, ''),
                meta:match[1] + '发型'
            };
        }
        var name = raw.replace(/^发型[-－_\s]*/, '').replace(/^\s+|\s+$/g, '');
        return {raw:raw, name:name || raw, meta:'发型'};
    }

    function hairVisual(row) {
        var frame = document.createElement('span');
        frame.className = 'cc-hair-icon';
        var entry = row && resolveHairEntry(row.identifier);
        var imageFrame = entry && entry.frames && entry.frames.length ? entry.frames[0] : null;
        var uri = imageFrame && imageFrame.uri || entry && entry.export && entry.export.uri;
        if (uri) {
            var image = document.createElement('img');
            image.className = 'cc-hair-icon-image';
            image.alt = '';
            image.setAttribute('aria-hidden', 'true');
            image.loading = 'lazy';
            image.decoding = 'async';
            try { image.src = new URL(uri, manifest.__baseUrl || document.baseURI).href; }
            catch (e) { image.src = uri; }
            frame.appendChild(image);
        } else {
            var fallback = document.createElement('span');
            fallback.className = 'cc-hair-icon-fallback';
            fallback.textContent = row && /光头/.test(row.name || row.identifier) ? '无' : '发';
            frame.appendChild(fallback);
        }
        return frame;
    }

    function fillHair() {
        var list = byId('cc-hair-list');
        if (!list || !snapshot || !model) return;
        if (appearanceTooltipScope && appearanceTooltipScope.releaseTree) appearanceTooltipScope.releaseTree(list);
        list.innerHTML = '';
        var total = snapshot.hairCatalog.length;
        snapshot.hairCatalog.forEach(function(row, index) {
            var display = hairDisplayParts(row);
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'cc-choice-card cc-hair-option';
            button.id = 'cc-hair-' + index;
            button.setAttribute('role', 'option');
            button.setAttribute('data-index', String(index));
            button.setAttribute('data-choice-key', 'hair:' + sourceIndex(row, index));
            button.setAttribute('aria-label', '发型，' + display.raw);
            button.setAttribute('aria-posinset', String(index + 1));
            button.setAttribute('aria-setsize', String(total));
            button.setAttribute('aria-selected', index === model.hairIndex ? 'true' : 'false');
            button.tabIndex = index === model.hairIndex ? 0 : -1;
            button.appendChild(hairVisual(row));
            var copy = document.createElement('span');
            copy.className = 'cc-hair-copy';
            var name = document.createElement('b');
            name.textContent = display.name;
            copy.appendChild(name);
            var detail = document.createElement('small'); detail.textContent = display.meta;
            copy.appendChild(detail);
            var marker = document.createElement('span');
            marker.className = 'cc-hair-marker';
            marker.setAttribute('aria-hidden', 'true');
            marker.textContent = index === model.hairIndex ? '◆' : '';
            button.appendChild(copy);
            button.appendChild(marker);
            button.addEventListener('click', function() { chooseHair(index, true); });
            button.addEventListener('keydown', function(event) { onChoiceKeydown(event, 'hair'); });
            list.appendChild(button);
            bindSimpleTooltip(button, 'hair:' + sourceIndex(row, index), display.raw, 'left');
        });
        fillHairSlot();
    }

    function fillHairSlot() {
        var host = byId('cc-hair-slot');
        if (!host || !snapshot || !model) return;
        host.innerHTML = '';
        var row = snapshot.hairCatalog[model.hairIndex];
        if (!row) return;
        var display = hairDisplayParts(row);
        host.appendChild(hairVisual(row));
        var copy = document.createElement('span'); copy.className = 'cc-slot-copy';
        var label = document.createElement('small'); label.textContent = '当前发型 · ' + display.meta;
        var name = document.createElement('b'); name.textContent = display.name;
        copy.appendChild(label); copy.appendChild(name); host.appendChild(copy);
        host.setAttribute('aria-label', '当前发型，' + display.raw);
    }

    function chooseHair(index, focus) {
        if (!snapshot || !model || isDraftLocked() || index < 0 || index >= snapshot.hairCatalog.length) return;
        model.hairIndex = index;
        model.draft.hairIdentifier = snapshot.hairCatalog[index].identifier;
        var options = byId('cc-hair-list').querySelectorAll('[role="option"]');
        options.forEach(function(option) {
            var selected = Number(option.getAttribute('data-index')) === index;
            option.setAttribute('aria-selected', selected ? 'true' : 'false');
            option.tabIndex = selected ? 0 : -1;
            var marker = option.querySelector('.cc-hair-marker');
            if (marker) marker.textContent = selected ? '◆' : '';
        });
        fillHairSlot();
        var focusOption = byId('cc-hair-list').querySelector('[data-index="' + index + '"]');
        if (focus && focusOption) {
            var panel = rootEl.querySelector('[data-cc-panel="1"]');
            var panelScrollTop = panel ? panel.scrollTop : 0;
            try { focusOption.focus({preventScroll:true}); } catch (e) { focusOption.focus(); }
            if (panel) panel.scrollTop = panelScrollTop;
            revealChoice(byId('cc-hair-list'), focusOption);
        }
        clearFieldError('hairIdentifier');
        refreshPreviewMeta();
        refreshReview();
        renderPreview();
    }

    function revealChoice(host, option) {
        if (!host || !option || appearanceDensity !== 'full') return;
        var hostRect = host.getBoundingClientRect();
        var optionRect = option.getBoundingClientRect();
        if (optionRect.top < hostRect.top) host.scrollTop -= hostRect.top - optionRect.top + 6;
        else if (optionRect.bottom > hostRect.bottom) host.scrollTop += optionRect.bottom - hostRect.bottom + 6;
    }

    function fillDifficulties() {
        var host = byId('cc-difficulties');
        ensureAppearanceTooltipScope();
        if (appearanceTooltipScope && appearanceTooltipScope.releaseTree) appearanceTooltipScope.releaseTree(host);
        host.innerHTML = '';
        snapshot.difficulties.forEach(function(row, index) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'cc-difficulty';
            button.setAttribute('role', 'radio');
            button.setAttribute('data-index', String(index));
            var selected = row.identifier === model.draft.difficulty;
            button.setAttribute('aria-checked', selected ? 'true' : 'false');
            button.tabIndex = selected ? 0 : -1;
            var title = document.createElement('strong');
            title.textContent = row.name;
            button.appendChild(title);
            if (row.recommended) {
                var tag = document.createElement('span');
                tag.className = 'cc-recommended';
                tag.textContent = '推荐';
                button.appendChild(tag);
            }
            var description = document.createElement('span');
            description.className = 'cc-difficulty-description';
            description.textContent = difficultySummary(row.description);
            button.appendChild(description);
            button.addEventListener('click', function() { chooseDifficulty(index, true); });
            button.addEventListener('keydown', onDifficultyKeydown);
            host.appendChild(button);
            bindSimpleTooltip(button, 'difficulty:' + row.identifier, row.description, 'left');
        });
    }

    function difficultySummary(value) {
        var text = String(value || '').replace(/^\s+|\s+$/g, '').replace(/\s+/g, ' ');
        if (!text) return '完整规则见详情。';
        var sentence = text.match(/^.*?[。！？；.!?;]/);
        var summary = sentence ? sentence[0] : text;
        var glyphs = Array.from(summary);
        if (glyphs.length <= 42) return summary;
        return glyphs.slice(0, 41).join('') + '…';
    }

    function chooseDifficulty(index, focus) {
        if (!snapshot || !model || isDraftLocked() || index < 0 || index >= snapshot.difficulties.length) return;
        model.draft.difficulty = snapshot.difficulties[index].identifier;
        var radios = byId('cc-difficulties').querySelectorAll('[role="radio"]');
        radios.forEach(function(radio, i) {
            radio.setAttribute('aria-checked', i === index ? 'true' : 'false');
            radio.tabIndex = i === index ? 0 : -1;
        });
        if (focus && radios[index]) radios[index].focus();
        clearFieldError('difficulty');
        refreshReview();
    }

    function onDifficultyKeydown(event) {
        var current = Number(event.currentTarget.getAttribute('data-index'));
        var count = snapshot.difficulties.length;
        var next = current;
        if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (current + 1) % count;
        else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (current + count - 1) % count;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = count - 1;
        else return;
        event.preventDefault();
        chooseDifficulty(next, true);
    }

    function nextStep() {
        if (!snapshot || !model || isDraftLocked()) return;
        syncNames();
        if (step === 0) {
            var checked = Runtime.validateSubmission(snapshot, model);
            var errors = {};
            if (checked.errors.displayName) errors.displayName = checked.errors.displayName;
            if (checked.errors.characterName) errors.characterName = checked.errors.characterName;
            if (Object.keys(errors).length) { showErrors(errors); return; }
        }
        if (step < 2) {
            step++;
            cue('playTransition');
            refreshUi();
            focusStep();
        }
    }

    function previousStep() {
        if (!snapshot || isDraftLocked()) return;
        if (step > 0) {
            step--;
            cue('playTransition');
            refreshUi();
            focusStep();
        }
    }

    function focusStep() {
        var target = step === 0 ? byId('cc-character-name')
            : (step === 1 ? byId('cc-height')
                : byId('cc-difficulties').querySelector('[tabindex="0"]'));
        if (target) {
            try { target.focus({preventScroll:true}); } catch (e) { target.focus(); }
        }
    }

    function submit() {
        if (!snapshot || !model || submitSent || isLocked()) return false;
        if (isRetryOnly()) return retrySubmittedPayload();
        syncNames();
        var checked = Runtime.validateSubmission(snapshot, model);
        if (!checked.valid) {
            showErrors(checked.errors);
            if (checked.errors.displayName || checked.errors.characterName) step = 0;
            else if (checked.errors.hairIdentifier || checked.errors.height || checked.errors.faceIdentifier
                    || checked.errors.upperIdentifier || checked.errors.lowerIdentifier || checked.errors.footwearIdentifier) step = 1;
            else step = 2;
            refreshUi();
            focusStep();
            cue('playError');
            return false;
        }
        clearErrors();
        submitSent = true;
        phase = 'submitting';
        refreshUi();
        var payload = {
            cmd:'character_create_submit',
            openRequestId:activeOpenRequestId,
            attemptId:snapshot.attemptId,
            slotKey:snapshot.slotKey,
            displayNameCustomized:checked.displayNameCustomized,
            draft:checked.draft
        };
        if (checked.displayNameCustomized) payload.displayName = checked.displayName;
        var ok = emit(payload);
        if (!ok) {
            submitSent = false;
            phase = 'rejected';
            setAlert('无法发送创建请求，请重试。');
            refreshUi();
            cue('playError');
            return false;
        }
        submittedPayload = payload;
        cue('playSelect');
        return true;
    }

    function retrySubmittedPayload() {
        if (!submittedPayload || phase !== 'rejected' || submitSent || durable) return false;
        submitSent = true;
        phase = 'submitting';
        refreshUi();
        if (!emit(submittedPayload)) {
            submitSent = false;
            phase = 'rejected';
            setAlert('上次保存尚未确认。为避免重复创建，当前内容已锁定；可以再次重试保存或取消。');
            refreshUi();
            cue('playError');
            return false;
        }
        cue('playSelect');
        return true;
    }

    function cancel() {
        if (isCancellationLocked()) return false;
        if (!emit({cmd:'cancel_launch'})) {
            setAlert('无法发送取消请求。');
            cue('playError');
            return false;
        }
        cue('playCancel');
        var cancelledToken = activeOpenRequestId;
        phase = 'closed';
        recoverySent = false;
        previewGeneration++;
        clearPreparationTimer();
        destroyRenderer();
        detachScale();
        clearOpenIdentity();
        disposeAppearanceTooltip();
        if (config && config.onCancel) config.onCancel(cancelledToken);
        return true;
    }

    function isCancellationLocked() {
        return phase === 'submitting' || phase === 'durable' || phase === 'unknown'
            || phase === 'scene_ready';
    }

    function isLocked() {
        return isCancellationLocked() || phase === 'starting' || phase === 'preparing';
    }

    function isRetryOnly() {
        return phase === 'rejected' && !!submittedPayload && !durable;
    }

    function isDraftLocked() {
        return isLocked() || isRetryOnly() || phase === 'durable_scene_error';
    }

    function loadDurableSlot() {
        if (phase !== 'durable_scene_error' || recoverySent) return false;
        recoverySent = true;
        refreshUi();
        var ok = !!(config && typeof config.onLoadDurable === 'function'
            && config.onLoadDurable(snapshot && snapshot.slotKey) !== false);
        if (!ok) {
            recoverySent = false;
            setAlert('无法发送载入请求；已创建的存档不会被重复保存。');
            refreshUi();
            cue('playError');
            return false;
        }
        cue('playSelect');
        return true;
    }

    function setAlert(message) { setText('cc-form-alert', message || ''); }
    function clearFieldError(key) {
        var error = byId('cc-error-' + key);
        if (error) error.textContent = '';
        var input = key === 'displayName' ? byId('cc-display-name')
            : key === 'characterName' ? byId('cc-character-name') : null;
        if (input) input.removeAttribute('aria-invalid');
    }
    function clearErrors() {
        ['displayName','characterName','hairIdentifier','difficulty'].forEach(clearFieldError);
        setAlert('');
    }
    function showErrors(errors) {
        clearErrors();
        Object.keys(errors).forEach(function(key) {
            var target = byId('cc-error-' + key);
            if (target) target.textContent = errors[key];
            var input = key === 'displayName' ? byId('cc-display-name')
                : key === 'characterName' ? byId('cc-character-name') : null;
            if (input) input.setAttribute('aria-invalid', 'true');
        });
        setAlert('请先修正标记的内容。');
        cue('playError');
    }

    function phaseCopy() {
        if (phase === 'closed') return ['loading', '未打开'];
        if (phase === 'starting') return ['loading', '正在准备游戏与角色资料...'];
        if (phase === 'preparing') return ['loading', '正在绘制角色预览...'];
        if (phase === 'editing') return ['ready', '可以开始建立角色'];
        if (phase === 'submitting') return ['loading', '正在保存角色...'];
        if (phase === 'durable') return ['ready', '角色已保存，正在进入游戏...'];
        if (phase === 'scene_ready') return ['ready', '角色已创建，正在进入游戏...'];
        if (phase === 'rejected' && isRetryOnly()) return ['error', '角色尚未保存；可重试或取消'];
        if (phase === 'rejected') return ['error', '角色创建未能继续；请重试或取消'];
        if (phase === 'unknown') return ['warning', '保存结果仍在确认；暂时不能再次创建'];
        if (phase === 'durable_scene_error') return ['error', '存档已创建，但场景进入失败；不会重复创建'];
        return ['error', '创建流程发生错误'];
    }

    function refreshUi() {
        if (!rootEl) return;
        var copy = phaseCopy();
        byId('cc-state-dot').setAttribute('data-state', copy[0]);
        setText('cc-state-text', copy[1]);
        var loading = byId('cc-loading');
        loading.hidden = !!snapshot;
        if (!snapshot) loading.textContent = phase === 'rejected'
            ? '角色创建未能开始，请取消后重试。'
            : '正在准备游戏与角色资料...';
        rootEl.querySelectorAll('[data-cc-panel]').forEach(function(panel) {
            var panelStep = Number(panel.getAttribute('data-cc-panel'));
            panel.hidden = panelStep !== step || (!snapshot && panelStep !== 0);
        });
        rootEl.querySelectorAll('[data-cc-step]').forEach(function(item) {
            var active = Number(item.getAttribute('data-cc-step')) === step;
            if (active) item.setAttribute('aria-current', 'step');
            else item.removeAttribute('aria-current');
        });
        var locked = isLocked() || !snapshot;
        var durableRecovery = phase === 'durable_scene_error';
        var draftLocked = locked || isRetryOnly() || durableRecovery;
        byId('cc-back').disabled = draftLocked || step === 0;
        byId('cc-cancel').disabled = isCancellationLocked();
        byId('cc-cancel').textContent = durableRecovery ? '返回存档列表' : '取消';
        byId('cc-next').disabled = durableRecovery ? recoverySent : locked;
        byId('cc-next').textContent = durableRecovery
            ? (recoverySent ? '正在载入…' : '载入已创建存档')
            : (isRetryOnly() ? '重试保存' : (step === 2 ? '确认创建' : '下一步'));
        byId('cc-form').setAttribute('aria-busy', phase === 'starting' || phase === 'preparing'
            || phase === 'submitting' || phase === 'durable' ? 'true' : 'false');
        rootEl.querySelectorAll('input, .cc-equipped-slot, .cc-choice-card, .cc-appearance-tab, .cc-density-option, .cc-difficulty').forEach(function(control) {
            control.disabled = draftLocked;
        });
        byId('cc-display-reset').disabled = draftLocked;
        var heightControl = byId('cc-preview-height-control');
        if (heightControl) heightControl.hidden = !snapshot || step !== 1;
        byId('cc-height').disabled = draftLocked || step !== 1;
        if (model) {
            byId('cc-display-name').value = model.displayName;
            byId('cc-character-name').value = model.draft.characterName;
            var gender = rootEl.querySelector('input[name="cc-gender"][value="' + model.draft.gender + '"]');
            if (gender) gender.checked = true;
            byId('cc-height').value = String(model.draft.height);
            byId('cc-height').setAttribute('aria-valuetext', model.draft.height + ' 厘米');
            setText('cc-height-value', model.draft.height + ' cm');
            refreshPreviewMeta();
            refreshReview();
        } else {
            byId('cc-display-name').value = pendingNames.displayName;
            byId('cc-character-name').value = pendingNames.characterName;
        }
    }

    function refreshPreviewMeta() {
        if (!model || !snapshot) return;
        setText('cc-preview-gender', model.draft.gender === 'female' ? '女性' : '男性');
        byId('cc-height').setAttribute('aria-valuetext', model.draft.height + ' 厘米');
        setText('cc-height-value', model.draft.height + ' cm');
        var hair = snapshot.hairCatalog[model.hairIndex];
        var hairName = hair ? hair.name : '未知发型';
        setText('cc-preview-hair', hairName);
        var canvas = byId('cc-preview-canvas');
        var scale = 0.9 + (model.draft.height - 150) / 250;
        canvas.style.setProperty('--cc-height-scale', String(scale));
        canvas.setAttribute('aria-label', (model.draft.gender === 'female' ? '女性' : '男性')
            + '角色，身高' + model.draft.height + '厘米，发型' + hairName);
    }

    function nameOf(rows, identifier) {
        for (var i = 0; i < rows.length; i++) if (rows[i].identifier === identifier) return rows[i].name;
        return '未知选项';
    }

    function refreshReview() {
        if (!model || !snapshot) return;
        var gender = model.draft.gender;
        var difficulty = nameOf(snapshot.difficulties, model.draft.difficulty);
        var characterName = model.draft.characterName || '（尚未填写）';
        var displayName = model.displayName || characterName;
        var showDisplayName = !!model.displayNameCustomized && displayName !== characterName;
        var hair = hairDisplayParts(snapshot.hairCatalog[model.hairIndex]);
        var rows = [
            ['character-name', '角色名', characterName]
        ];
        if (showDisplayName) rows.push(['display-name', '存档名', displayName]);
        rows.push(
            ['identity', '角色', (gender === 'female' ? '女性' : '男性') + ' · ' + model.draft.height + ' cm'],
            ['difficulty', '难度', difficulty],
            ['hair', '发型', hair.primary],
            ['equipment', '服装', nameOf(snapshot.appearanceCatalog.upper[gender], model.draft.upperIdentifier)
                + ' · ' + nameOf(snapshot.appearanceCatalog.lower[gender], model.draft.lowerIdentifier)
                + ' · ' + nameOf(snapshot.appearanceCatalog.footwear[gender], model.draft.footwearIdentifier)]
        );
        var review = byId('cc-review');
        review.innerHTML = '';
        review.classList.toggle('cc-review--display-follows', !showDisplayName);
        rows.forEach(function(row) {
            var wrap = document.createElement('div');
            var dt = document.createElement('dt');
            var dd = document.createElement('dd');
            wrap.setAttribute('data-review-key', row[0]);
            dt.textContent = row[1]; dd.textContent = row[2];
            wrap.appendChild(dt); wrap.appendChild(dd); review.appendChild(wrap);
        });
    }

    function attachRenderer() {
        if (!manifest || renderer || !rootEl || !snapshot) return;
        var generation = previewGeneration;
        var token = activeOpenRequestId;
        try {
            renderer = global.DressupDollRenderer.create(byId('cc-preview-canvas'), {
                manifest:manifest,
                animate:false,
                margin:18,
                zoom:0.96,
                ignoreCssTransforms:true,
                onRender:function(meta) {
                    if (generation !== previewGeneration || token !== activeOpenRequestId) return;
                    lastRendererMeta = meta;
                    updatePreviewFallback();
                    inspectPreparationFrame(meta, generation, token);
                }
            });
            if (typeof global.ResizeObserver === 'function') {
                previewResizeObserver = new global.ResizeObserver(scheduleRendererScaleRefresh);
                previewResizeObserver.observe(byId('cc-preview-canvas'));
            }
            scheduleRendererScaleRefresh();
            renderPreview();
        } catch (e) {
            rendererIssue = 'render_failed';
            updatePreviewFallback();
            schedulePreparationReveal(true, generation, token);
        }
    }

    function scheduleRendererScaleRefresh() {
        if (!renderer || rendererScaleRequest !== null) return;
        rendererScaleRequest = requestFrame(function() {
            rendererScaleRequest = null;
            if (!renderer) return;
            var canvas = byId('cc-preview-canvas');
            if (!canvas) return;
            var rect = canvas.getBoundingClientRect();
            var ratio = (Number(global.devicePixelRatio) || 1)
                * Math.max(rect.width / Math.max(1, canvas.clientWidth || rect.width),
                    rect.height / Math.max(1, canvas.clientHeight || rect.height));
            renderer.setPixelRatio(Math.min(4, Math.max(1, ratio)));
        });
    }

    function destroyRenderer() {
        if (previewResizeObserver) {
            previewResizeObserver.disconnect();
            previewResizeObserver = null;
        }
        if (rendererScaleRequest !== null) {
            if (typeof global.cancelAnimationFrame === 'function') global.cancelAnimationFrame(rendererScaleRequest);
            else clearTimeout(rendererScaleRequest);
        }
        rendererScaleRequest = null;
        if (renderer) renderer.destroy();
        renderer = null;
    }

    function updateOverlayScale() {
        if (!ownsOverlayScale || !global.document || !global.document.documentElement) return;
        var height = Number(global.innerHeight) || 864;
        global.document.documentElement.style.setProperty('--cf7-overlay-scale', String(Math.max(0.25, height / 864)));
    }

    function attachScale() {
        detachScale();
        var shell = rootEl && rootEl.querySelector('.cc-scale-shell');
        if (!shell) return;
        var rootStyle = global.document && global.document.documentElement
            ? global.document.documentElement.style : null;
        priorOverlayScale = rootStyle ? rootStyle.getPropertyValue('--cf7-overlay-scale') : '';
        ownsOverlayScale = true;
        updateOverlayScale();
        scaleHandle = global.PanelScale && typeof global.PanelScale.attach === 'function'
            ? global.PanelScale.attach(shell, DESIGN_WIDTH, DESIGN_HEIGHT, {
                onUpdate:function() {
                    updateOverlayScale();
                    scheduleRendererScaleRefresh();
                }
            }) : null;
    }

    function detachScale() {
        if (scaleHandle && typeof scaleHandle.detach === 'function') scaleHandle.detach();
        scaleHandle = null;
        if (ownsOverlayScale && global.document && global.document.documentElement) {
            var rootStyle = global.document.documentElement.style;
            if (priorOverlayScale) rootStyle.setProperty('--cf7-overlay-scale', priorOverlayScale);
            else rootStyle.removeProperty('--cf7-overlay-scale');
        }
        priorOverlayScale = '';
        ownsOverlayScale = false;
    }

    function ensurePreview() {
        if (renderer) return;
        if (manifest) {
            attachRenderer();
            return;
        }
        if (manifestPromise) return;
        rendererIssue = '';
        setText('cc-preview-fallback', '正在载入角色预览素材...');
        if (!global.DressupDollRenderer) {
            rendererIssue = 'renderer_missing';
            updatePreviewFallback();
            if (phase === 'preparing') schedulePreparationReveal(true, previewGeneration, activeOpenRequestId);
            return;
        }
        manifestPromise = global.DressupDollRenderer.loadManifest('assets/dressup/manifest.json')
            .then(function(value) {
                manifest = value;
                manifestPromise = null;
                if (snapshot && model) fillHair();
                attachRenderer();
            })
            .catch(function() {
                manifestPromise = null;
                rendererIssue = 'manifest_failed';
                updatePreviewFallback();
                if (phase === 'preparing') schedulePreparationReveal(true, previewGeneration, activeOpenRequestId);
            });
    }

    function renderPreview() {
        if (!renderer || !manifest || !model) { updatePreviewFallback(); return; }
        try {
            var draft = model.draft;
            var state = global.DressupDollRenderer.buildStateFromEquipment(manifest, {
                gender:draft.gender === 'female' ? '女' : '男',
                equipment:{
                    '上装装备':draft.upperIdentifier,
                    '下装装备':draft.lowerIdentifier,
                    '脚部装备':draft.footwearIdentifier
                },
                appearance:{'脸型':draft.faceIdentifier, '发型':draft.hairIdentifier},
                rig:'battle',
                stateLabel:'空手站立',
                margin:18,
                zoom:0.96
            });
            lastRendererMeta = renderer.render(state);
            rendererIssue = '';
        } catch (e) {
            rendererIssue = 'render_failed';
            if (phase === 'preparing') schedulePreparationReveal(true, previewGeneration, activeOpenRequestId);
        }
        updatePreviewFallback();
    }

    function updatePreviewFallback() {
        var fallback = byId('cc-preview-fallback');
        if (!fallback) return;
        if (rendererIssue === 'renderer_missing' || rendererIssue === 'manifest_failed'
                || rendererIssue === 'render_failed') fallback.textContent = '角色预览暂时不可用，仍可继续选择。';
        else if (!manifest || lastRendererMeta && lastRendererMeta.pendingImages > 0) fallback.textContent = '正在准备角色预览...';
        else if (lastRendererMeta && (lastRendererMeta.failedImages > 0 || lastRendererMeta.missing > 0)) fallback.textContent = '部分外观暂时无法预览，选择仍会正常保存。';
        else fallback.textContent = '';
        fallback.hidden = fallback.textContent === '';
    }

    function clearPreparationTimer() {
        if (preparationTimer !== null) clearTimeout(preparationTimer);
        preparationTimer = null;
    }

    function clearPreviewCanvas() {
        var canvas = byId('cc-preview-canvas');
        if (!canvas) return;
        try {
            canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
        } catch (e) {}
    }

    function measurePreviewAlphaPixels(limit) {
        var canvas = byId('cc-preview-canvas');
        if (!canvas || !canvas.width || !canvas.height) return 0;
        try {
            var pixels = canvas.getContext('2d')
                .getImageData(0, 0, canvas.width, canvas.height).data;
            var visible = 0;
            for (var i = 3; i < pixels.length; i += 4) {
                if (pixels[i] > 0 && ++visible >= limit) return visible;
            }
            return visible;
        } catch (e) {
            return 0;
        }
    }

    function armPreparationDeadline(generation, token) {
        clearPreparationTimer();
        preparationTimer = setTimeout(function() {
            preparationTimer = null;
            if (phase !== 'preparing' || generation !== previewGeneration
                    || token !== activeOpenRequestId) return;
            rendererIssue = rendererIssue || 'render_failed';
            updatePreviewFallback();
            schedulePreparationReveal(true, generation, token);
        }, PREVIEW_PRESENTATION_DEADLINE_MS);
    }

    function requestFrame(callback) {
        if (global && typeof global.requestAnimationFrame === 'function') {
            return global.requestAnimationFrame(callback);
        }
        return setTimeout(callback, 0);
    }

    function schedulePreparationReveal(degraded, generation, token) {
        if (phase !== 'preparing' || generation !== previewGeneration
                || token !== activeOpenRequestId) return false;
        clearPreparationTimer();
        requestFrame(function() {
            requestFrame(function() {
                if (phase !== 'preparing' || generation !== previewGeneration
                        || token !== activeOpenRequestId) return;
                phase = 'editing';
                refreshUi();
                if (config && typeof config.onReady === 'function') config.onReady(token, degraded === true);
                focusStep();
            });
        });
        return true;
    }

    function inspectPreparationFrame(meta, generation, token) {
        if (phase !== 'preparing' || !meta || generation !== previewGeneration
                || token !== activeOpenRequestId || meta.pendingImages > 0) return false;
        var complete = meta.holders > 0 && meta.drawnImages > 0
            && meta.failedImages === 0 && meta.missing === 0;
        if (complete) {
            lastPreviewAlphaPixels = measurePreviewAlphaPixels(MIN_PREVIEW_ALPHA_PIXELS);
            if (lastPreviewAlphaPixels >= MIN_PREVIEW_ALPHA_PIXELS) {
                return schedulePreparationReveal(false, generation, token);
            }
            return false;
        }
        // A zero-draw frame without a concrete asset failure can be an intermediate
        // renderer callback. Keep the mask until a later valid frame or the bounded
        // presentation deadline instead of revealing an empty paper doll.
        if (meta.failedImages > 0 || meta.missing > 0) {
            return schedulePreparationReveal(true, generation, token);
        }
        return false;
    }

    function revealPreparationFailure(token) {
        clearPreparationTimer();
        if (config && typeof config.onReady === 'function' && token) config.onReady(token, true);
    }

    function open(mode, slotKey) {
        if (!rootEl || (mode !== 'new' && mode !== 'rebuild')) return false;
        destroyRenderer();
        detachScale();
        clearPreparationTimer();
        previewGeneration++;
        disposeAppearanceTooltip();
        snapshot = null;
        model = null;
        pendingNames = {characterName:'', displayName:'', displayNameCustomized:false};
        clearOpenIdentity();
        activeOpenRequestId = createOpenRequestId();
        expectedMode = mode;
        expectedSlot = mode === 'rebuild' ? String(slotKey || '') : null;
        phase = 'starting';
        step = 0;
        submitSent = false;
        submittedPayload = null;
        durable = false;
        recoverySent = false;
        rendererIssue = '';
        lastRendererMeta = null;
        lastPreviewAlphaPixels = 0;
        clearPreviewCanvas();
        appearanceView = 'equipment';
        appearanceDensity = loadAppearanceDensity();
        activeEquipmentIndex = 0;
        clearErrors();
        refreshUi();
        if (config && config.onPrepare) config.onPrepare(activeOpenRequestId);
        if (config && config.onShow) config.onShow();
        attachScale();
        ensurePreview();
        var request = {
            cmd:'character_create_open',
            mode:mode,
            openRequestId:activeOpenRequestId
        };
        if (mode === 'rebuild') request.slotKey = expectedSlot;
        if (!expectedSlot && mode === 'rebuild') {
            phase = 'rejected';
            setAlert('没有找到要重建的存档，请返回后重试。');
            refreshUi();
            revealPreparationFailure(activeOpenRequestId);
            return false;
        }
        if (!emit(request)) {
            var failedToken = activeOpenRequestId;
            phase = 'rejected';
            setAlert('角色创建请求未能发送，请返回后重试。');
            refreshUi();
            revealPreparationFailure(failedToken);
            return false;
        }
        return true;
    }

    function handleSnapshot(message) {
        if (phase !== 'starting' || snapshot) return false;
        var next = Runtime && Runtime.normalizeSnapshot(message);
        if (!next) {
            if (message && message.openRequestId === activeOpenRequestId) {
                phase = 'rejected';
                setAlert('角色资料无法读取，请取消后重试。');
                refreshUi();
                revealPreparationFailure(activeOpenRequestId);
            }
            return false;
        }
        if (!activeOpenRequestId || next.openRequestId !== activeOpenRequestId) return false;
        if (expectedMode === 'rebuild' && next.slotKey !== expectedSlot) return false;
        if (pendingAttemptId && (next.attemptId !== pendingAttemptId
                || next.slotKey !== pendingSlotKey)) return false;
        pendingAttemptId = next.attemptId;
        pendingSlotKey = next.slotKey;
        syncNames();
        var stagedNames = {
            characterName:pendingNames.characterName,
            displayName:pendingNames.displayName,
            displayNameCustomized:pendingNames.displayNameCustomized
        };
        snapshot = next;
        model = Runtime.initialDraft(snapshot);
        model.draft.characterName = stagedNames.characterName;
        model.displayNameCustomized = stagedNames.displayNameCustomized;
        model.displayName = stagedNames.displayNameCustomized
            ? stagedNames.displayName : stagedNames.characterName;
        phase = 'preparing';
        step = 0;
        submitSent = false;
        submittedPayload = null;
        durable = false;
        clearErrors();
        rebuildAppearance();
        fillDifficulties();
        refreshUi();
        ensurePreview();
        renderPreview();
        armPreparationDeadline(previewGeneration, activeOpenRequestId);
        if (rendererIssue) schedulePreparationReveal(true, previewGeneration, activeOpenRequestId);
        else if (lastRendererMeta) inspectPreparationFrame(lastRendererMeta, previewGeneration, activeOpenRequestId);
        return true;
    }

    function handleState(message) {
        if (!message || message.openRequestId !== activeOpenRequestId) return false;
        var next = Runtime && Runtime.normalizeState(message);
        if (!snapshot && phase === 'starting') {
            if (!next) {
                if (message.cmd !== 'character_create_state' || message.phase !== 'rejected'
                        || message.attemptId || (message.slotKey
                            && (expectedMode !== 'rebuild' || message.slotKey !== expectedSlot))) return false;
                phase = 'rejected';
                submitSent = false;
                setAlert(message.message || message.detail || message.error || '无法开始角色创建。');
                refreshUi();
                revealPreparationFailure(activeOpenRequestId);
                return true;
            }
            if (expectedMode === 'rebuild' && next.slotKey !== expectedSlot) return false;
            if (pendingAttemptId && (next.attemptId !== pendingAttemptId
                    || next.slotKey !== pendingSlotKey)) return false;
            pendingAttemptId = next.attemptId;
            pendingSlotKey = next.slotKey;
            if (next.phase === 'starting') return true;
            if (next.phase !== 'rejected') return false;
            phase = 'rejected';
            submitSent = false;
            setAlert(next.detail || '无法开始角色创建。');
            refreshUi();
            revealPreparationFailure(activeOpenRequestId);
            return true;
        }
        if (!next || !Runtime.matchesIdentity(snapshot, next)) return false;
        var wasPreparing = phase === 'preparing';
        if (phase === 'scene_ready' || phase === 'durable_scene_error') {
            return false;
        } else if (durable) {
            if (next.phase === 'scene_ready') phase = 'scene_ready';
            else if (next.phase === 'durable_scene_error') phase = 'durable_scene_error';
            else return false;
        } else if (phase === 'unknown') {
            if (next.phase === 'durable') {
                durable = true;
                phase = 'durable';
            } else if (next.phase === 'scene_ready') {
                durable = true;
                phase = 'scene_ready';
            } else if (next.phase === 'durable_scene_error') {
                durable = true;
                phase = 'durable_scene_error';
            } else return false;
        } else if (next.phase === 'durable') {
            durable = true;
            phase = 'durable';
        } else if (next.phase === 'scene_ready') {
            durable = true;
            phase = 'scene_ready';
        } else if (next.phase === 'unknown') {
            phase = 'unknown';
        } else if (next.phase === 'rejected') {
            submitSent = false;
            phase = 'rejected';
        } else if (next.phase === 'submitting') {
            submitSent = true;
            phase = 'submitting';
        } else if (next.phase === 'durable_scene_error') {
            return false;
        } else {
            phase = 'rejected';
            submitSent = false;
        }
        if (next.detail) setAlert(next.detail);
        else if (phase !== 'rejected') setAlert('');
        if (phase === 'scene_ready' || phase === 'durable_scene_error') {
            disposeAppearanceTooltip();
        }
        if (phase === 'scene_ready') {
            destroyRenderer();
            detachScale();
        }
        refreshUi();
        if (wasPreparing && phase === 'rejected') revealPreparationFailure(activeOpenRequestId);
        return true;
    }

    function handleEscape() {
        if (!rootEl || phase === 'closed') return false;
        if (phase === 'durable_scene_error') cancel();
        else if (isRetryOnly()) cancel();
        else if (!isLocked() && step > 0) previousStep();
        else if (!isCancellationLocked()) cancel();
        return true;
    }

    function debugState() {
        return {
            phase:phase,
            step:step,
            expectedMode:expectedMode,
            expectedSlot:expectedSlot,
            openRequestId:activeOpenRequestId,
            pendingAttemptId:pendingAttemptId,
            pendingSlotKey:pendingSlotKey,
            attemptId:snapshot && snapshot.attemptId,
            slotKey:snapshot && snapshot.slotKey,
            displayName:model && model.displayName,
            displayNameCustomized:model && model.displayNameCustomized,
            appearanceView:appearanceView,
            appearanceDensity:appearanceDensity,
            activeEquipment:activeEquipmentIndex,
            previewGeneration:previewGeneration,
            draft:model && JSON.parse(JSON.stringify(model.draft)),
            hairIndex:model && model.hairIndex,
            hairCatalog:snapshot ? snapshot.hairCatalog.map(function(row) { return row.identifier; }) : [],
            submitSent:submitSent,
            retryOnly:isRetryOnly(),
            durable:durable,
            recoverySent:recoverySent,
            rendererIssue:rendererIssue,
            previewAlphaPixels:lastPreviewAlphaPixels,
            minimumPreviewAlphaPixels:MIN_PREVIEW_ALPHA_PIXELS,
            rendererMeta:lastRendererMeta ? {
                gender:lastRendererMeta.gender,
                holders:lastRendererMeta.holders,
                totalHolders:lastRendererMeta.totalHolders,
                missing:lastRendererMeta.missing,
                pendingImages:lastRendererMeta.pendingImages,
                failedImages:lastRendererMeta.failedImages,
                drawnImages:lastRendererMeta.drawnImages
            } : null
        };
    }

    function init(options) {
        if (!Runtime) throw new Error('BootstrapCharacterCreateRuntime is required');
        config = options || {};
        rootEl = config.root;
        if (!rootEl) throw new Error('character-create root is required');
        mount();
        return api;
    }

    var api = {
        init:init,
        open:open,
        handleSnapshot:handleSnapshot,
        handleState:handleState,
        handleEscape:handleEscape,
        debugState:debugState
    };
    return api;
});
