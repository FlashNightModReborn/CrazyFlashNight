/** Presentation-only header controller for InventoryWorkbench's tuning affordances. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchHeader = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function noop() {}

    // 锁定/禁用点击的即时反馈只能命令式播 cue('illegal'): 声明式 cue 会被
    // aria-disabled 统一抑制, 替换 data-audio-cue 是契约 §5.2 反模式; 无音频层时静默。
    function playBlockedCue() {
        if (typeof BootstrapAudio !== 'undefined' && BootstrapAudio
                && typeof BootstrapAudio.cue === 'function') {
            BootstrapAudio.cue('illegal');
        }
    }

    function action(visible, label, disabled, reason, pressed) {
        return {
            visible:!!visible,
            disabled:!!disabled,
            pressed:pressed == null ? null : !!pressed,
            label:label == null ? '' : String(label),
            reason:reason == null ? '' : String(reason)
        };
    }

    function createActionButton(document, id, label, handler, onBlocked) {
        var node = document.createElement('button');
        var activate = typeof handler === 'function' ? handler : noop;
        var explainBlocked = typeof onBlocked === 'function' ? onBlocked : noop;
        node.type = 'button';
        node.className = 'workbench-mode-btn';
        node.textContent = label;
        node.setAttribute('data-header-action', id);
        node.addEventListener('click', function(event) {
            var reason = node.getAttribute('data-header-disabled-reason') || '';
            if (node.getAttribute('aria-disabled') === 'true' && reason) {
                if (event && typeof event.preventDefault === 'function') {
                    event.preventDefault();
                }
                playBlockedCue();
                explainBlocked(reason);
                return;
            }
            activate(event);
        });
        return node;
    }

    function createActionGroups(options) {
        options = options || {};
        var document = options.document;
        var shell = options.shell;
        if (!document || !shell) throw new Error('Inventory header action groups require document and shell');
        var storageActions = document.createElement('div');
        storageActions.className = 'inventory-workbench-mode-actions';
        var buildActions = document.createElement('nav');
        buildActions.className = 'character-build-header-actions';
        buildActions.setAttribute('aria-label', '角色构筑视图');
        shell.addHeaderAction(storageActions);
        shell.addHeaderAction(buildActions);
        var buttons = {};
        function append(host, id, label, handler) {
            var node = createActionButton(
                document, id, label, handler, options.onBlocked);
            buttons[id] = node;
            host.appendChild(node);
            return node;
        }
        append(buildActions, 'storage', '收纳', options.onStorage);
        append(buildActions, 'stats', '个人信息', options.onStats);
        append(buildActions, 'skills', '技能配置', options.onSkills);
        append(buildActions, 'back-build', '← 返回构筑', options.onBackBuild).hidden = true;
        append(storageActions, 'return-build', '返回构筑', options.onReturnBuild).hidden = true;
        return {
            storageActions:storageActions,
            buildActions:buildActions,
            buttons:buttons
        };
    }

    function createCloseAction(document, shell, handler, onBlocked) {
        var close = createActionButton(document, 'close', '×', handler, onBlocked);
        close.className = 'workbench-close-btn';
        close.setAttribute('aria-label', '关闭工作台');
        close.setAttribute('data-audio-cue', 'back');
        shell.addHeaderAction(close);
        return close;
    }

    function createWorkbenchHeader(options) {
        options = options || {};
        var groups = createActionGroups(options);
        var buttons = groups.buttons;
        var helpAction = new options.components.HelpAction({
            shell:options.shell
        });
        buttons.help = helpAction.button;
        buttons.close = createCloseAction(
            options.document,
            options.shell,
            options.onClose,
            options.onBlocked);
        var preparationMenu = null;
        if (options.preparationNavigationV1) {
            preparationMenu =
                new options.preparationApi.PreparationMenuController({
                    document:options.document,
                    host:groups.buildActions,
                    uiData:options.uiData,
                    onSelect:options.onPreparationSelect,
                    onChange:options.onPreparationChange
                });
            groups.buildActions.insertBefore(
                preparationMenu.wrapper,
                buttons.stats);
            buttons['preparation-menu'] = preparationMenu.trigger;
        }
        var densityToggle = options.density.createToggle(options.onDensity);
        groups.storageActions.insertBefore(
            densityToggle,
            groups.storageActions.firstChild);
        var tuningHeader = null;
        if (options.profile.profile === 'battlebox') {
            tuningHeader = new TuningHeaderController({
                document:options.document,
                shell:{
                    addHeaderAction:function(node) {
                        groups.storageActions.appendChild(node);
                    }
                },
                view:options.view,
                onSwitch:options.onTuningSwitch,
                onBlocked:options.onBlocked
            });
        }
        return {
            storageActions:groups.storageActions,
            buildActions:groups.buildActions,
            buttons:buttons,
            helpAction:helpAction,
            densityToggle:densityToggle,
            tuningHeader:tuningHeader,
            preparationMenu:preparationMenu
        };
    }

    var PREPARATION_KEYS = Object.freeze([
        'equipment',
        'battlebox',
        'tuning',
        'skills',
        'materials',
        'intelligence'
    ]);
    var PREPARATION_DESTINATION_KINDS = Object.freeze({
        equipment:'current',
        battlebox:'local-view',
        tuning:'local-view',
        skills:'post-close',
        materials:'post-close',
        intelligence:'post-close'
    });

    function normalizePreparationAvailability(value) {
        if (!value || typeof value !== 'object'
                || Array.isArray(value)
                || Object.keys(value).length !== PREPARATION_KEYS.length) return null;
        var normalized = {};
        for (var i = 0; i < PREPARATION_KEYS.length; i++) {
            var key = PREPARATION_KEYS[i];
            var item = value[key];
            if (!item || typeof item !== 'object' || Array.isArray(item)
                    || Object.keys(item).length !== 3
                    || typeof item.visible !== 'boolean'
                    || typeof item.disabled !== 'boolean'
                    || typeof item.reason !== 'string') return null;
            normalized[key] = {
                visible:item.visible,
                disabled:item.disabled,
                reason:item.reason,
                current:key === 'equipment',
                destinationKind:PREPARATION_DESTINATION_KINDS[key]
            };
        }
        return normalized;
    }

    function InventoryWorkbenchHeaderProjection(state) {
        state = state || {};
        var view = state.view === 'build' || state.view === 'tuning'
            ? state.view : 'storage';
        var statsMode = !!state.statsMode;
        var buildMode = view === 'build' && !statsMode;
        var locked = buildMode && !!state.busy;
        var lockReason = locked
            ? String(state.reason || '构筑操作完成前不能切换视图。') : '';
        var closeLockReason = locked
            ? (state.reason
                ? String(state.reason) + '；完成后才能关闭工作台。'
                : '构筑操作完成前不能关闭工作台。')
            : '';
        var tuningState = state.tuningState || {};
        var preparationNavigationV1 = !!state.preparationNavigationV1;
        var preparationItems = preparationNavigationV1
            ? normalizePreparationAvailability(state.preparationAvailability)
            : null;
        if (preparationNavigationV1 && !preparationItems) {
            throw new Error('Preparation availability projection rejected');
        }
        var projection = {
            storage:action(buildMode && !preparationNavigationV1, '收纳', locked, lockReason),
            stats:action(buildMode, '个人信息', locked, lockReason),
            skills:action(buildMode && !preparationNavigationV1, '技能配置', locked, lockReason),
            'preparation-menu':action(
                buildMode && preparationNavigationV1,
                '整备 ▾',
                false,
                ''),
            'back-build':action(statsMode, '← 返回构筑', false, ''),
            'return-build':action(
                !statsMode && view !== 'build' && !!state.buildAvailable,
                '返回构筑', false, ''),
            tuning:action(
                !statsMode && view === 'storage' && !!state.tuningAvailable,
                '装备调制', !!tuningState.disabled, tuningState.reason || '',
                view === 'tuning'),
            help:action(true, '?', false, ''),
            close:action(true, '×', locked, closeLockReason)
        };
        projection.preparationItems = preparationItems;
        return projection;
    }

    function syncContextActions(options) {
        options = options || {};
        var helpAction = options.helpAction;
        var profile = options.profile;
        if (helpAction && profile) {
            helpAction.update({
                ariaLabel:options.statsMode || options.view === 'build'
                    ? '查看角色构筑帮助'
                    : options.view === 'tuning'
                        ? '查看装备调制帮助'
                        : '查看' + profile.title + '帮助',
                disabled:(options.view === 'storage' || options.view === 'tuning')
                    && !options.storageReady,
                onOpen:options.onHelp
            });
        }
        var densityToggle = options.densityToggle;
        var storageActions = options.storageActions;
        if (!densityToggle || !storageActions) return;
        var buildHost = options.buildHost;
        var target = options.view === 'build' && !options.statsMode && buildHost
            ? buildHost.querySelector(
                '[data-build-subview="tuning"] .character-build-tuning-heading [data-build-density-mount]')
                || buildHost.querySelector(
                    '.character-build-pane-tools [data-build-density-mount]')
            : null;
        target = target || storageActions;
        if (densityToggle.parentNode !== target) {
            target.insertBefore(densityToggle, target.firstChild);
        }
    }

    function renderWorkbenchHeader(state, updateChrome) {
        state = state || {};
        var storageState = state.storageState || {
            view:state.view,
            disabled:false
        };
        if (state.tuningHeader) state.tuningHeader.update(storageState);
        var projection = InventoryWorkbenchHeaderProjection({
            view:state.view,
            statsMode:state.statsMode,
            buildAvailable:!!state.buildAvailable,
            tuningAvailable:!!state.tuningHeader,
            tuningState:{
                disabled:!!storageState.disabled,
                reason:storageState.reason || ''
            },
            busy:state.busy,
            reason:state.reason,
            preparationNavigationV1:state.preparationNavigationV1,
            preparationAvailability:state.preparationMenu
                ? state.preparationMenu.getAvailability()
                : null
        });
        applyProjection(state.buttons, projection);
        if (state.preparationMenu) {
            state.preparationMenu.applyProjection(projection.preparationItems);
        }
        if (updateChrome && state.shell && state.root && state.profile) {
            var view = state.view;
            var statsMode = !!state.statsMode;
            state.shell.setProfile(statsMode || view === 'build'
                ? 'character-build'
                : view === 'tuning' ? 'library-decision' : 'transfer-pair');
            state.root.setAttribute(
                'data-workbench-view',
                statsMode ? 'stats' : view);
            state.root.setAttribute(
                'data-workbench-skin',
                view === 'build' || view === 'tuning' || statsMode
                    ? 'character'
                    : 'inventory');
            state.root.classList.toggle(
                'character-build-shell',
                view === 'build' || statsMode);
            state.root.querySelector('.workbench-header').classList.toggle(
                'character-build-header',
                view === 'build' || statsMode);
            state.storageActions.hidden = view === 'build' || statsMode;
            state.buildActions.hidden = view !== 'build' && !statsMode;
            if (statsMode) {
                state.shell.setTitle('个人信息', '角色档案 · 已应用构筑');
            } else if (view === 'build') {
                state.shell.setTitle('角色构筑', '装备与药剂 · 构筑预览');
            } else if (view === 'tuning') {
                state.shell.setTitle('装备调制', '背包装备 · DLS 调制终端');
            } else {
                state.shell.setTitle(state.profile.title, '');
            }
            state.shell.setSlotLabel(
                'R',
                view === 'build' ? '候选对比'
                    : view === 'tuning' ? '调制操作' : state.profile.title);
            if (state.preparationMenu) {
                state.preparationMenu.setSuppressed(
                    view !== 'build'
                    || statsMode
                    || state.shell.hasModal());
            }
        }
        syncContextActions({
            helpAction:state.helpAction,
            profile:state.profile,
            statsMode:state.statsMode,
            view:state.view,
            storageReady:state.storageReady,
            onHelp:state.onHelp,
            densityToggle:state.densityToggle,
            storageActions:state.storageActions,
            buildHost:state.buildHost
        });
        return projection;
    }

    function restoreAriaLabel(node) {
        if (!node.hasAttribute('data-header-base-aria-label')) return;
        var base = node.getAttribute('data-header-base-aria-label');
        if (base) node.setAttribute('aria-label', base);
        else node.removeAttribute('aria-label');
        node.removeAttribute('data-header-base-aria-label');
    }

    function applyProjection(buttons, projection) {
        buttons = buttons || {};
        projection = projection || {};
        Object.keys(buttons).forEach(function(id) {
            var node = buttons[id];
            var state = projection[id] || action(false, '', true, '');
            if (!node) return;
            node.hidden = !state.visible;
            if (state.label && id !== 'help' && id !== 'close') {
                node.textContent = state.label;
            }
            var explainable = state.disabled && !!state.reason;
            node.disabled = state.disabled && !explainable;
            if (state.disabled) {
                node.setAttribute('aria-disabled', 'true');
                if (!node.hasAttribute('data-header-base-aria-label')) {
                    node.setAttribute(
                        'data-header-base-aria-label',
                        node.getAttribute('aria-label') || '');
                }
                var baseAriaLabel =
                    node.getAttribute('data-header-base-aria-label') || '';
                node.setAttribute(
                    'aria-label',
                    (baseAriaLabel || state.label)
                        + (state.reason ? '，不可用：' + state.reason : '，不可用'));
                if (state.reason) {
                    node.setAttribute('title', state.reason);
                    node.setAttribute('data-header-disabled-reason', state.reason);
                } else {
                    node.removeAttribute('title');
                    node.removeAttribute('data-header-disabled-reason');
                }
            } else {
                if (id === 'storage') node.setAttribute('aria-disabled', 'false');
                else node.removeAttribute('aria-disabled');
                node.removeAttribute('title');
                node.removeAttribute('data-header-disabled-reason');
                restoreAriaLabel(node);
            }
            if (state.pressed == null) node.removeAttribute('aria-pressed');
            else node.setAttribute('aria-pressed', state.pressed ? 'true' : 'false');
        });
        return projection;
    }

    function TuningHeaderController(options) {
        options = options || {};
        if (!options.document || !options.shell) throw new Error('TuningHeaderController requires document and shell ports');
        this._document = options.document;
        this._shell = options.shell;
        this._onSwitch = typeof options.onSwitch === 'function' ? options.onSwitch : noop;
        this._onBlocked = typeof options.onBlocked === 'function' ? options.onBlocked : noop;
        this._view = options.view === 'tuning' ? 'tuning' : 'storage';
        this._disabled = !!options.disabled;
        this._disabledReason = '';
        this._listeners = [];
        this.switchButton = this._createSwitchButton();
        this._shell.addHeaderAction(this.switchButton);
        this.update({view:this._view});
    }

    TuningHeaderController.prototype._listen = function(node, type, handler) {
        node.addEventListener(type, handler);
        this._listeners.push(function() { node.removeEventListener(type, handler); });
    };
    TuningHeaderController.prototype._createSwitchButton = function() {
        var self = this;
        var button = this._document.createElement('button');
        button.type = 'button';
        button.className = 'workbench-mode-btn equipment-tuning-view-switch';
        button.setAttribute('data-workbench-key', 'tuning-switch');
        button.setAttribute('data-audio-cue', 'select');
        this._listen(button, 'click', function(event) {
            if (self._disabled) {
                playBlockedCue();
                self._onBlocked(self._disabledReason || '当前状态不能切换收纳与调制。');
                return;
            }
            self._onSwitch(
                self._view === 'tuning' ? 'storage' : 'tuning',
                event && event.currentTarget || button);
        });
        return button;
    };
    TuningHeaderController.prototype.update = function(state) {
        state = state || {};
        if (state.view === 'storage' || state.view === 'tuning') this._view = state.view;
        this.switchButton.textContent =
            this._view === 'tuning' ? '战备箱与背包' : '装备调制';
        this.switchButton.setAttribute('aria-pressed', this._view === 'tuning' ? 'true' : 'false');
        if (state.disabled != null) this._disabled = !!state.disabled;
        this._disabledReason = this._disabled ? String(state.reason || '') : '';
        this.switchButton.disabled = this._disabled && !this._disabledReason;
        this.switchButton.setAttribute('aria-disabled', this._disabled ? 'true' : 'false');
        if (this._disabledReason) {
            this.switchButton.setAttribute('title', this._disabledReason);
            this.switchButton.setAttribute(
                'aria-label',
                this.switchButton.textContent + '，不可用：' + this._disabledReason
            );
        } else {
            this.switchButton.removeAttribute('title');
            this.switchButton.removeAttribute('aria-label');
        }
        return true;
    };
    TuningHeaderController.prototype.destroy = function() {
        for (var i = this._listeners.length - 1; i >= 0; i--) this._listeners[i]();
        this._listeners = [];
        return true;
    };

    return {
        createActionButton:createActionButton,
        createActionGroups:createActionGroups,
        createCloseAction:createCloseAction,
        createWorkbenchHeader:createWorkbenchHeader,
        PREPARATION_KEYS:PREPARATION_KEYS,
        normalizePreparationAvailability:normalizePreparationAvailability,
        InventoryWorkbenchHeaderProjection:InventoryWorkbenchHeaderProjection,
        syncContextActions:syncContextActions,
        renderWorkbenchHeader:renderWorkbenchHeader,
        applyProjection:applyProjection,
        TuningHeaderController:TuningHeaderController
    };
});
