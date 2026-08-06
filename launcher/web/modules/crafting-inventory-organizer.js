/** Crafting-owned storage child view. It never registers or opens a Host panel. */
var CraftingInventoryOrganizer = (function() {
    'use strict';

    var _host = null;
    var _shell = null;
    var _root = null;
    var _density = null;
    var _help = null;
    var _owner = null;
    var _storageReady = false;
    var _closeSent = false;

    function toast(message) {
        if (typeof Toast !== 'undefined') Toast.add(message);
    }

    function isActive() {
        return !!(Panels.getActive && Panels.getActive() === 'crafting');
    }

    function button(label, className, handler) {
        var node = document.createElement('button');
        node.type = 'button';
        node.className = className;
        node.textContent = label;
        node.addEventListener('click', handler);
        return node;
    }

    function refreshHeader() {
        if (!_shell || !_storageReady) return;
        var state = InventoryStorageWorkbench.getHeaderState();
        if (_help) _help.update({
            disabled:state.disabled,
            ariaLabel:'查看战备箱整理帮助',
            onOpen:InventoryStorageWorkbench.openHelp
        });
    }

    function controllerPorts(profile) {
        return {
            shell:_shell,
            root:_root,
            profileConfig:profile,
            ownerPanel:_owner.panel,
            panelInstanceId:_owner.panelInstanceId,
            densityController:_density,
            addHeaderAction:function(node) { _shell.addHeaderAction(node); },
            refreshHeader:refreshHeader,
            onViewChanged:function() {
                _shell.setProfile('transfer-pair');
                _root.setAttribute('data-workbench-view', 'storage');
            },
            isPanelActive:isActive
        };
    }

    function mount(host, ownerContext) {
        if (_shell || !host || !ownerContext
                || ownerContext.kind !== 'crafting-organizer'
                || ownerContext.panel !== 'crafting'
                || !/^[A-Za-z0-9._~-]{1,128}$/.test(
                    String(ownerContext.panelInstanceId || ''))
                || typeof ownerContext.onReturn !== 'function'
                || !isActive()) return false;
        _host = host;
        _owner = {
            kind:'crafting-organizer',
            panel:'crafting',
            panelInstanceId:String(ownerContext.panelInstanceId),
            onReturn:ownerContext.onReturn
        };
        _shell = new Workbench.DualPaneShell({
            profile:'transfer-pair',
            title:'战备箱',
            subtitle:'合成工作台内整理',
            status:'同步中',
            leftLabel:'背包',
            rightLabel:'战备箱'
        });
        _root = _shell.getRoot();
        _root.classList.add('kshop-workbench', 'inventory-workbench-panel');
        _root.setAttribute('data-workbench-skin', 'inventory');
        _root.setAttribute('data-workbench-owner-context', 'crafting-organizer');
        _host.appendChild(_root);
        _density = new Workbench.GridDensityController({
            panelId:'workbench',
            defaultMode:'compact'
        });
        _root.setAttribute('data-layout-mode', _density.mode);
        _shell.addHeaderAction(_density.createToggle(function(mode) {
            _root.setAttribute('data-layout-mode', mode);
        }));
        var returnButton = button('返回合成',
            'workbench-mode-btn inventory-return-crafting-btn',
            requestReturn);
        returnButton.setAttribute('aria-label', '返回合成并重新核算原配方与份数');
        _shell.addHeaderAction(returnButton);
        _help = new WorkbenchComponents.HelpAction({shell:_shell});
        var closeButton = button('×', 'workbench-close-btn', function() {
            requestClose('header');
        });
        closeButton.setAttribute('aria-label', '关闭合成工作台');
        _shell.addHeaderAction(closeButton);

        var profile = InventoryWorkbenchConfig.resolveProfile({profile:'battlebox'});
        try {
            _storageReady = InventoryStorageWorkbench.activate(
                controllerPorts(profile), 'storage');
        } catch (error) {
            if (typeof console !== 'undefined' && console.error) {
                console.error('[CraftingInventoryOrganizer] mount threw:', error);
            }
            _storageReady = false;
        }
        refreshHeader();
        if (_storageReady) return true;
        teardown();
        return false;
    }

    function completeClose(reason) {
        if (_closeSent) return false;
        _closeSent = true;
        if (!_owner || !_owner.panelInstanceId) return false;
        var message = {type:'panel', cmd:'close', panel:'crafting',
            panelInstanceId:_owner.panelInstanceId};
        var accepted = false;
        try { accepted = Bridge.send(message) !== false; }
        catch (_) { accepted = false; }
        if (!accepted) {
            _closeSent = false;
            toast('启动器连接不可用，工作台保持打开。');
            return false;
        }
        Panels.close();
        return true;
    }

    function requestClose(reason) {
        if (!_shell) return false;
        if (_shell.hasModal()) return _shell.closeModal(reason || 'close');
        return InventoryStorageWorkbench.prepareClose(reason, function(ready) {
            if (ready) completeClose(reason);
        });
    }

    function requestReturn() {
        if (!_owner || !_storageReady) return false;
        return InventoryStorageWorkbench.prepareClose('return', function(ready) {
            if (!ready) return;
            var owner = _owner;
            teardown();
            owner.onReturn();
        });
    }

    function teardown() {
        if (_storageReady) InventoryStorageWorkbench.deactivate();
        if (_help) _help.destroy();
        if (_density) _density.destroy();
        if (_shell) _shell.destroy();
        if (_root && _root.parentNode) _root.parentNode.removeChild(_root);
        _host = null;
        _shell = null;
        _root = null;
        _density = null;
        _help = null;
        _owner = null;
        _storageReady = false;
        _closeSent = false;
    }

    return {
        mount:mount,
        requestClose:requestClose,
        teardown:teardown,
        isMounted:function() { return !!_shell; },
        debugState:function() {
            return {
                ownerContext:_owner ? _owner.kind : '',
                hostOwner:_owner ? _owner.panel : '',
                panelInstanceId:_owner ? _owner.panelInstanceId : '',
                storage:_storageReady ? InventoryStorageWorkbench.debugState() : null
            };
        }
    };
})();
