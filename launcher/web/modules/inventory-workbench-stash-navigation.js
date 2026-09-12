/** Stash source orchestration for the workbench facade: stash feature closure,
 * authority lifecycle, view-hop and close gating. View transitions still go
 * through InventoryWorkbenchNavigation — this is a narrow source helper, not
 * a second navigation system. */
(function(root, factory) {
    'use strict';
    var api = factory(root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchStashNavigation = api;
})(typeof window !== 'undefined' ? window : globalThis, function(root) {
    'use strict';

    // Headless stash closure: session + item-use channel + authority only. It
    // must never pull CharacterBuildView, the doll renderer or the manifest —
    // a storage-launched panel opens stash without any character asset.
    var STASH_DEPS = [
        'modules/character-build/character-build-mutation.js',
        'modules/character-build/character-build-drug-layout.js',
        'modules/character-build/character-build-session-contract.js',
        'modules/character-build-session.js',
        'modules/character-build/character-build-transport.js',
        'modules/character-build/character-build-cooldown-channel.js',
        'modules/character-build/character-build-stash-transport.js',
        'modules/character-build/character-build-item-use.js',
        'modules/character-build/character-build-stash-authority.js'
    ];

    function isFeatureReady() {
        return !!(root.CharacterBuildSession
            && root.CharacterBuildSession.CharacterBuildSession
            && root.CharacterBuildTransport
            && typeof root.CharacterBuildTransport.createRequestMux === 'function'
            && root.CharacterBuildItemUse
            && typeof root.CharacterBuildItemUse.Controller === 'function'
            && root.CharacterBuildStashAuthority
            && typeof root.CharacterBuildStashAuthority.create === 'function');
    }

    function featureDescriptor() {
        return {view:'stash', title:'暂存物资', deps:STASH_DEPS,
            ready:isFeatureReady, label:'stash feature'};
    }

    function loadFeature() {
        var loader = root.InventoryWorkbenchFeatureLoader;
        if (!loader || typeof loader.loadFeature !== 'function') {
            return Promise.reject(
                new Error('stash feature loader is unavailable'));
        }
        return loader.loadFeature(featureDescriptor());
    }

    function navOf(ref) { return typeof ref === 'function' ? ref() : ref; }

    function decorateControllerPorts(ports, navRef) {
        ports.storageSource = 'container';
        ports.stashItemUse = null;
        ports.requestStorageSource = function(sourceId, opener) {
            var nav = navOf(navRef);
            return nav ? nav.request(sourceId, {opener:opener}) : false;
        };
        return ports;
    }

    function decorateBuildPorts(ports, navRef) {
        ports.openStorageSource = function(sourceId) {
            var nav = navOf(navRef);
            return nav ? nav.request(sourceId, {}) : false;
        };
        return ports;
    }

    function create(options) {
        options = options || {};
        var _authority = null, _itemUse = null, _origin = '';
        var _pendingEntry = null, _switching = false, _destroyed = false;
        var _closeSent = false, _readyTimer = null;

        function context() {
            return typeof options.context === 'function' ? options.context() : {};
        }
        function storage() {
            return options.storage || root.InventoryStorageWorkbench;
        }
        function toast(message) {
            if (typeof options.toast === 'function') options.toast(message);
            else if (root.Toast) root.Toast.add(message);
        }
        function isActive() {
            if (typeof options.active === 'function') return options.active();
            return !!(root.Panels && root.Panels.getActive
                && root.Panels.getActive() === 'workbench');
        }
        function live(epoch) {
            var c = context();
            return !_destroyed && epoch === c.epoch && isActive() && !c.closing;
        }
        function restoreFocus(opener) {
            if (opener && opener.isConnected !== false
                    && typeof opener.focus === 'function') {
                try { opener.focus(); } catch (_) {}
            }
        }
        function ensureAuthority() {
            if (_authority) return _authority;
            var factory = options.authorityModule || root.CharacterBuildStashAuthority;
            if (!factory || typeof factory.create !== 'function') return null;
            var c = context();
            _authority = factory.create({
                send:options.send || function(message) {
                    return root.Bridge.send(message);
                },
                router:options.router
                    || root.PanelRuntime && root.PanelRuntime.sharedResponseRouter,
                timeoutMs:c.runtimeConfig && c.runtimeConfig.requestTimeoutMs,
                sessionNonce:c.runtimeConfig && c.runtimeConfig.sessionNonce,
                getBuild:function() { return context().build || null; },
                panelInstanceId:function() {
                    return context().panelInstanceId || '';
                },
                onStatus:function(state, reason) {
                    var shell = context().shell;
                    if (shell) shell.setStatus(
                        reason === 'idle' ? '已同步' : '正在同步暂存',
                        reason === 'idle' ? 'ready' : 'busy');
                },
                toast:toast
            });
            return _authority;
        }
        function fail(message, opener) {
            if (_readyTimer) clearTimeout(_readyTimer); _readyTimer = null;
            _switching = false;
            _pendingEntry = null;
            _itemUse = null;
            _origin = '';
            if (_authority) _authority.release();
            if (message) toast(message);
            restoreFocus(opener);
        }
        function switchToStash(opener, epoch, attempts) {
            _pendingEntry = null;
            var st = storage();
            if (st && typeof st.getSource === 'function'
                    && st.getSource() === 'stash') {
                _switching = false;
                return;
            }
            if (!st || typeof st.switchSource !== 'function') {
                fail('暂存来源尚未就绪。', opener);
                return;
            }
            var state = st.debugState && st.debugState().coordinator;
            if (state && !state.ready && (!state.busyOwner || state.busyOwner === 'bootstrap') && !state.refreshRequired) {
                if ((attempts || 0) >= 40) { fail('背包同步尚未完成，请重试打开暂存。', opener); return; }
                _readyTimer = setTimeout(function() {
                    _readyTimer = null;
                    if (live(epoch)) switchToStash(opener, epoch, (attempts || 0) + 1);
                }, 250);
                return;
            }
            var accepted = false;
            try {
                accepted = st.switchSource('stash', {itemUse:_itemUse},
                    function(success) {
                        _switching = false;
                        if (!live(epoch)) return;
                        if (!success) fail('无法打开暂存来源，请重试。', opener);
                    });
            } catch (error) {
                accepted = false;
            }
            if (!accepted) fail('无法打开暂存来源，请重试。', opener);
        }
        function enter(opts) {
            opts = opts || {};
            var c = context(), st = storage();
            if (c.view === 'storage' && c.storageReady && st) {
                if (typeof st.getSource === 'function'
                        && st.getSource() === 'stash') return true;
                var header = typeof st.getHeaderState === 'function'
                    ? st.getHeaderState() : null;
                if (header && header.disabled) {
                    toast(header.reason || '库存操作尚未完成，请稍候。');
                    return false;
                }
            }
            var epoch = c.epoch, opener = opts.opener || null;
            _switching = true;
            _origin = c.view === 'storage' ? 'storage' : c.view;
            Promise.resolve(loadFeature()).then(function() {
                if (!live(epoch)) return;
                var authority = ensureAuthority();
                if (!authority) {
                    fail('暂存物资资源不可用。', opener);
                    return;
                }
                authority.acquire(function(handle) {
                    if (!live(epoch)) return;
                    if (!handle || !handle.itemUse) {
                        fail('暂存物资暂不可用，请稍候重试。', opener);
                        return;
                    }
                    _itemUse = handle.itemUse;
                    if (context().view !== 'storage') {
                        _pendingEntry = {opener:opener};
                        if (!options.requestView('storage', {
                            origin:'storage-source', opener:opener
                        })) {
                            fail('无法打开收纳视图。', opener);
                        }
                        return;
                    }
                    switchToStash(opener, epoch);
                });
            }).catch(function() {
                if (live(epoch)) fail('暂存物资资源加载失败，请重试。', opener);
            });
            return true;
        }
        function leave() {
            var c = context(), st = storage();
            if (!c.storageReady || !st || typeof st.getSource !== 'function'
                    || st.getSource() !== 'stash' || c.view !== 'storage') {
                if (_authority) _authority.release();
                _itemUse = null;
                _origin = '';
                return true;
            }
            var header = typeof st.getHeaderState === 'function'
                ? st.getHeaderState() : null;
            if (header && header.disabled) {
                toast(header.reason || '库存操作尚未完成，请稍候。');
                return false;
            }
            _switching = true;
            var epoch = c.epoch, accepted = false;
            try {
                accepted = st.switchSource('container', {}, function(success) {
                    _switching = false;
                    if (!live(epoch)) return;
                    if (success) {
                        _origin = '';
                        if (_authority) _authority.release();
                        _itemUse = null;
                    } else {
                        toast('未能返回本来源，请重试。');
                    }
                });
            } catch (error) {
                accepted = false;
            }
            if (!accepted) _switching = false;
            return !!accepted;
        }
        function request(sourceId, opts) {
            if (sourceId !== 'container' && sourceId !== 'stash') return false;
            var c = context();
            if (c.closing || c.featureLoading || _switching) return false;
            if (c.navigation
                    && typeof c.navigation.rejectIfPending === 'function'
                    && c.navigation.rejectIfPending()) return false;
            if (sourceId === 'stash' && c.buildLockReason) {
                toast(c.buildLockReason);
                return false;
            }
            return sourceId === 'stash' ? enter(opts) : leave();
        }
        function prepareView(next, proceed) {
            if (next === 'storage') return proceed();
            var c = context(), st = storage(), epoch = c.epoch;
            function finish() {
                _origin = ''; _itemUse = null;
                if (!_authority) return proceed();
                _authority.release();
                // A headless session must finish before Build opens its own session.
                // A borrowed Build session stays live and resumes the same generation.
                if (!_authority.debugState().session) return proceed();
                _switching = true;
                var started = _authority.finalize(function(accepted) {
                    _switching = false;
                    if (accepted && live(epoch)) proceed();
                    else if (live(epoch)) toast('暂存会话尚未完成结算，请重试切换。');
                });
                if (!started) _switching = false;
                return !!started;
            }
            if (!c.storageReady || !st || st.getSource() !== 'stash') return finish();
            _switching = true;
            var started = st.switchSource('container', {}, function(success) {
                _switching = false;
                if (success && live(epoch)) finish();
            });
            if (!started) _switching = false;
            return !!started;
        }
        function consumeEscape() {
            var c = context(), st = storage();
            if (c.view === 'storage' && c.storageReady && st
                    && typeof st.getSource === 'function'
                    && st.getSource() === 'stash' && _origin === 'storage') {
                return request('container', {
                    origin:'escape',
                    opener:root.document ? root.document.activeElement : null
                });
            }
            return false;
        }
        function onView(next) {
            if (!_pendingEntry) return;
            var entry = _pendingEntry;
            if (next === 'storage' && _itemUse) {
                _pendingEntry = null;
                switchToStash(entry.opener, context().epoch);
                return;
            }
            if (next !== 'storage') {
                _pendingEntry = null;
                _switching = false;
                _itemUse = null;
                _origin = '';
                if (_authority) _authority.release();
                toast('暂存打开已取消。');
            }
        }
        function finalizeClose(reason) {
            var build = context().build;
            if (_authority && !_authority.canClose()) {
                toast('暂存领取仍在确认，请稍候关闭。');
                return false;
            }
            var owner = build || _authority;
            if (!owner || build && build.canClose()) return finishClose(reason);
            options.setClosing(true);
            var epoch = context().epoch;
            var callId = owner.finalize(function(accepted) {
                if (_destroyed || context().epoch !== epoch) return;
                options.setClosing(false);
                if (accepted) finishClose(reason);
            });
            if (!callId) {
                options.setClosing(false);
                toast('工作台仍在同步，请稍候关闭。');
            }
            return !!callId;
        }
        function finishClose(reason) {
            if (typeof options.finishClose === 'function') return options.finishClose(reason);
            if (_closeSent) return false;
            _closeSent = true;
            var message = root.InventoryWorkbenchConfig.createCloseMessage(
                context().panelInstanceId, reason);
            if (root.Bridge.send(message) === false) {
                _closeSent = false;
                toast('启动器连接不可用，工作台保持打开。');
                return false;
            }
            root.Panels.close();
            return true;
        }
        function destroy() {
            _destroyed = true;
            if (_readyTimer) clearTimeout(_readyTimer); _readyTimer = null;
            if (_authority) _authority.destroy();
            _authority = null;
            _itemUse = null;
            _origin = '';
            _pendingEntry = null;
            _switching = false;
        }
        return {
            request:request,
            prepareView:prepareView,
            consumeEscape:consumeEscape,
            onView:onView,
            finalizeClose:finalizeClose,
            destroy:destroy,
            itemUse:function() { return _itemUse; },
            source:function() { return _itemUse ? 'stash' : 'container'; },
            switching:function() { return _switching; },
            debugState:function() {
                return {origin:_origin || null, switching:_switching,
                    itemUse:!!_itemUse,
                    authority:_authority ? _authority.debugState() : null};
            }
        };
    }

    return {
        STASH_DEPS:STASH_DEPS,
        isFeatureReady:isFeatureReady,
        featureDescriptor:featureDescriptor,
        loadFeature:loadFeature,
        decorateControllerPorts:decorateControllerPorts,
        decorateBuildPorts:decorateBuildPorts,
        create:create
    };
});
