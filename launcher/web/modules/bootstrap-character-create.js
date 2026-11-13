/** Bootstrap character-create DOM controller. Host remains authoritative. */
(function(root, factory) {
    'use strict';
    var api = factory(root, root && root.BootstrapCharacterCreateRuntime);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.BootstrapCharacterCreate = api;
})(typeof window !== 'undefined' ? window : globalThis, function(global, Runtime) {
    'use strict';

    var Controls = global.CharacterIdentityControls;
    var config = null;
    var rootEl = null;
    var snapshot = null;
    var model = null;
    var expectedMode = null;
    var expectedSlot = null;
    var phase = 'closed';
    var step = 0;
    var previewChoice = null;
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
    var visitedSteps = [true, false, false];
    var validationAttempted = false;
    var appearanceDensity = {equipment:'full', hair:'full'};
    var lastPanelStep = -1;
    var previewResizeObserver = null;
    var rendererScaleRequest = null;
    var priorOverlayScale = '';
    var ownsOverlayScale = false;
    var PREVIEW_PRESENTATION_DEADLINE_MS = 12000;
    var MIN_PREVIEW_ALPHA_PIXELS = 501;
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
            + '<section class="cc-shell cc-scale-shell corner-brackets" aria-labelledby="cc-title">'
            + ' <header class="cc-header term-heading-rule">'
            + '  <div class="cc-heading"><span class="term-kicker">角色创建</span>'
            + '   <div class="cc-title-row"><h1 id="cc-title">建立角色</h1>'
            + '    <ol class="cc-steps" aria-label="建角步骤">'
            + '     <li data-cc-step="0" aria-current="step"><button type="button" class="cc-step-jump" data-cc-step-jump="0" disabled><span>01</span>身份</button></li>'
            + '     <li data-cc-step="1"><button type="button" class="cc-step-jump" data-cc-step-jump="1" disabled><span>02</span>外观</button></li>'
            + '     <li data-cc-step="2"><button type="button" class="cc-step-jump" data-cc-step-jump="2" disabled><span>03</span>难度</button></li>'
            + '    </ol>'
            + '   </div></div>'
            + '  <div class="cc-state"><span id="cc-state-dot" class="term-status-dot" data-state="loading"></span>'
            + '   <span id="cc-state-text" role="status" aria-live="polite">正在准备角色...</span></div>'
            + ' </header>'
            + ' <div class="cc-main">'
            + '  <aside class="cc-preview term-card" aria-label="角色预览">'
            + '   <button type="button" class="term-btn" id="cc-random-look">随机外观</button>'
            + '   <div class="cc-canvas-wrap"><canvas id="cc-preview-canvas" role="img" aria-label="当前角色外观预览"></canvas>'
            + '    <p id="cc-preview-fallback" class="cc-preview-fallback" aria-live="polite">正在准备角色预览...</p></div>'
            + '   <div class="cc-pad" aria-hidden="true"><i></i><i></i><i></i></div>'
            + '   <strong id="cc-nameplate">未命名</strong>'
            + Controls.heightMarkup('cc', true, 'cc-step-title-1')
            + '   <dl class="cc-preview-meta"><div><dt>性别</dt><dd id="cc-preview-gender">—</dd></div>'
            + '    <div><dt>发型</dt><dd id="cc-preview-hair">—</dd></div></dl>'
            + '   <div class="cc-tt-anchor" aria-hidden="true"></div>'
            + '  </aside>'
            + '  <form id="cc-form" class="cc-workflow" novalidate>'
            + '   <div id="cc-loading" class="cc-loading" role="status">正在准备角色创建...</div>'
            + '   <section class="cc-step-panel" data-cc-panel="0" aria-labelledby="cc-step-title-0">'
            + '    <h2 id="cc-step-title-0">身份登记</h2>'
            + Controls.nameMarkup('cc', true)
            + Controls.genderMarkup('cc')
            + '    <p class="cc-gender-hint">切换性别会重置外观，保留姓名与难度。</p>'
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
            + '    <div id="cc-equipment-view" aria-label="初始装备"></div>'
            + '    <section id="cc-hair-view" aria-label="发型">'
            + '     <div class="cc-hair-filter"><b>发型</b><div id="cc-hair-filter" role="group" aria-label="发型分类"></div><input id="cc-hair-search" type="search" aria-label="搜索发型" placeholder="搜索发型"><button type="button" class="term-btn cc-density-option" data-density-view="hair" aria-label="切换发型图标或名称">显示图标</button></div>'
            + '     <div id="cc-hair-list" class="cc-choice-pool cc-hair-list" role="listbox" aria-label="可选发型"></div>'
            + '     <p id="cc-hair-empty" role="status" hidden>没有符合条件的发型。</p>'
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
            + '      <span id="cc-slot-signature" class="slot-sig" aria-label="新存档节点签名" hidden></span>'
            + '      <dl id="cc-review" class="cc-review" tabindex="0" aria-labelledby="cc-review-title"></dl>'
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
        rootEl.querySelectorAll('[data-cc-step-jump]').forEach(function(button) {
            button.addEventListener('click', function() {
                jumpToStep(Number(button.getAttribute('data-cc-step-jump')));
            });
        });
        byId('cc-cancel').addEventListener('click', cancel);
        byId('cc-random-look').addEventListener('click', function () {
            if (!snapshot || !model || isDraftLocked()) return;
            EQUIPMENT_PICKERS.forEach(function (picker) {
                var rows = equipmentRows(picker);
                if (rows.length) model.draft[picker.key] = rows[Math.floor(Math.random() * rows.length)].identifier;
            });
            var tag = model.draft.gender === 'female' ? '女式' : '男式';
            var indexes = [];
            snapshot.hairCatalog.forEach(function (row, index) {
                if (row.identifier.indexOf(tag) >= 0) indexes.push(index);
            });
            var hairs = snapshot.hairCatalog;
            if (hairs.length) {
                model.hairIndex = indexes.length ? indexes[Math.floor(Math.random() * indexes.length)]
                    : Math.floor(Math.random() * hairs.length);
                model.draft.hairIdentifier = hairs[model.hairIndex].identifier;
            }
            var height = byId('cc-height');
            var baseline = snapshot.defaults[model.draft.gender].height;
            model.draft.height = Math.min(Number(height.max), Math.max(Number(height.min), baseline + Math.round((Math.random() - 0.5) * 24)));
            previewChoice = null;
            rebuildAppearance(); refreshUi(); renderPreview();
        });
        byId('cc-hair-search').addEventListener('input', fillHair);
        byId('cc-hair-filter').addEventListener('click', function (event) {
            var button = event.target.closest('button[data-group]');
            if (!button) return;
            byId('cc-hair-filter').dataset.selected = button.dataset.group;
            fillHair();
        });
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
        Controls.bindGender(rootEl.querySelectorAll('input[name="cc-gender"]'), function(value) {
            if (!snapshot || isDraftLocked()) return;
            Runtime.applyGender(snapshot, model, value);
            rebuildAppearance(); refreshUi(); renderPreview(); flashPreviewSwap();
        });
        rootEl.querySelector('[data-density-view="hair"]').addEventListener('click', function() {
            if (!model || isDraftLocked()) return;
            appearanceDensity.hair = appearanceDensity.hair === 'full' ? 'compact' : 'full';
            try { global.localStorage.setItem(APPEARANCE_DENSITY_KEY, JSON.stringify(appearanceDensity)); } catch (e) {}
            applyHairDensity();
        });
        Controls.bindHeight(byId('cc-height'), function(value) {
            if (!model || isDraftLocked()) return;
            model.draft.height = value;
            refreshPreviewMeta();
            renderPreview();
            refreshReview();
        });
    }

    function bindNameInput(input, kind) {
        if (!input) return;
        Controls.bindNameInput(input, {
            onComposition:function(value) { composing = value; },
            onChange:function() { syncNames(kind); },
            onEnter:function() { if (!isLocked() && snapshot) nextStep(); }
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
        refreshProgress();
        setText('cc-nameplate', characterName.trim() || '未命名');
        refreshReview();
    }

    function rebuildAppearance() {
        if (!snapshot || !model) return;
        ensureAppearanceTooltipScope();
        fillEquipmentPool();
        fillHair();
        applyHairDensity();
        loadAppearanceIcons();
    }

    function loadAppearanceDensity() {
        var defaults = {equipment:'full', hair:'full'};
        try {
            var raw = global.localStorage && global.localStorage.getItem(APPEARANCE_DENSITY_KEY);
            if (!raw) return defaults;
            // 旧版存的是全局单值 'full'/'compact'：视为用户对两个视图共同的显式选择迁移。
            if (raw === 'full' || raw === 'compact') return {equipment:raw, hair:raw};
            var parsed = JSON.parse(raw);
            return {
                equipment:parsed && parsed.equipment === 'compact' ? 'compact' : 'full',
                hair:parsed && parsed.hair === 'compact' ? 'compact' : 'full'
            };
        } catch (e) {}
        return defaults;
    }

    function applyHairDensity() {
        var compact = appearanceDensity.hair === 'compact';
        byId('cc-hair-list').classList.toggle('item-grid-compact', compact);
        var button = rootEl.querySelector('[data-density-view="hair"]');
        button.textContent = compact ? '显示名称' : '显示图标';
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

    // 候选注释统一锚到表单列右缘的隐形锚条：tooltip 恒出现在表单列内部右侧，
    // 不随格内位置跳动，也不会左压纸娃娃预览（placement 'left' 相对锚条恒可行）。
    function appearanceTooltipAnchor() {
        return rootEl ? rootEl.querySelector('.cc-tt-anchor') : null;
    }

    function bindAppearanceTooltip(button, row) {
        if (!appearanceTooltipScope || typeof appearanceTooltipScope.bindAsync !== 'function') return;
        var key = 'appearance:' + row.identifier;
        appearanceTooltipCache[key] = {success:true};
        appearanceTooltipScope.bindAsync(button, {
            key:key,
            item:row,
            cache:appearanceTooltipCache,
            anchor:appearanceTooltipAnchor,
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
            anchor:appearanceTooltipAnchor,
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

    function sourceIndex(row, fallback) {
        return row && row.sourceIndex !== undefined ? row.sourceIndex : fallback;
    }

    function bindTryOn(button, key, value) {
        function preview() {
            if (!model || isDraftLocked()) return;
            previewChoice = {button:button, key:key, value:value};
            renderPreview();
        }
        function restore() {
            if (previewChoice && previewChoice.button === button) {
                previewChoice = null;
                renderPreview();
            }
        }
        button.addEventListener('pointerenter', preview);
        button.addEventListener('pointerleave', restore);
        button.addEventListener('focus', preview);
        button.addEventListener('blur', restore);
    }

    function fillEquipmentPool() {
        var view = byId('cc-equipment-view');
        if (!view || !snapshot || !model) return;
        if (appearanceTooltipScope && appearanceTooltipScope.releaseTree) appearanceTooltipScope.releaseTree(view);
        if (previewChoice && view.contains(previewChoice.button)) { previewChoice = null; renderPreview(); }
        view.replaceChildren();
        EQUIPMENT_PICKERS.forEach(function(picker) {
            var line = document.createElement('div');
            line.className = 'cc-equipment-line';
            var label = document.createElement('b');
            label.textContent = picker.label;
            var host = document.createElement('div');
            host.className = 'cc-equipment-choices';
            host.id = 'cc-pool-' + picker.catalog;
            host.setAttribute('role', 'listbox');
            host.setAttribute('aria-label', picker.label);
            line.append(label, host);
            view.appendChild(line);
            buildEquipmentOptions(host, picker);
        });
    }

    function buildEquipmentOptions(host, picker) {
        var rows = equipmentRows(picker);
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
            bindTryOn(button, picker.key, row.identifier);
            button.addEventListener('click', function() { chooseEquipment(picker, index, true); });
            button.addEventListener('keydown', function(event) { onChoiceKeydown(event, picker); });
            host.appendChild(button);
            bindAppearanceTooltip(button, row);
        });
    }

    // 换装反馈：纸娃娃重绘时一道扫描光掠过画布，遮住合成硬切；reduced-motion 由 CSS 关闭。
    function flashPreviewSwap() {
        var wrap = rootEl && rootEl.querySelector('.cc-canvas-wrap');
        if (!wrap) return;
        wrap.classList.remove('is-swapping');
        void wrap.offsetWidth;
        wrap.classList.add('is-swapping');
    }

    function chooseEquipment(picker, index, focus) {
        if (!snapshot || !model || isDraftLocked()) return;
        var rows = equipmentRows(picker);
        if (index < 0 || index >= rows.length) return;
        previewChoice = null;
        model.draft[picker.key] = rows[index].identifier;
        var key = 'equip:' + picker.catalog + ':' + sourceIndex(rows[index], index);
        var host = byId('cc-pool-' + picker.catalog);
        host.querySelectorAll('[role="option"]').forEach(function(button) {
            var selected = button.dataset.choiceKey === key;
            button.setAttribute('aria-selected', String(selected));
            button.tabIndex = selected ? 0 : -1;
            button.querySelector('.cc-item-marker').textContent = selected ? '◆' : '';
            if (selected && focus) button.focus({preventScroll:true});
        });
        renderPreview();
        flashPreviewSwap();
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
        var density = host && host.id === 'cc-hair-list' ? appearanceDensity.hair : appearanceDensity.equipment;
        return density === 'compact' ? Math.max(1, Math.floor(width / 52)) : Math.max(1, Math.floor(width / 170));
    }

    function onChoiceKeydown(event, kind) {
        var host = event.currentTarget.parentElement;
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
        else chooseEquipment(kind, absoluteIndex, true);
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
        if (previewChoice && list.contains(previewChoice.button)) { previewChoice = null; renderPreview(); }
        list.innerHTML = '';
        var filter = byId('cc-hair-filter');
        var search = byId('cc-hair-search').value.trim().toLocaleLowerCase();
        if (!filter.children.length) {
            filter.dataset.selected = 'gender';
            ['gender', 'all'].forEach(function(group) {
                var button = document.createElement('button');
                button.type = 'button'; button.className = 'term-btn';
                button.dataset.group = group;
                button.textContent = group === 'gender' ? '本性别' : '全部';
                filter.appendChild(button);
            });
        }
        Array.from(filter.children).forEach(function(button) {
            button.setAttribute('aria-pressed', String(button.dataset.group === filter.dataset.selected));
        });
        var genderTag = model.draft.gender === 'female' ? '女式' : '男式';
        var total = snapshot.hairCatalog.length;
        snapshot.hairCatalog.forEach(function(row, index) {
            var display = hairDisplayParts(row);
            if ((filter.dataset.selected === 'gender' && row.identifier.indexOf(genderTag) < 0) || (search && display.raw.toLocaleLowerCase().indexOf(search) < 0)) return;
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
            bindTryOn(button, 'hairIdentifier', row.identifier);
            button.addEventListener('click', function() { chooseHair(index, true); });
            button.addEventListener('keydown', function(event) { onChoiceKeydown(event, 'hair'); });
            list.appendChild(button);
            bindSimpleTooltip(button, 'hair:' + sourceIndex(row, index), display.raw, 'left');
        });
        var visible = list.querySelectorAll('[role="option"]');
        byId('cc-hair-empty').hidden = visible.length !== 0;
        Array.from(visible).forEach(function (button, position) {
            button.setAttribute('aria-posinset', String(position + 1));
            button.setAttribute('aria-setsize', String(visible.length));
        });
        if (visible.length && !list.querySelector('[tabindex="0"]')) visible[0].tabIndex = 0;
    }

    function chooseHair(index, focus) {
        if (!snapshot || !model || isDraftLocked() || index < 0 || index >= snapshot.hairCatalog.length) return;
        previewChoice = null;
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
        flashPreviewSwap();
    }

    function revealChoice(host, option) {
        if (!host || !option) return;
        var hostRect = host.getBoundingClientRect();
        var optionRect = option.getBoundingClientRect();
        var scale = hostRect.height / host.offsetHeight || 1;
        if (optionRect.top < hostRect.top) host.scrollTop -= (hostRect.top - optionRect.top) / scale + 6;
        else if (optionRect.bottom > hostRect.bottom) host.scrollTop += (optionRect.bottom - hostRect.bottom) / scale + 6;
    }

    // 难度卡片图标：终端 stroke 风内联 SVG，按名称语义映射（天平=平衡、回旋=逆天/回归原版、山旗=挑战）。
    function difficultyIcon(row) {
        var name = row.name || '';
        var path;
        if (name.indexOf('平衡') >= 0) path = 'M12 4v16M6 20h12M6 8h12M8 8l-2.5 5h5L8 8zM16 8l-2.5 5h5L16 8z';
        else if (name.indexOf('逆天') >= 0) path = 'M4 12a8 8 0 1 0 3-6M4 12V7m0 5h5';
        else path = 'M4 20l5-9 4 6 3-4 4 7zM9 11V4m0 0h4';
        var span = document.createElement('span');
        span.className = 'cc-difficulty-icon';
        span.setAttribute('aria-hidden', 'true');
        span.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"'
            + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + path + '"/></svg>';
        return span;
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
            title.appendChild(difficultyIcon(row));
            var titleText = document.createElement('span');
            titleText.textContent = row.name;
            title.appendChild(titleText);
            button.appendChild(title);
            if (row.recommended) {
                var tag = document.createElement('span');
                tag.className = 'cc-recommended';
                tag.textContent = '推荐';
                button.appendChild(tag);
            }
            var description = document.createElement('span');
            description.className = 'cc-difficulty-description';
            description.textContent = selected ? row.description : difficultySummary(row.description);
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
            var description = snapshot.difficulties[i].description;
            radio.querySelector('.cc-difficulty-description').textContent =
                i === index ? description : difficultySummary(description);
        });
        if (focus && radios[index]) radios[index].focus();
        clearFieldError('difficulty');
        refreshPreviewMeta();
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

    // 编辑期间可自由切换三步，最终提交仍校验完整草稿。
    function jumpToStep(index) {
        if (!snapshot || isDraftLocked()) return;
        if (!Number.isInteger(index) || index < 0 || index === step || index > 2) return;
        syncNames();
        previewChoice = null;
        step = index;
        cue('playTransition');
        refreshUi();
        focusStep();
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
        validationAttempted = true;
        clearErrors();
        Object.keys(errors).forEach(function(key) {
            var target = byId('cc-error-' + key);
            if (target) target.textContent = errors[key];
            var input = key === 'displayName' ? byId('cc-display-name')
                : key === 'characterName' ? byId('cc-character-name') : null;
            if (input) input.setAttribute('aria-invalid', 'true');
        });
        setAlert('请先修正标记的内容。');
        refreshProgress();
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

    function refreshProgress() {
        if (!rootEl) return;
        var steps = rootEl.querySelectorAll('[data-cc-step]');
        var rings = rootEl.querySelectorAll('.cc-pad i');
        var named = model && model.draft.characterName.trim();
        var errors = model && snapshot ? Runtime.validateSubmission(snapshot, model).errors : {};
        var invalid = [errors.characterName || errors.displayName || errors.gender,
            errors.height || errors.faceIdentifier || errors.hairIdentifier || errors.upperIdentifier || errors.lowerIdentifier || errors.footwearIdentifier,
            errors.difficulty];
        steps.forEach(function(item, index) {
            var warn = !!invalid[index] && (validationAttempted || (index === 0 && !!named));
            var done = !!model && !invalid[index] && (index === 0 ? !!named : visitedSteps[index]);
            item.classList.toggle('is-done', done);
            item.classList.toggle('has-error', warn);
            item.querySelector('button').setAttribute('aria-invalid', String(warn));
            rings[index].classList.toggle('is-done', done);
        });
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
            var visible = panelStep === step && !(!snapshot && panelStep !== 0);
            panel.hidden = !visible;
            if (visible && panelStep !== lastPanelStep) {
                lastPanelStep = panelStep;
                var reduced = global.matchMedia
                    && global.matchMedia('(prefers-reduced-motion: reduce)').matches;
                if (!reduced) {
                    panel.classList.remove('cc-panel-enter');
                    void panel.offsetWidth;
                    panel.classList.add('cc-panel-enter');
                    panel.addEventListener('animationend', function handler() {
                        panel.removeEventListener('animationend', handler);
                        panel.classList.remove('cc-panel-enter');
                    });
                }
            }
        });
        if (snapshot && !isDraftLocked()) visitedSteps[step] = true;
        refreshProgress();
        rootEl.querySelector('.cc-pad').classList.toggle('is-committing', phase === 'submitting' || phase === 'durable');
        rootEl.querySelectorAll('[data-cc-step]').forEach(function(item) {
            var itemStep = Number(item.getAttribute('data-cc-step'));
            var active = itemStep === step;
            if (active) item.setAttribute('aria-current', 'step');
            else item.removeAttribute('aria-current');
            var jump = item.querySelector('[data-cc-step-jump]');
            if (jump) jump.disabled = isDraftLocked() || itemStep === step;
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
            : (isRetryOnly() ? '重试保存' : (step === 2 ? '建立角色' : '下一步'));
        byId('cc-form').setAttribute('aria-busy', phase === 'starting' || phase === 'preparing'
            || phase === 'submitting' || phase === 'durable' ? 'true' : 'false');
        rootEl.querySelectorAll('input, .cc-equipped-slot, .cc-choice-card, .cc-appearance-tab, .cc-density-option, .cc-difficulty').forEach(function(control) {
            control.disabled = draftLocked;
        });
        byId('cc-display-reset').disabled = draftLocked;
        byId('cc-random-look').disabled = draftLocked;
        rootEl.querySelectorAll('#cc-hair-filter button').forEach(function(button) { button.disabled = draftLocked; });
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
        setText('cc-nameplate', model.draft.characterName.trim() || '未命名');
        setText('cc-preview-gender', model.draft.gender === 'female' ? '女性' : '男性');
        byId('cc-height').setAttribute('aria-valuetext', model.draft.height + ' 厘米');
        setText('cc-height-value', model.draft.height + ' cm');
        var hair = snapshot.hairCatalog[model.hairIndex];
        var hairName = hair ? hairDisplayParts(hair).name : '未知发型';
        setText('cc-preview-hair', hairName);
        var canvas = byId('cc-preview-canvas');
        var scale = Controls.previewScale(model.draft.height);
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
            ['difficulty', '难度', difficulty],
            ['identity', '外形', (gender === 'female' ? '女性' : '男性') + ' · ' + model.draft.height + ' cm · ' + hair.name],
            ['equipment', '服装', nameOf(snapshot.appearanceCatalog.upper[gender], model.draft.upperIdentifier)
                + ' · ' + nameOf(snapshot.appearanceCatalog.lower[gender], model.draft.lowerIdentifier)
                + ' · ' + nameOf(snapshot.appearanceCatalog.footwear[gender], model.draft.footwearIdentifier)]
        );
        paintSlotSignature();
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

    function paintSlotSignature() {
        var badge = byId('cc-slot-signature');
        if (!badge || !snapshot || !global.BootstrapSaveManager) return;
        global.BootstrapSaveManager.paintSignature(badge, snapshot.slotKey);
        badge.hidden = !badge.childElementCount;
    }

    function attachRenderer() {
        if (!manifest || renderer || !rootEl || !snapshot) return;
        var generation = previewGeneration;
        var token = activeOpenRequestId;
        try {
            renderer = global.CharacterAppearancePreview.create(byId('cc-preview-canvas'), {
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

    function onStageResize() {
        scheduleRendererScaleRefresh();
    }

    function attachScale() {
        // 同一逻辑画布已经缩放，装备浮签保留原来的逻辑字号。
        var style = global.document.documentElement.style;
        priorOverlayScale = style.getPropertyValue('--cf7-overlay-scale');
        ownsOverlayScale = true;
        style.setProperty('--cf7-overlay-scale', String(576 / 864));
        global.addEventListener('resize', onStageResize);
        scheduleRendererScaleRefresh();
    }

    function detachScale() {
        global.removeEventListener('resize', onStageResize);
        if (ownsOverlayScale) {
            var style = global.document.documentElement.style;
            if (priorOverlayScale) style.setProperty('--cf7-overlay-scale', priorOverlayScale);
            else style.removeProperty('--cf7-overlay-scale');
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
            if (previewChoice && previewChoice.button.isConnected && step === 1) {
                draft = Object.assign({}, draft);
                draft[previewChoice.key] = previewChoice.value;
            }
            lastRendererMeta = renderer.renderProfile(draft, {
                '上装装备':draft.upperIdentifier,
                '下装装备':draft.lowerIdentifier,
                '脚部装备':draft.footwearIdentifier
            }, {'脸型':draft.faceIdentifier, '发型':draft.hairIdentifier});
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
        visitedSteps = [true, false, false];
        validationAttempted = false;
        byId('cc-hair-search').value = '';
        byId('cc-hair-filter').dataset.selected = 'gender';
        setText('cc-nameplate', '未命名');
        appearanceDensity = loadAppearanceDensity();
        lastPanelStep = -1;
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
            appearanceDensity:appearanceDensity,
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
        global.addEventListener('pm19-decor-ready', paintSlotSignature);
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
