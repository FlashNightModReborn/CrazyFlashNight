/**
 * KShop runtime reliability primitives.
 *
 * KShopRequestMux owns the WebView-session callId namespace and validates response channels.
 * KShopWriteCoordinator serializes saveCart/checkoutCommit/legacy claim, coalesces cart saves
 * and forces bulkQuery reconciliation after any ambiguous write result. checkoutPreview stays
 * read-only outside the write owner; checkoutCommit consumes an AS2-issued opaque plan token.
 */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.KShopRequestMux = api.KShopRequestMux;
        root.KShopWriteCoordinator = api.KShopWriteCoordinator;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    function KShopRequestMux(options) {
        options = options || {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            callPrefix:'wb',
            router:options.router || PanelRuntime.sharedResponseRouter,
            onProtocolError:options.onProtocolError,
            createMessage:function(context) {
                var message = PanelRuntime.copyOwn(context.payload);
                message.type = 'panel';
                message.cmd = context.entry.cmd;
                message.callId = context.entry.callId;
                if (context.entry.metadata.channel === 'inventory') message.domain = 'inventory';
                else if (Object.prototype.hasOwnProperty.call(message, 'domain')) delete message.domain;
                return message;
            },
            validateResponse:function(data, entry) {
                if (!data || data.type !== 'panel_resp' || data.callId !== entry.callId) return false;
                if (entry.metadata.channel === 'inventory') {
                    return data.domain === 'inventory' && data.cmd === entry.cmd;
                }
                return !data.domain && (!data.panel || data.panel === 'kshop')
                    && (!data.cmd || data.cmd === entry.cmd);
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', callId:context.entry.callId, cmd:context.entry.cmd,
                    success:false, error:context.error, clientSynthetic:true};
            }
        });
    }

    KShopRequestMux.prototype.openSession = function() {
        this._mux.openSession({});
        return this._mux.debugState().generation;
    };

    KShopRequestMux.prototype.closeSession = function() {
        this._mux.closeSession();
    };

    KShopRequestMux.prototype.request = function(channel, cmd, payload, callback) {
        channel = channel || 'shop';
        if (channel !== 'shop' && channel !== 'inventory') throw new Error('unsupported mux channel: ' + channel);
        if (!cmd) throw new Error('mux cmd is required');
        return this._mux.request(cmd, payload, {
            metadata:{channel:channel},
            sendError:'disconnected'
        }, callback);
    };

    KShopRequestMux.prototype.handleResponse = function(data) {
        return this._mux.handleResponse(data);
    };

    KShopRequestMux.prototype.cancel = function(callId) {
        return this._mux.cancel(callId);
    };

    KShopRequestMux.prototype.pendingCount = function() {
        return this._mux.pendingCount();
    };

    KShopRequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {
            sessionNonce: state.sessionNonce,
            openGeneration: state.generation,
            sequence: state.sequence,
            active: state.active,
            pendingCount: state.pendingCount
        };
    };

    KShopRequestMux.prototype.destroy = function() { this._mux.destroy(); };

    function cloneCart(cart) {
        var out = [];
        cart = cart || [];
        for (var i = 0; i < cart.length; i++) {
            out.push({ idx: Number(cart[i].idx), qty: Number(cart[i].qty) });
        }
        return out;
    }

    function cartEquals(a, b) {
        a = cloneCart(a);
        b = cloneCart(b);
        if (a.length !== b.length) return false;
        for (var i = 0; i < a.length; i++) {
            if (a[i].idx !== b[i].idx || a[i].qty !== b[i].qty) return false;
        }
        return true;
    }

    function isFiniteNumber(value) {
        return typeof value === 'number' && isFinite(value);
    }

    function isValidBulkSnapshot(response) {
        return !!response
            && response.success === true
            && Array.isArray(response.catalog)
            && Array.isArray(response.cart)
            && Array.isArray(response.purchased)
            && typeof response.purchasedToken === 'string' && response.purchasedToken.length > 0
            && isFiniteNumber(response.kpoints)
            && isFiniteNumber(response.playerLevel)
            && isFiniteNumber(response.reverseLevel);
    }

    function KShopWriteCoordinator(options) {
        options = options || {};
        this._request = options.request;
        this._getCart = options.getCart || function() { return []; };
        this._getPurchasedToken = options.getPurchasedToken || function() { return ''; };
        this._applyBulkSnapshot = options.applyBulkSnapshot || function() {};
        this._onStateChange = options.onStateChange || function() {};
        this._setTimer = options.setTimer || function(callback, delay) { return setTimeout(callback, delay); };
        this._clearTimer = options.clearTimer || function(timer) { clearTimeout(timer); };
        this._debounceMs = Math.max(0, Number(options.debounceMs) || 700);
        this._timer = null;
        this._revision = 0;
        this._savedRevision = 0;
        this._saveInFlight = null;
        this._exclusive = null;
        this._reconciling = null;
        this._reconcileBlocked = null;
        this._closing = false;
        this._closeCallback = null;
        this._opened = false;
    }

    KShopWriteCoordinator.prototype.open = function() {
        this.forceClose();
        this._opened = true;
        this._revision = 0;
        this._savedRevision = 0;
        this._emitState();
    };

    KShopWriteCoordinator.prototype.forceClose = function() {
        if (this._timer) this._clearTimer(this._timer);
        this._timer = null;
        this._saveInFlight = null;
        this._exclusive = null;
        this._reconciling = null;
        this._reconcileBlocked = null;
        this._closing = false;
        this._closeCallback = null;
        this._opened = false;
        this._emitState();
    };

    KShopWriteCoordinator.prototype.acceptAuthoritativeCart = function() {
        this._revision += 1;
        this._savedRevision = this._revision;
        this._emitState();
    };

    KShopWriteCoordinator.prototype.canEditCart = function() {
        return this._opened && !this._closing && !this._exclusive && !this._reconciling && !this._reconcileBlocked;
    };

    KShopWriteCoordinator.prototype.markCartChanged = function() {
        if (!this.canEditCart()) return false;
        this._revision += 1;
        this._scheduleAutoSave();
        this._emitState();
        return true;
    };

    KShopWriteCoordinator.prototype.checkout = function(expectedCheckoutToken, callback) {
        if (!this._beginExclusive('checkoutCommit')) return false;
        var self = this;
        this._ensureSaved(function(saveResult) {
            if (!saveResult.success) {
                self._finishExclusive(saveResult, callback);
                return;
            }
            self._request('checkoutCommit', {
                v: 1,
                expectedCheckoutToken: String(expectedCheckoutToken || '')
            }, function(response) {
                if (self._isDefinitive('checkoutCommit', response)) {
                    self._finishExclusive(response, callback);
                } else {
                    self._startReconcile('checkoutCommit', response, function(result) {
                        self._finishExclusive(result, callback);
                    });
                }
            });
        });
        return true;
    };

    KShopWriteCoordinator.prototype.claim = function(purchasedIdx, callback) {
        if (!this._beginExclusive('claim')) return false;
        var self = this;
        this._ensureSaved(function(saveResult) {
            if (!saveResult.success) {
                self._finishExclusive(saveResult, callback);
                return;
            }
            self._request('claim', {
                purchasedIdx: purchasedIdx,
                expectedPurchasedToken: String(self._getPurchasedToken() || '')
            }, function(response) {
                if (response && response.success === false
                        && (response.error === 'item_not_found' || response.error === 'stale_state')) {
                    self._startReconcile('claim', response, function(result) {
                        self._finishExclusive(result, callback);
                    });
                } else if (self._isDefinitive('claim', response)) {
                    self._finishExclusive(response, callback);
                } else {
                    self._startReconcile('claim', response, function(result) {
                        self._finishExclusive(result, callback);
                    });
                }
            });
        });
        return true;
    };

    KShopWriteCoordinator.prototype.close = function(callback) {
        if (!this._opened || this._closing) return false;
        this._closing = true;
        this._closeCallback = typeof callback === 'function' ? callback : function() {};
        if (this._timer) this._clearTimer(this._timer);
        this._timer = null;
        this._emitState();
        this._continueClose();
        return true;
    };

    KShopWriteCoordinator.prototype.retryReconcile = function() {
        var blocked = this._reconcileBlocked;
        if (!blocked) return false;
        this._reconcileBlocked = null;
        this._startReconcile(blocked.origin, blocked.originalResponse, blocked.continuation);
        return true;
    };

    KShopWriteCoordinator.prototype.debugState = function() {
        return this._stateSnapshot();
    };

    KShopWriteCoordinator.prototype._scheduleAutoSave = function() {
        var self = this;
        if (this._timer) this._clearTimer(this._timer);
        this._timer = this._setTimer(function() {
            self._timer = null;
            if (!self._opened || self._closing || self._exclusive || self._reconciling || self._reconcileBlocked) return;
            self._sendSave('autosave', function(result) {
                if (!result.success && result.error === 'busy') self._scheduleAutoSave();
            });
        }, this._debounceMs);
    };

    KShopWriteCoordinator.prototype._beginExclusive = function(kind) {
        if (!this._opened || this._closing || this._exclusive || this._reconciling || this._reconcileBlocked) return false;
        this._exclusive = kind;
        if (this._timer) this._clearTimer(this._timer);
        this._timer = null;
        this._emitState();
        return true;
    };

    KShopWriteCoordinator.prototype._finishExclusive = function(result, callback) {
        this._exclusive = null;
        if (typeof callback === 'function') callback(result || { success: false, error: 'unknown' });
        this._emitState();
        this._continueClose();
    };

    KShopWriteCoordinator.prototype._ensureSaved = function(callback) {
        var self = this;
        if (this._timer) this._clearTimer(this._timer);
        this._timer = null;
        if (this._saveInFlight) {
            this._saveInFlight.waiters.push(function(result) {
                if (!result.success) callback(result);
                else self._ensureSaved(callback);
            });
            return;
        }
        if (this._savedRevision >= this._revision) {
            callback({ success: true, synced: true });
            return;
        }
        this._sendSave('sync', function(result) {
            if (!result.success) callback(result);
            else self._ensureSaved(callback);
        });
    };

    KShopWriteCoordinator.prototype._sendSave = function(purpose, callback) {
        var self = this;
        if (this._saveInFlight) {
            if (typeof callback === 'function') this._saveInFlight.waiters.push(callback);
            return;
        }
        if (this._savedRevision >= this._revision) {
            if (typeof callback === 'function') callback({ success: true, synced: true });
            return;
        }

        var entry = {
            revision: this._revision,
            cart: cloneCart(this._getCart()),
            purpose: purpose,
            waiters: typeof callback === 'function' ? [callback] : []
        };
        this._saveInFlight = entry;
        this._emitState();
        this._request('saveCart', { cart: entry.cart }, function(response) {
            if (self._saveInFlight !== entry) return;
            self._saveInFlight = null;
            if (response && response.success === true) {
                self._savedRevision = Math.max(self._savedRevision, entry.revision);
                self._drainWaiters(entry.waiters, response);
                if (self._savedRevision < self._revision && !self._exclusive && !self._closing) self._scheduleAutoSave();
                self._emitState();
                self._continueClose();
            } else if (response && response.success === false && response.error === 'busy') {
                self._drainWaiters(entry.waiters, response);
                self._emitState();
            } else {
                self._startReconcile('saveCart', response, function(result) {
                    self._drainWaiters(entry.waiters, result);
                    self._continueClose();
                });
            }
        });
    };

    KShopWriteCoordinator.prototype._startReconcile = function(origin, originalResponse, continuation) {
        var self = this;
        if (this._reconciling) return;
        this._reconciling = { origin: origin };
        this._emitState();
        this._request('bulkQuery', {}, function(response) {
            self._reconciling = null;
            if (!isValidBulkSnapshot(response)) {
                self._reconcileBlocked = {
                    origin: origin,
                    originalResponse: originalResponse,
                    continuation: continuation,
                    lastError: response && response.success === false
                        ? response
                        : { success: false, error: 'invalid_response' }
                };
                self._emitState();
                return;
            }

            var preserveCart = origin === 'saveCart';
            self._applyBulkSnapshot(response, { reason: origin, preserveCart: preserveCart });
            if (preserveCart) {
                if (cartEquals(response.cart, self._getCart())) {
                    self._savedRevision = self._revision;
                    self._emitState();
                    continuation({ success: true, reconciled: true, snapshot: response });
                } else {
                    self._emitState();
                    self._ensureSaved(function(result) {
                        result.reconciled = true;
                        result.snapshot = response;
                        continuation(result);
                    });
                }
            } else {
                self._revision += 1;
                self._savedRevision = self._revision;
                self._emitState();
                continuation({
                    success: false,
                    error: originalResponse && originalResponse.error ? originalResponse.error : 'reconciled_unknown_result',
                    reconciled: true,
                    snapshot: response
                });
            }
        });
    };

    KShopWriteCoordinator.prototype._isDefinitive = function(cmd, response) {
        if (!response || typeof response.success !== 'boolean') return false;
        if (response.success) {
            if (cmd === 'checkoutCommit') return response.v === 1 && isFiniteNumber(response.newBalance)
                && Array.isArray(response.delivered) && Array.isArray(response.cart) && Array.isArray(response.purchased)
                && typeof response.purchasedToken === 'string' && response.purchasedToken.length > 0;
            if (cmd === 'claim') return Array.isArray(response.purchased)
                && typeof response.purchasedToken === 'string' && response.purchasedToken.length > 0;
            return false;
        }
        if (response.error === 'busy') return true;
        if (cmd === 'checkoutCommit') return response.error === 'insufficient_kpoints'
            || response.error === 'inventory_full' || response.error === 'stale_state';
        if (cmd === 'claim') return response.error === 'inventory_full'
            || response.error === 'acquire_failed';
        return false;
    };

    KShopWriteCoordinator.prototype._continueClose = function() {
        if (!this._closing || !this._closeCallback) return;
        if (this._exclusive || this._reconciling || this._reconcileBlocked) return;
        var self = this;
        var callback = this._closeCallback;
        this._ensureSaved(function(result) {
            if (!self._closing || self._closeCallback !== callback) return;
            if (result.success) {
                self._closeCallback = null;
                callback({ success: true });
            } else {
                self._closing = false;
                self._closeCallback = null;
                self._emitState();
                callback(result);
            }
        });
    };

    KShopWriteCoordinator.prototype._drainWaiters = function(waiters, result) {
        for (var i = 0; i < waiters.length; i++) waiters[i](result);
    };

    KShopWriteCoordinator.prototype._stateSnapshot = function() {
        return {
            opened: this._opened,
            closing: this._closing,
            exclusive: this._exclusive,
            saveInFlight: !!this._saveInFlight,
            reconciling: !!this._reconciling,
            reconcileBlocked: !!this._reconcileBlocked,
            dirty: this._savedRevision < this._revision,
            revision: this._revision,
            savedRevision: this._savedRevision,
            canEditCart: this.canEditCart(),
            canStartWrite: this._opened && !this._closing && !this._exclusive && !this._reconciling && !this._reconcileBlocked
        };
    };

    KShopWriteCoordinator.prototype._emitState = function() {
        this._onStateChange(this._stateSnapshot());
    };

    return {
        KShopRequestMux: KShopRequestMux,
        KShopWriteCoordinator: KShopWriteCoordinator,
        cartEquals: cartEquals,
        isValidBulkSnapshot: isValidBulkSnapshot
    };
});
