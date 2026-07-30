/** Single parent/facade for storage, tuning and character-build editing. */
var InventoryWorkbench = (function() {
    'use strict';

    var _scaleEl, _scale, _shell, _root, _body, _buildHost, _storageActions, _buildActions;
    var _densityToggle, _helpAction;
    var _density, _tuningHeader, _preparationMenu, _storageReady = false, _build = null;
    var _profile, _view = 'storage', _panelInstanceId = '', _navigation = null;
    var _runtimeConfig = (typeof window !== 'undefined'
        && window.__INVENTORY_WORKBENCH_CONFIG__) || {};
    var _activationEpoch = 0;
    var _closing = false, _statsMode = false, _closeSent = false, _buttons = {};
    var _buildInteractionLocked = false, _buildLockReason = '';
    var _preparationNavigationV1 = false;
    var _featureGate = null;

    function toast(message) {
        if (typeof Toast !== 'undefined') Toast.add(message);
    }

    function active() {
        return Panels.getActive
            ? Panels.getActive() === 'workbench'
            : Panels.isOpen();
    }

    function create() {
        _scaleEl = document.createElement('div');
        _scaleEl.className =
            'panel-scale-shell kshop-scale-shell inventory-workbench-scale-shell';
        return _scaleEl;
    }

    function clear(node) {
        while (node && node.firstChild) node.removeChild(node.firstChild);
    }

    function featureLoading() {
        return !!(_featureGate && _featureGate.isLoading());
    }

    function storageHeaderState() {
        var state = _storageReady
            ? InventoryStorageWorkbench.getHeaderState()
            : {view:_view, disabled:false};
        return !featureLoading() ? state : {view:state.view, disabled:true,
            reason:'工作台功能资源正在加载，请稍候。'};
    }

    function headerState() {
        return {
            shell:_shell,
            root:_root,
            profile:_profile,
            view:_view,
            statsMode:_statsMode,
            storageActions:_storageActions,
            buildActions:_buildActions,
            storageState:storageHeaderState(),
            storageReady:_storageReady,
            buildAvailable:!!(_navigation && _navigation.canReturnTo('build')),
            tuningHeader:_tuningHeader,
            buttons:_buttons,
            busy:_buildInteractionLocked || featureLoading(),
            reason:featureLoading()
                ? '工作台功能资源正在加载，请稍候。' : _buildLockReason,
            preparationNavigationV1:_preparationNavigationV1,
            preparationMenu:_preparationMenu,
            helpAction:_helpAction,
            densityToggle:_densityToggle,
            buildHost:_buildHost,
            onHelp:function() {
                if (featureLoading()) return false;
                return (_view === 'build' || _statsMode) && _build
                    ? _build.openHelp() : InventoryStorageWorkbench.openHelp();
            }
        };
    }

    function refreshHeader() {
        InventoryWorkbenchHeader.renderWorkbenchHeader(
            headerState(),
            false);
    }

    function storageViewChanged(next) {
        if (_navigation && _navigation.storageChanged(next)) return;
        toast('收到无效视图状态，请关闭工作台后重试。');
    }

    function updateChrome() {
        if (!_shell || !_profile) return;
        InventoryWorkbenchHeader.renderWorkbenchHeader(
            headerState(),
            true);
    }

    function makeHeader() {
        var header = InventoryWorkbenchHeader.createWorkbenchHeader({
            document:document, shell:_shell,
            components:WorkbenchComponents,
            density:_density,
            profile:_profile,
            view:_view,
            onStorage:function(event) {
                requestView('storage', {
                    origin:'header',
                    opener:event && event.currentTarget || _buttons.storage
                });
            },
            onStats:function() { if (_build) _build.openStats(_buttons.stats); },
            onSkills:requestSkillsNavigation,
            onBackBuild:function() { if (_build) _build.closeStats('back'); },
            onReturnBuild:function(event) {
                requestView('build', {
                    origin:'header',
                    opener:event && event.currentTarget || _buttons['return-build']
                });
            },
            onClose:function() { requestClose('header'); },
            preparationNavigationV1:_preparationNavigationV1,
            preparationApi:typeof InventoryWorkbenchPreparationMenu !== 'undefined'
                ? InventoryWorkbenchPreparationMenu : null,
            uiData:typeof UiData !== 'undefined' ? UiData : null,
            onPreparationSelect:selectPreparation,
            onPreparationChange:refreshHeader,
            onDensity:function(mode) {
                if (_root) _root.setAttribute('data-layout-mode', mode);
                if (_build) _build.setDensity(mode);
            },
            onTuningSwitch:function(next, opener) {
                requestView(next, {origin:'header', opener:opener});
            },
            onBlocked:toast
        });
        _storageActions = header.storageActions;
        _buildActions = header.buildActions;
        _buttons = header.buttons;
        _helpAction = header.helpAction;
        _densityToggle = header.densityToggle;
        _tuningHeader = header.tuningHeader;
        _preparationMenu = header.preparationMenu;
        refreshHeader();
    }

    function controllerPorts() {
        return {
            shell:_shell,
            root:_root,
            profileConfig:_profile,
            panelInstanceId:_panelInstanceId,
            densityController:_density,
            addHeaderAction:function(node) {
                if (_storageActions && node) {
                    _storageActions.appendChild(node);
                }
            },
            refreshHeader:refreshHeader,
            onViewChanged:storageViewChanged,
            isPanelActive:active
        };
    }

    function ensureStorage(initialView) {
        if (_storageReady) {
            return initialView === InventoryStorageWorkbench.getView()
                || InventoryStorageWorkbench.switchView(initialView);
        }
        _storageReady = InventoryStorageWorkbench.activate(
            controllerPorts(),
            initialView);
        refreshHeader();
        return _storageReady;
    }

    function buildPorts() {
        var activationEpoch = _activationEpoch;
        return {
            shell:_shell,
            getDensity:function() {
                return _density.mode;
            },
            syncDensityToggle:refreshHeader,
            setStatus:function(text, state) { _shell.setStatus(text, state); },
            setInteractionLocked:function(locked, reason) {
                _buildInteractionLocked = !!locked;
                _buildLockReason = _buildInteractionLocked ? String(reason || '') : '';
                if (_preparationMenu) {
                    _preparationMenu.updateLock(
                        _buildInteractionLocked,
                        _buildLockReason);
                }
                refreshHeader();
            },
            beginExternalWrite:function(owner) { return _storageReady
                ? InventoryStorageWorkbench.beginExternalWrite(owner) : {detached:true}; },
            completeExternalWrite:function(operation, snapshots, callback, needsRefresh) {
                if (operation && operation.detached === true) {
                    if (callback) callback({success:true, refreshed:false});
                    return true;
                }
                return _storageReady && InventoryStorageWorkbench.completeExternalWrite(
                    operation, snapshots, callback, needsRefresh);
            },
            refreshExternalInventory:function(callback) { return !_storageReady ? (callback({success:true, refreshed:false}), true) : InventoryStorageWorkbench.refreshExternalInventory(callback); },
            requestClose:requestClose,
            statsMode:statsMode,
            onSessionState:function(_, reason) {
                if (reason === 'opened' || reason === 'snapshot') {
                    setTimeout(function() {
                        acceptBuildMount(_panelInstanceId, activationEpoch);
                    }, 0);
                }
            },
            onMountFailed:function(panelInstanceId, response) {
                rejectBuildMount(panelInstanceId, activationEpoch, response);
            },
            openModal:function(spec) {
                if (_preparationMenu) _preparationMenu.close(false);
                return _shell.openModal(spec);
            },
            toast:function(message, command) {
                if (command === 'snapshot') rejectBuildMount(
                    _panelInstanceId, activationEpoch);
                toast(message);
            }
        };
    }

    function acceptBuildMount(panelInstanceId, activationEpoch) {
        if (activationEpoch !== _activationEpoch
                || String(panelInstanceId || '') !== _panelInstanceId) return;
        if (_navigation) _navigation.buildReady();
    }

    function rejectBuildMount(panelInstanceId, activationEpoch) {
        setTimeout(function() {
            if (activationEpoch !== _activationEpoch
                    || String(panelInstanceId || '') !== _panelInstanceId) return;
            if (_navigation && _navigation.buildFailed()) return;
            if (Panels.rejectActiveMount) {
                Panels.rejectActiveMount('workbench', _panelInstanceId);
            }
        }, 0);
    }

    function ensureBuild() {
        if (!_build) {
            _build = new CharacterBuild.CharacterBuildController({
                document:document,
                send:function(message) {
                    return Bridge.send(message);
                },
                router:PanelRuntime.sharedResponseRouter,
                timeoutMs:_runtimeConfig.requestTimeoutMs,
                sessionNonce:_runtimeConfig.sessionNonce,
                ports:buildPorts()
            });
        }
        return _build;
    }

    function createNavigation(viewStack) {
        _navigation = InventoryWorkbenchNavigation.create({
            document:document,
            getRoot:function() { return _root; },
            stack:viewStack,
            view:_view,
            storage:InventoryStorageWorkbench,
            ensureStorage:ensureStorage,
            storageReady:function() { return _storageReady; },
            ensureBuild:ensureBuild,
            getBuild:function() { return _build; },
            body:_body,
            buildHost:_buildHost,
            panelInstanceId:_panelInstanceId,
            getView:function() { return _view; },
            onView:function(next) {
                _view = next;
                refreshHeader();
                updateChrome();
            },
            toast:toast
        });
    }

    function requestView(next, options) {
        if (_preparationMenu) _preparationMenu.close(false);
        if (_navigation && _navigation.rejectIfPending()) return false;
        if (_buildInteractionLocked && _view === 'build') {
            if (next === 'storage' || next === 'tuning') toast(_buildLockReason
                || (next === 'storage' ? '构筑操作完成前不能进入收纳。' : '构筑操作完成前不能进入背包装备调制。'));
            return false;
        }
        if (_closing || featureLoading()
                || (next !== 'storage' && next !== 'tuning' && next !== 'build')
                || next === _view) {
            return false;
        }
        return !!(_featureGate && _featureGate.run(next, function() {
            return _navigation && _navigation.request(next, options);
        }, {initial:false}));
    }

    function statsMode(activeStats, statsRoot, opener) {
        var header = _root.querySelector('.workbench-header');
        if (_preparationMenu) _preparationMenu.close(false);
        _statsMode = !!activeStats;
        if (_statsMode) statsRoot.insertBefore(header, statsRoot.firstChild);
        else _root.insertBefore(header, _root.firstChild);
        updateChrome();
        return _statsMode ? _buttons['back-build'] : opener;
    }

    function finishClose(reason) {
        if (_closeSent) return false;
        _closeSent = true;
        var message = InventoryWorkbenchConfig.createCloseMessage(
            _panelInstanceId, reason);
        if (Bridge.send(message) === false) {
            _closeSent = false;
            toast('启动器连接不可用，工作台保持打开。');
            return false;
        }
        Panels.close();
        return true;
    }

    function finalizeClose(reason) {
        if (!_build) return finishClose(reason);
        if (_build.canClose()) return finishClose(reason);
        _closing = true;
        var callId = _build.finalize(function(accepted) {
            _closing = false;
            if (accepted) finishClose(reason);
        });
        if (!callId) {
            _closing = false;
            toast('角色构筑仍在同步，请稍候关闭。');
        }
        return !!callId;
    }

    function requestPreparationNavigation(reason) {
        if (_view !== 'build' || !_build || _closing) return false;
        if (_buildInteractionLocked) {
            toast(_buildLockReason || '构筑操作完成前不能切换整备目标。');
            return false;
        }
        if (_statsMode) _build.closeStats(reason);
        return requestClose(reason);
    }

    function requestSkillsNavigation() {
        return requestPreparationNavigation('navigate_skills');
    }

    function selectPreparation(identity, opener) {
        switch (identity) {
        case 'equipment': return false;
        case 'battlebox': return requestView(
            'storage', {origin:'preparation-menu',
                opener:_preparationMenu && _preparationMenu.trigger || opener});
        case 'tuning': return requestView(
            'tuning', {origin:'preparation-menu',
                opener:_preparationMenu && _preparationMenu.trigger || opener});
        case 'skills': return requestSkillsNavigation();
        case 'materials': return requestPreparationNavigation('navigate_materials');
        case 'intelligence': return requestPreparationNavigation('navigate_intelligence');
        default: return false;
        }
    }

    function requestClose(reason) {
        if (reason === 'escape' && _preparationMenu
                && _preparationMenu.consumeEscape()) return true;
        if (_preparationMenu) _preparationMenu.close(false);
        if (_closing) return false;
        if (_navigation && _navigation.rejectIfPending()) return false;
        if (_shell && _shell.hasModal()) {
            return _shell.closeModal(reason || 'close');
        }
        if (reason === 'escape' && _view === 'build'
                && _build && _build.consumeEscape()) {
            return true;
        }
        if (reason === 'escape' && _view !== 'build'
                && InventoryStorageWorkbench.consumeEscape()) return true;
        var returnPlan = reason === 'escape' && _navigation
            ? _navigation.returnPlan('escape') : null;
        if (returnPlan) {
            return requestView(returnPlan.entry.viewId, {
                origin:'escape',
                opener:document.activeElement,
                plan:returnPlan
            });
        }
        if (_storageReady && _view !== 'build') {
            return InventoryStorageWorkbench.prepareClose(reason, function(ready) {
                if (!ready) return;
                finalizeClose(reason);
            });
        }
        return finalizeClose(reason);
    }

    function teardown() {
        _activationEpoch++;
        if (_storageReady) InventoryStorageWorkbench.deactivate();
        if (_build) _build.destroy();
        if (_tuningHeader) _tuningHeader.destroy();
        if (_preparationMenu) _preparationMenu.destroy();
        if (_density) _density.destroy();
        if (_scale) _scale.detach();
        if (_helpAction) _helpAction.destroy();
        if (_shell) _shell.destroy();
        _storageReady = false; _build = null; _tuningHeader = null;
        _preparationMenu = null;
        _density = null; _densityToggle = null; _helpAction = null; _scale = null;
        _shell = null; _root = null; _body = null; _buildHost = null;
        _closing = false;
        _statsMode = false;
        _buttons = {};
        _buildInteractionLocked = false;
        _buildLockReason = '';
        _preparationNavigationV1 = false;
        _profile = null;
        _view = 'storage';
        if (_navigation) _navigation.destroy();
        _navigation = null;
        _panelInstanceId = '';
        if (_featureGate) _featureGate.cancel();
        _featureGate = null;
        _closeSent = false;
        clear(_scaleEl);
    }

    function activate(el, initData) {
        initData = initData || {};
        var launch = InventoryWorkbenchConfig.resolveLaunchContext(initData);
        if (!launch) {
            toast('工作台参数无效，已取消打开。');
            return false;
        }
        _activationEpoch++;
        var activationEpoch = _activationEpoch;
        _profile = launch.profile;
        _view = launch.view;
        _preparationNavigationV1 = launch.preparationNavigationV1;
        var viewStack = new InventoryWorkbenchConfig.WorkbenchViewStack({
            viewId:_view, origin:'launch',
            focusKey:launch.returnFocusAction
                ? 'header:' + launch.returnFocusAction : ''
        });
        _panelInstanceId = launch.panelInstanceId;
        _closeSent = false;
        _shell = new Workbench.DualPaneShell({
            profile:_view === 'build' ? 'character-build'
                : _view === 'tuning' ? 'library-decision' : 'transfer-pair',
            title:_profile.title,
            status:'同步中',
            leftLabel:'背包',
            rightLabel:_profile.title
        });
        _root = _shell.getRoot();
        _root.classList.add(
            'kshop-workbench',
            'inventory-workbench-panel');
        _root.setAttribute('data-workbench-skin', 'inventory');
        _scaleEl.appendChild(_root);

        _body = _root.querySelector('.workbench-body');
        _buildHost = document.createElement('section');
        _buildHost.className = 'character-build-host';
        _buildHost.hidden = true;
        _root.insertBefore(_buildHost, _root.querySelector('.workbench-modal-layer'));
        _density = new Workbench.GridDensityController({
            panelId:'workbench',
            defaultMode:'compact'
        });
        _root.setAttribute('data-layout-mode', _density.mode);
        makeHeader();
        createNavigation(viewStack);
        _featureGate = InventoryWorkbenchFeatureLoader.createPanelGate({
            isLive:function() { return activationEpoch === _activationEpoch && active(); },
            shell:_shell, refresh:refreshHeader, update:updateChrome, toast:toast,
            reject:function() {
                if (Panels.rejectActiveMount)
                    Panels.rejectActiveMount('workbench', _panelInstanceId);
            }
        });
        _scale = typeof PanelScale !== 'undefined'
            ? PanelScale.attach(_scaleEl, 1024, 576)
            : null;
        function mountInitial() {
            var accepted = _view === 'build'
                ? _navigation.mountInitialBuild() : ensureStorage(_view);
            if (accepted !== false && _view === 'build') {
                if (launch.returnFocusAction === 'skills') _buttons.skills.focus();
                else if (launch.returnFocusAction === 'preparation-menu'
                        && _preparationMenu) _preparationMenu.focusTrigger();
            }
            return accepted;
        }
        var mounted = _view === 'storage'
            ? mountInitial()
            : _featureGate.run(_view, mountInitial, {initial:true});
        updateChrome();
        return mounted !== false;
    }

    function rebind(el, initData) {
        teardown();
        return activate(el, initData);
    }

    Panels.register('workbench', {
        create:create,
        onOpen:activate,
        onRebind:rebind,
        onClose:teardown,
        onRequestClose:requestClose,
        onForceClose:function() {
            toast('连接断开，物品工作台已关闭');
        }
    });

    return {
        debugState:function() {
            var storage = _storageReady
                ? InventoryStorageWorkbench.debugState()
                : null;
            var state = Object.assign({}, storage || {});
            state.profile = _profile && _profile.profile;
            state.view = _view;
            state.panelInstanceId = _panelInstanceId;
            state.hostOwner = 'workbench';
            state.featureLoading = featureLoading();
            state.closing = _closing;
            state.buildInteractionLocked = _buildInteractionLocked;
            state.buildLockReason = _buildLockReason;
            state.storage = storage;
            state.build = _build ? _build.debugState() : null;
            state.viewStack = _navigation ? _navigation.snapshot() : [];
            state.viewTransition = _navigation ? _navigation.debugState() : null;
            return state;
        }
    };
})();
