/** Single parent/facade for storage, tuning and character-build editing. */
var InventoryWorkbench = (function() {
    'use strict';

    var _scaleEl, _scale, _shell, _root, _body, _buildHost, _storageActions, _buildActions;
    var _densityToggle;
    var _density, _tuningHeader, _storageReady = false, _build = null;
    var _profile, _view = 'storage', _panelInstanceId = '', _returnTarget = null;
    var _runtimeConfig = (typeof window !== 'undefined'
        && window.__INVENTORY_WORKBENCH_CONFIG__) || {};
    var _activationEpoch = 0;
    var _closing = false, _statsMode = false, _closeSent = false, _buttons = {};
    var _buildInteractionLocked = false, _buildLockReason = '';

    function toast(message) {
        if (typeof Toast !== 'undefined') Toast.add(message);
    }

    function active() {
        return Panels.getActive
            ? Panels.getActive() === 'workbench'
            : Panels.isOpen();
    }

    function validInstance(value) {
        return /^[A-Za-z0-9._~-]{1,128}$/.test(String(value || ''));
    }

    function add(host, node) {
        if (host && node) host.appendChild(node);
        return node;
    }

    function button(id, label, handler) {
        var node = document.createElement('button');
        node.type = 'button';
        node.className = 'workbench-mode-btn';
        node.textContent = label;
        node.setAttribute('data-header-action', id);
        node.addEventListener('click', handler);
        _buttons[id] = node;
        return node;
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

    function storageHeaderState() {
        return _storageReady
            ? InventoryStorageWorkbench.getHeaderState()
            : {view:_view, confirmationMode:'safe', disabled:false};
    }

    function refreshHeader() {
        var state = storageHeaderState();
        if (_tuningHeader) _tuningHeader.update(state);
        if (_buttons['return-build']) {
            _buttons['return-build'].hidden = !_build || state.view !== 'storage';
        }
    }

    function storageViewChanged(next) {
        _view = next;
        refreshHeader();
        updateChrome();
    }

    function updateChrome() {
        if (!_shell || !_profile) return;
        _root.setAttribute('data-workbench-view', _statsMode ? 'stats' : _view);
        _root.setAttribute('data-workbench-skin',
            _view === 'build' || _view === 'tuning' || _statsMode ? 'character' : 'inventory');
        _root.classList.toggle(
            'character-build-shell',
            _view === 'build' || _statsMode);
        _root.querySelector('.workbench-header').classList.toggle(
            'character-build-header',
            _view === 'build' || _statsMode);
        _storageActions.hidden = _view === 'build' || _statsMode;
        _buildActions.hidden = _view !== 'build' && !_statsMode;
        if (_statsMode) {
            _shell.setTitle('个人信息', '角色档案 · 已应用构筑');
        } else if (_view === 'build') {
            _shell.setTitle('角色构筑', '装备与药剂 · 构筑预览');
        } else if (_view === 'tuning') {
            _shell.setTitle('装备调制', '背包装备 · DLS 调制终端');
        } else {
            _shell.setTitle(_profile.title, '');
        }
        _shell.setSlotLabel('R', _view === 'build' ? '候选对比'
            : _view === 'tuning' ? '调制操作' : _profile.title);
        syncDensityToggle();
    }

    function syncDensityToggle() {
        if (!_densityToggle || !_storageActions) return;
        var target = _view === 'build' && !_statsMode && _buildHost
            ? _buildHost.querySelector(
                '[data-build-subview="tuning"] .character-build-tuning-heading [data-build-density-mount]')
                || _buildHost.querySelector(
                    '.character-build-pane-tools [data-build-density-mount]') : null;
        target = target || _storageActions;
        if (_densityToggle.parentNode !== target) target.insertBefore(_densityToggle, target.firstChild);
    }

    function makeHeader() {
        _storageActions = document.createElement('div');
        _storageActions.className = 'inventory-workbench-mode-actions';
        _buildActions = document.createElement('nav');
        _buildActions.className = 'character-build-header-actions';
        _buildActions.setAttribute('aria-label', '角色构筑视图');
        _shell.addHeaderAction(_storageActions);
        _shell.addHeaderAction(_buildActions);

        add(_buildActions, button('storage', '收纳', function() {
            requestView('storage');
        }));
        add(_buildActions, button('stats', '个人信息', function() {
            if (_build) _build.openStats(_buttons.stats);
        }));
        add(_buildActions, button('back-build', '← 返回构筑', function() {
            if (_build) _build.closeStats('back');
        })).hidden = true;
        var buildHelp = add(_buildActions, button('help', '?', function() {
            if (_build) _build.openHelp();
        }));
        buildHelp.setAttribute('aria-label', '角色构筑帮助');
        add(_storageActions, button('return-build', '返回构筑', function() {
            requestView('build');
        })).hidden = true;

        if (_returnTarget) {
            var returnButton = add(
                _storageActions,
                button('return-panel', '返回合成', returnToPanel));
            returnButton.classList.add('inventory-return-crafting-btn');
            returnButton.setAttribute(
                'aria-label',
                '返回合成并重新核算原配方与份数');
        }

        var close = button('close', '×', function() {
            requestClose('header');
        });
        close.className = 'workbench-close-btn';
        close.setAttribute('aria-label', '关闭工作台');
        close.setAttribute('data-audio-cue', 'cancel');
        _shell.addHeaderAction(close);

        _densityToggle = _density.createToggle(function(mode) {
            if (_root) _root.setAttribute('data-layout-mode', mode);
            if (_build) _build.setDensity(mode);
        });
        _storageActions.insertBefore(_densityToggle, _storageActions.firstChild);

        if (_profile.profile === 'battlebox') {
            _tuningHeader = new InventoryWorkbenchHeader.TuningHeaderController({
                document:document,
                shell:{
                    addHeaderAction:function(node) {
                        add(_storageActions, node);
                    }
                },
                view:_view,
                confirmationMode:'safe',
                onSwitch:requestView,
                onHelp:function() {
                    InventoryStorageWorkbench.openHelp();
                },
                onConfirmationChange:function(mode) {
                    InventoryStorageWorkbench.setConfirmationMode(mode, false);
                }
            });
        }
    }

    function controllerPorts() {
        return {
            shell:_shell,
            root:_root,
            profileConfig:_profile,
            panelInstanceId:_panelInstanceId,
            densityController:_density,
            addHeaderAction:function(node) {
                add(_storageActions, node);
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
            syncDensityToggle:syncDensityToggle,
            setStatus:function(text, state) {
                _shell.setStatus(text, state);
            },
            setInteractionLocked:function(locked, reason) {
                _buildInteractionLocked = !!locked;
                _buildLockReason = _buildInteractionLocked ? String(reason || '') : '';
                for (var key in _buttons) {
                    var explainable = key === 'storage' && _view === 'build';
                    _buttons[key].disabled = _buildInteractionLocked && !explainable;
                    if (explainable) {
                        _buttons[key].setAttribute('aria-disabled',
                            _buildInteractionLocked ? 'true' : 'false');
                        _buttons[key].setAttribute('aria-label', _buildInteractionLocked
                            ? '收纳，不可用：' + _buildLockReason : '收纳');
                    }
                }
            },
            beginExternalWrite:function(owner) {
                return _storageReady
                    ? InventoryStorageWorkbench.beginExternalWrite(owner) : {detached:true};
            },
            completeExternalWrite:function(operation, snapshots) {
                return operation && operation.detached === true ? true
                    : _storageReady && InventoryStorageWorkbench.completeExternalWrite(
                        operation, snapshots);
            },
            requestClose:requestClose,
            statsMode:statsMode,
            onMountFailed:function(panelInstanceId) {
                rejectBuildMount(panelInstanceId, activationEpoch);
            },
            openModal:function(spec) {
                return _shell.openModal(spec);
            },
            toast:toast
        };
    }

    function rejectBuildMount(panelInstanceId, activationEpoch) {
        setTimeout(function() {
            if (activationEpoch === _activationEpoch
                    && String(panelInstanceId || '') === _panelInstanceId
                    && Panels.rejectActiveMount) {
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

    function showBuild() {
        _body.hidden = true;
        _buildHost.hidden = false;
        _view = 'build';
        updateChrome();
        var activated = ensureBuild().activate(_buildHost, _panelInstanceId);
        syncDensityToggle();
        return activated;
    }

    function showStorage() {
        if (_build) _build.suspend();
        _buildHost.hidden = true;
        _body.hidden = false;
        if (!ensureStorage('storage')) return false;
        _view = InventoryStorageWorkbench.getView();
        updateChrome();
        return true;
    }

    function requestView(next) {
        if (_buildInteractionLocked && _view === 'build') {
            if (next === 'storage') toast(_buildLockReason
                || '构筑操作完成前不能进入收纳。');
            return false;
        }
        if (_closing
                || (next !== 'storage' && next !== 'tuning' && next !== 'build')
                || next === _view) {
            return false;
        }
        if (next === 'build') {
            if (!_build || !_storageReady || !_build.canLeave()) return false;
            return InventoryStorageWorkbench.prepareLeave(
                'build',
                function(ready) {
                    if (ready) showBuild();
                });
        }
        if (_view === 'build') {
            return next === 'storage' && !!_build.prepareLeave(function(ready) {
                if (ready) showStorage();
            });
        }
        return _storageReady
            ? InventoryStorageWorkbench.switchView(next)
            : ensureStorage(next);
    }

    function statsMode(activeStats, statsRoot, opener) {
        var header = _root.querySelector('.workbench-header');
        _statsMode = !!activeStats;
        _buttons.storage.hidden = _statsMode;
        _buttons.stats.hidden = _statsMode;
        _buttons['back-build'].hidden = !_statsMode;
        if (_statsMode) statsRoot.insertBefore(header, statsRoot.firstChild);
        else _root.insertBefore(header, _root.firstChild);
        updateChrome();
        return _statsMode ? _buttons['back-build'] : opener;
    }

    function finishClose() {
        if (_closeSent) return false;
        _closeSent = true;
        var instance = _panelInstanceId;
        Panels.close();
        Bridge.send({
            type:'panel',
            cmd:'close',
            panel:'workbench',
            panelInstanceId:instance
        });
        return true;
    }

    function openReturnTarget() {
        if (!_returnTarget) return false;
        var target = _returnTarget;
        _returnTarget = null;
        Panels.open(target.panel, target.initData);
        return true;
    }

    function returnToPanel() {
        return !!(_returnTarget
            && _storageReady
            && InventoryStorageWorkbench.prepareClose(
                'return',
                function(ready) {
                    if (ready) openReturnTarget();
                }));
    }

    function finalizeClose() {
        if (!_build) return finishClose();
        if (_build.canClose()) return finishClose();
        _closing = true;
        var callId = _build.finalize(function(accepted) {
            _closing = false;
            if (accepted) finishClose();
        });
        if (!callId) {
            _closing = false;
            toast('角色构筑仍在同步，请稍候关闭。');
        }
        return !!callId;
    }

    function requestClose(reason) {
        if (_closing) return false;
        if (_shell && _shell.hasModal()) {
            return _shell.closeModal(reason || 'close');
        }
        if (reason === 'escape' && _build && _view !== 'build') {
            return requestView('build');
        }
        if (reason === 'escape' && _view === 'build'
                && _build && _build.consumeEscape()) {
            return true;
        }
        if (_storageReady && _view !== 'build') {
            return InventoryStorageWorkbench.prepareClose(reason, function(ready) {
                if (!ready) return;
                if (_returnTarget && reason !== 'header') openReturnTarget();
                else finalizeClose();
            });
        }
        return finalizeClose();
    }

    function teardown() {
        _activationEpoch++;
        if (_storageReady) InventoryStorageWorkbench.deactivate();
        if (_build) _build.destroy();
        if (_tuningHeader) _tuningHeader.destroy();
        if (_density) _density.destroy();
        if (_scale) _scale.detach();
        if (_shell) _shell.destroy();

        _storageReady = false;
        _build = null;
        _tuningHeader = null;
        _density = null;
        _densityToggle = null;
        _scale = null;
        _shell = null;
        _root = null;
        _body = null;
        _buildHost = null;
        _closing = false;
        _statsMode = false;
        _buttons = {};
        _buildInteractionLocked = false;
        _buildLockReason = '';
        _profile = null;
        _view = 'storage';
        _panelInstanceId = '';
        _returnTarget = null;
        _closeSent = false;
        clear(_scaleEl);
    }

    function activate(el, initData) {
        _activationEpoch++;
        initData = initData || {};
        _profile = InventoryWorkbenchConfig.resolveProfile(initData);
        _view = InventoryWorkbenchConfig.resolveView(initData);
        _panelInstanceId = String(initData.panelInstanceId || '');
        if (!_profile || !_view
                || !InventoryWorkbenchConfig.isViewAllowed(_profile, _view)
                || !validInstance(_panelInstanceId)) {
            toast('工作台参数无效，已取消打开。');
            return false;
        }

        _returnTarget = InventoryWorkbenchConfig.resolveReturnTarget(initData);
        _closeSent = false;
        _shell = new Workbench.DualPaneShell({
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
            panelId:'workbench'
        });
        _root.setAttribute('data-layout-mode', _density.mode);
        makeHeader();
        _scale = typeof PanelScale !== 'undefined'
            ? PanelScale.attach(_scaleEl, 1024, 576)
            : null;
        var mounted = _view === 'build'
            ? showBuild()
            : ensureStorage(_view);
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
            state.closing = _closing;
            state.buildInteractionLocked = _buildInteractionLocked;
            state.buildLockReason = _buildLockReason;
            state.storage = storage;
            state.build = _build ? _build.debugState() : null;
            state.returnTarget = _returnTarget
                ? {
                    panel:_returnTarget.panel,
                    initData:_returnTarget.initData
                }
                : null;
            return state;
        }
    };
})();
