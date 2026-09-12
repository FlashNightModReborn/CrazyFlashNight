/** 暂存领取的会话归属：借用现役构筑 exact 会话，或建立 headless 会话（无 view/renderer/manifest）。 */
(function(root, factory) {
    'use strict';
    var session = typeof module !== 'undefined' && module.exports
        ? require('../character-build-session.js')
        : root && root.CharacterBuildSession;
    var itemUse = typeof module !== 'undefined' && module.exports
        ? require('./character-build-item-use.js')
        : root && root.CharacterBuildItemUse;
    var transport = typeof module !== 'undefined' && module.exports
        ? require('./character-build-transport.js')
        : root && root.CharacterBuildTransport;
    var api = factory(session, itemUse, transport);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildStashAuthority = api;
        root.CharacterBuildStashAuthority = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(SessionModule, ItemUseModule, Transport) {
    'use strict';
    if (!SessionModule || !SessionModule.CharacterBuildSession) {
        throw new Error('CharacterBuildStashAuthority requires CharacterBuildSession');
    }
    if (!ItemUseModule || typeof ItemUseModule.Controller !== 'function') {
        throw new Error('CharacterBuildStashAuthority requires CharacterBuildItemUse');
    }
    if (!Transport || typeof Transport.createRequestMux !== 'function') {
        throw new Error('CharacterBuildStashAuthority requires CharacterBuildTransport');
    }
    var BUSY_ITEM_USE_STATES = ['write_pending', 'query_pending', 'needs_reconcile'];

    function create(options) {
        options = options || {};
        var send = options.send, router = options.router;
        var _mode = '';
        var _handle = null;
        var _build = null;
        var _session = null;
        var _itemUse = null;
        var _waiters = [];
        var _destroyed = false;

        function panelInstanceId() {
            var value = typeof options.panelInstanceId === 'function'
                ? options.panelInstanceId() : options.panelInstanceId;
            return typeof value === 'string' && value ? value : '';
        }
        function status(state, reason) {
            if (typeof options.onStatus === 'function') {
                options.onStatus(state, reason);
            }
        }
        function notice(message) {
            if (typeof options.toast === 'function') options.toast(message);
        }
        function ensureHeadless() {
            if (_session) return;
            var mux = Transport.createRequestMux({
                send:send, router:router,
                timeoutMs:options.timeoutMs,
                sessionNonce:options.sessionNonce,
                setTimer:options.setTimer,
                clearTimer:options.clearTimer
            });
            _session = new SessionModule.CharacterBuildSession({
                mux:mux,
                onState:function(state, reason) { status('session_' + reason, state); },
                onError:function(response, command) {
                    notice(command === 'finalize'
                        ? '暂存会话尚未完成结算，请重试关闭。'
                        : '暂存会话同步失败，请重试。');
                }
            });
            _itemUse = new ItemUseModule.Controller({
                send:send, router:router,
                timeoutMs:options.timeoutMs,
                sessionNonce:options.sessionNonce,
                operationNonce:options.operationNonce || options.sessionNonce,
                setTimer:options.setTimer,
                clearTimer:options.clearTimer,
                onState:function(state, reason) { status('item_use_' + reason, state); },
                onSettled:function() {},
                onInbox:function() {},
                onCooldown:function() {}
            });
        }
        function itemUseController() {
            return _handle && _handle.itemUse ? _handle.itemUse : _itemUse;
        }
        function itemUseBusy() {
            var use = itemUseController();
            var state = use && typeof use.debugState === 'function'
                ? use.debugState().state : 'closed';
            return BUSY_ITEM_USE_STATES.indexOf(state) >= 0;
        }
        function flushWaiters(handle) {
            var waiters = _waiters;
            _waiters = [];
            for (var index = 0; index < waiters.length; index++) {
                try { waiters[index](handle); } catch (_) {}
            }
        }
        function headlessHandle() {
            var generation = _session.getSessionGeneration();
            var pid = panelInstanceId();
            if (!generation || !pid || !_itemUse.bind(pid, generation)) return null;
            _itemUse.refreshInbox();
            _mode = 'headless';
            _handle = {itemUse:_itemUse, generation:generation,
                panelInstanceId:pid, headless:true};
            return _handle;
        }
        function borrowHandle(owner, authority) {
            if (typeof owner.holdItemUse === 'function') owner.holdItemUse();
            _mode = 'borrowed';
            _build = owner;
            _handle = {itemUse:authority.itemUse,
                generation:authority.generation,
                panelInstanceId:authority.panelInstanceId || panelInstanceId(),
                headless:false};
            return _handle;
        }
        function acquireHeadless(callback) {
            ensureHeadless();
            var state = _session.getState();
            if (state === 'idle' || state === 'flush_failed') {
                var handle = headlessHandle();
                callback(handle);
                return handle;
            }
            if (state === 'closed') {
                _waiters.push(callback);
                var callId = _session.open(panelInstanceId(), function(_, accepted) {
                    if (_destroyed) return;
                    flushWaiters(accepted === true ? headlessHandle() : null);
                });
                if (!callId) flushWaiters(null);
                return callId || true;
            }
            if (state === 'opening' || state === 'opening_reconcile') {
                _waiters.push(callback);
                return true;
            }
            callback(null);
            return null;
        }
        function acquire(callback) {
            callback = typeof callback === 'function' ? callback : function() {};
            if (_destroyed) { callback(null); return null; }
            if (_handle) { callback(_handle); return _handle; }
            if (_waiters.length) { _waiters.push(callback); return true; }
            var owner = typeof options.getBuild === 'function'
                ? options.getBuild() : null;
            if (owner && typeof owner.itemUseAuthority === 'function') {
                var authority = owner.itemUseAuthority();
                if (authority && authority.itemUse && authority.generation) {
                    var handle = borrowHandle(owner, authority);
                    callback(handle);
                    return handle;
                }
                if (typeof owner.whenItemUseReady === 'function') {
                    _waiters.push(callback);
                    owner.whenItemUseReady(function(result) {
                        if (_destroyed) return;
                        flushWaiters(result && result.itemUse && result.generation
                            ? borrowHandle(owner, result) : null);
                    });
                    return true;
                }
                callback(null);
                return null;
            }
            return acquireHeadless(callback);
        }
        function release() {
            if (_mode === 'borrowed' && _build
                    && typeof _build.releaseItemUse === 'function') {
                _build.releaseItemUse();
            }
            _mode = '';
            _build = null;
            _handle = null;
            return true;
        }
        // Close responsibility follows the still-live headless session, not the
        // released view handle: a released stash source must still finalize.
        function canClose() {
            if (_destroyed) return true;
            if (itemUseBusy()) return false;
            if (!_session) return true;
            var state = _session.getState();
            return state === 'idle' || state === 'flush_failed'
                || state === 'finalized' || state === 'closed';
        }
        function finalize(callback) {
            callback = typeof callback === 'function' ? callback : function() {};
            if (_destroyed) {
                callback(true);
                return true;
            }
            if (!canClose()) {
                callback(false);
                return null;
            }
            if (!_session) {
                callback(true);
                return true;
            }
            var state = _session.getState();
            if (state === 'finalized' || state === 'closed') {
                callback(true);
                return true;
            }
            var callId = _session.finalize(function(_, accepted) {
                callback(accepted === true);
            });
            if (!callId) {
                callback(false);
                return null;
            }
            return callId;
        }
        function destroy() {
            if (_destroyed) return false;
            _destroyed = true;
            release();
            flushWaiters(null);
            if (_itemUse) _itemUse.destroy();
            if (_session) _session.destroy();
            _itemUse = null;
            _session = null;
            return true;
        }
        return {
            acquire:acquire,
            release:release,
            canClose:canClose,
            finalize:finalize,
            destroy:destroy,
            debugState:function() {
                return {
                    mode:_mode || null,
                    generation:_handle ? _handle.generation : null,
                    waiters:_waiters.length,
                    session:_session ? _session.debugState() : null,
                    itemUse:itemUseController()
                        ? itemUseController().debugState() : null
                };
            }
        };
    }

    // Build-side ports the borrowed path depends on: installed onto
    // CharacterBuildController.prototype by character-build.js so this narrow
    // module owns both ends of the hold/wait contract.
    function installBuildPorts(prototype) {
        if (!prototype) return false;
        prototype._flushItemUseReadyWaiters = function(result) {
            var waiters = this._itemUseReadyWaiters;
            if (!waiters || !waiters.length) return;
            this._itemUseReadyWaiters = [];
            for (var index = 0; index < waiters.length; index++) {
                try { waiters[index](result); } catch (_) {}
            }
        };
        prototype.itemUseAuthority = function() {
            var generation = this._session.getSessionGeneration();
            var state = this._session.getState();
            if (!this._panelInstanceId || !generation
                    || (state !== 'idle' && state !== 'flush_failed')) {
                return null;
            }
            if (this._itemUse.debugState().state === 'closed') {
                if (!this._itemUse.bind(this._panelInstanceId, generation)) {
                    return null;
                }
                this._itemUse.refreshInbox();
            }
            return {
                itemUse:this._itemUse,
                panelInstanceId:this._panelInstanceId,
                generation:generation
            };
        };
        prototype.whenItemUseReady = function(callback) {
            if (typeof callback !== 'function') return false;
            var authority = this.itemUseAuthority();
            if (authority) {
                callback(authority);
                return true;
            }
            var state = this._session.getState();
            if (state === 'closed' || state === 'finalized') {
                callback(null);
                return true;
            }
            this._itemUseReadyWaiters.push(callback);
            return true;
        };
        prototype.holdItemUse = function() {
            this._itemUseHolds++;
            return this._itemUseHolds;
        };
        prototype.releaseItemUse = function() {
            if (this._itemUseHolds > 0) this._itemUseHolds--;
            return this._itemUseHolds;
        };
        return true;
    }

    return {create:create, installBuildPorts:installBuildPorts};
});
