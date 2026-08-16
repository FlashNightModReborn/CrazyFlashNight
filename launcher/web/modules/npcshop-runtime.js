/** NPC shop/inventory request facade backed by the shared panel runtime. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.NpcShopRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var NPC_COMMANDS = {
        snapshot:true, tooltip:true, batchPreview:true, tradePreview:true,
        buy:true, batchSell:true, tradeCommit:true
    };
    var PANEL_INSTANCE_PATTERN = /^[A-Za-z0-9._~-]{1,128}$/;
    var NAVIGATION_CALL_ID_PATTERN = /^[A-Za-z0-9._-]{1,96}$/;
    var SHOP_CATALOG_INDEX_MAX = 10000;
    var NAVIGATION_WATCHDOG_MS = 6500;
    var DIAGNOSTIC_EVENTS = {
        request_issued:true, client_timeout:true, send_failed:true,
        response_shape_mismatch:true, response_transform_failed:true,
        response_accepted:true, snapshot_adopted:true,
        snapshot_rejected:true, snapshot_stale:true
    };
    var DIAGNOSTIC_OUTCOMES = {
        issued:true, accepted:true, adopted:true, host_error:true,
        shape_mismatch:true, transform_failed:true, client_timeout:true,
        send_failed:true, stale:true
    };
    var DIAGNOSTIC_ERRORS = {
        '':true, other:true, malformed_response:true, timeout:true,
        client_timeout:true, disconnected:true, not_sent:true,
        invalid_payload:true, panel_instance_expired:true,
        npcshop_unavailable:true, stale_state:true, shop_not_found:true,
        item_not_found:true, locked:true, invalid_price:true,
        invalid_quantity:true, insufficient_quantity:true,
        insufficient_money:true, inventory_full:true, destination_full:true,
        nothing_to_sell:true, sell_forbidden:true, busy:true,
        reconcile_required:true, unsupported_cmd:true
    };
    var CLOSE_REASONS = {button:true, escape:true, backdrop:true, toggle:true};
    var RETURN_FAILURE_ERRORS = {
        invalid_payload:true, stale_source:true, navigation_unavailable:true,
        access_denied:true, source_not_settled:true, admission_failed:true,
        timeout:true, busy:true, return_unavailable:true
    };

    function own(value, key) {
        return Object.prototype.hasOwnProperty.call(value || {}, key);
    }

    function exactKeys(value, keys) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var actual = Object.keys(value).sort(), expected = keys.slice().sort();
        return actual.length === expected.length && actual.every(function(key, index) {
            return key === expected[index];
        });
    }

    function strictText(value) {
        return typeof value === 'string' && value.length > 0 && value.length <= 256
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function identityText(value) {
        return strictText(value) && value.trim().length > 0
            && value.trim().toLowerCase() !== 'undefined';
    }

    function boundedIdentity(value, maxLength) {
        return identityText(value) && value.length <= maxLength;
    }

    function shopCatalogIndex(value) {
        return Number.isInteger(value) && value >= 0 && value <= SHOP_CATALOG_INDEX_MAX;
    }

    function diagnosticOutcome(event, error) {
        if (event === 'request_issued') return 'issued';
        if (event === 'client_timeout') return 'client_timeout';
        if (event === 'send_failed') return 'send_failed';
        if (event === 'response_shape_mismatch') return 'shape_mismatch';
        if (event === 'response_transform_failed') return 'transform_failed';
        if (event === 'snapshot_adopted') return 'adopted';
        if (event === 'snapshot_stale') return 'stale';
        if (event === 'snapshot_rejected') {
            if (error === 'client_timeout' || error === 'timeout') return 'client_timeout';
            if (error === 'disconnected' || error === 'not_sent') return 'send_failed';
            return 'host_error';
        }
        return error ? 'host_error' : 'accepted';
    }

    function createDiagnosticMessage(record) {
        record = record || {};
        var event = String(record.event || '');
        var cmd = String(record.cmd || '');
        var callId = String(record.callId || '');
        var panelInstanceId = String(record.panelInstanceId || '');
        var generation = Number(record.generation);
        var error = String(record.error || '');
        if (!DIAGNOSTIC_EVENTS[event] || !NPC_COMMANDS[cmd]
                || !NAVIGATION_CALL_ID_PATTERN.test(callId)
                || !PANEL_INSTANCE_PATTERN.test(panelInstanceId)
                || !Number.isInteger(generation) || generation < 0
                || generation > 2147483647) return null;
        if (!DIAGNOSTIC_ERRORS[error]) error = 'other';
        var outcome = diagnosticOutcome(event, error);
        if (!DIAGNOSTIC_OUTCOMES[outcome]) return null;
        return {type:'debug', scope:'npcshop', event:event, outcome:outcome,
            cmd:cmd, webCallId:callId, panelInstanceId:panelInstanceId,
            generation:generation, error:error};
    }

    function createSnapshotDiagnostic(event, response, entry, panelInstanceId) {
        return {domain:'npcshop', event:event, cmd:'snapshot',
            callId:entry && entry.callId, generation:entry && entry.generation,
            panelInstanceId:entry && entry.session
                ? entry.session.panelInstanceId : panelInstanceId,
            error:response && response.success === false
                ? String(response.error || 'other') : ''};
    }

    function createDiagnosticEmitter(options) {
        options = options || {};
        var local = typeof options.local === 'function' ? options.local : null;
        var send = typeof options.send === 'function' ? options.send : null;
        return function(record) {
            if (local) { try { local(record); } catch (_) {} }
            if (!record || record.domain !== 'npcshop') return;
            if ((record.event === 'request_issued' || record.event === 'response_accepted')
                    && record.cmd !== 'snapshot') return;
            var message = createDiagnosticMessage(record);
            if (message && send) { try { send(message); } catch (_) {} }
        };
    }

    function parseInitData(value) {
        var ordinaryKeys = ['mode', 'source', 'debug', 'shopId', 'panelInstanceId'];
        var materialKeys = ordinaryKeys.concat(['preferredItemName',
            'preferredCatalogIndex', 'canReturnCraftingMaterials', 'navigationOrigin']);
        var ordinary = exactKeys(value, ordinaryKeys);
        var material = exactKeys(value, materialKeys);
        if ((!ordinary && !material) || value.mode !== 'runtime'
                || value.debug !== false || !boundedIdentity(value.source, 128)
                || !boundedIdentity(value.shopId, 80)
                || !PANEL_INSTANCE_PATTERN.test(String(value.panelInstanceId || ''))) return null;
        if (ordinary && value.source === 'crafting_materials') return null;
        if (material && (value.source !== 'crafting_materials'
                || !boundedIdentity(value.preferredItemName, 128)
                || !shopCatalogIndex(value.preferredCatalogIndex)
                || value.canReturnCraftingMaterials !== true
                || value.navigationOrigin !== 'crafting_materials')) return null;
        return {kind:material ? 'crafting_materials' : 'ordinary', data:value};
    }

    function identityTriple(value, internalField) {
        return !!value && typeof value === 'object'
            && identityText(value[internalField])
            && identityText(value.displayName)
            && identityText(value.icon);
    }

    function validateStateIdentity(data, payload, cmd) {
        if (!data || data.shopId !== payload.shopId || !Array.isArray(data.catalog)
                || !data.views || !data.views.material || !data.views.intelligence) return false;
        if (!data.catalog.every(function(item) { return identityTriple(item, 'itemName'); })) return false;
        for (var key of ['material', 'intelligence']) {
            var slots = data.views[key] && data.views[key].slots;
            if (!Array.isArray(slots) || !slots.every(function(slot) {
                return !slot.occupied || identityTriple(slot.item, 'name');
            })) return false;
        }
        if (!cmd || cmd === 'snapshot') return true;
        if (data.operation !== cmd) return false;
        if (cmd === 'buy' && Number(data.quantity) !== Number(payload.quantity)) return false;
        return true;
    }

    function validateBusinessResponse(data, entry) {
        if (!data || data.success !== true) return !!data && data.success === false;
        var payload = entry && entry.metadata && entry.metadata.payload || {};
        var cmd = entry && entry.cmd;
        if (cmd === 'snapshot' || cmd === 'buy'
                || cmd === 'batchSell' || cmd === 'tradeCommit') {
            return validateStateIdentity(data, payload, cmd);
        }
        if (cmd === 'tradePreview') {
            return data.shopId === payload.shopId
                && Array.isArray(data.purchaseLines) && Array.isArray(data.saleLines)
                && data.purchaseLines.every(function(line) { return identityTriple(line, 'itemName'); })
                && data.saleLines.every(function(line) { return identityTriple(line, 'itemName'); });
        }
        if (cmd === 'batchPreview') {
            return Array.isArray(data.summary)
                && data.summary.every(function(line) { return identityTriple(line, 'itemName'); });
        }
        if (cmd === 'tooltip') {
            return identityText(data.itemName)
                && identityText(data.displayname)
                && (!Object.prototype.hasOwnProperty.call(data, 'iconName')
                    || identityText(data.iconName))
                && (!payload.itemName || data.itemName === payload.itemName);
        }
        return false;
    }

    function OwnerLifecycle(options) {
        options = options || {};
        this._panel = String(options.panel || 'npcshop');
        this._muxes = Array.isArray(options.muxes) ? options.muxes.slice() : [];
        this.panelInstanceId = '';
        this.generation = 0;
        this.needsReconcile = false;
        this.reconcileEpoch = 0;
    }

    OwnerLifecycle.prototype.open = function(panelInstanceId) {
        if (typeof panelInstanceId !== 'string' || !PANEL_INSTANCE_PATTERN.test(panelInstanceId)) {
            return false;
        }
        var session = {ownerPanel:this._panel, panelInstanceId:panelInstanceId};
        var opened = [];
        this.generation++;
        for (var i = 0; i < this._muxes.length; i++) {
            var mux = this._muxes[i];
            if (!mux || typeof mux.openSession !== 'function' || !mux.openSession(session)) {
                for (var j = 0; j < opened.length; j++) opened[j].closeSession();
                this.panelInstanceId = '';
                this.needsReconcile = false;
                this.reconcileEpoch = 0;
                return false;
            }
            opened.push(mux);
        }
        this.panelInstanceId = panelInstanceId;
        this.needsReconcile = false;
        this.reconcileEpoch = 0;
        return true;
    };

    OwnerLifecycle.prototype.close = function() {
        this.generation++;
        for (var i = 0; i < this._muxes.length; i++) {
            if (this._muxes[i] && typeof this._muxes[i].closeSession === 'function') {
                this._muxes[i].closeSession();
            }
        }
        this.panelInstanceId = '';
        this.needsReconcile = false;
        this.reconcileEpoch = 0;
    };

    OwnerLifecycle.prototype.captureSnapshot = function() {
        return {generation:this.generation, reconcileEpoch:this.reconcileEpoch,
            isReconcileProbe:this.needsReconcile};
    };

    OwnerLifecycle.prototype.isCurrentSnapshot = function(intent) {
        return !!intent && intent.generation === this.generation
            && intent.reconcileEpoch === this.reconcileEpoch
            && (!this.needsReconcile || intent.isReconcileProbe);
    };

    OwnerLifecycle.prototype.enterNeedsReconcile = function() {
        if (!this.needsReconcile) this.reconcileEpoch++;
        this.needsReconcile = true;
    };

    OwnerLifecycle.prototype.acceptAuthorityState = function() {
        this.needsReconcile = false;
    };

    OwnerLifecycle.prototype.closeMessage = function(reason) {
        reason = String(reason || '');
        if (!CLOSE_REASONS[reason] || !this.panelInstanceId) return null;
        return {type:'panel', cmd:'close', panel:this._panel,
            panelInstanceId:this.panelInstanceId, reason:reason};
    };

    function RequestMux(options) {
        options = options || {};
        var domain = String(options.domain || 'npcshop');
        var panel = String(options.panel || 'npcshop');
        var prefix = String(options.callPrefix || (domain === 'npcshop' ? 'npc' : 'npc-' + domain));
        var diagnostic = typeof options.diagnostic === 'function'
            ? options.diagnostic : function() {};
        this._domain = domain;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            callPrefix:prefix,
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!session && session.ownerPanel === panel
                    && /^[A-Za-z0-9._~-]{1,128}$/.test(String(session.panelInstanceId || ''));
            },
            createMessage:function(context) {
                return {type:'panel', domain:domain, panel:panel, cmd:context.entry.cmd,
                    panelInstanceId:context.session.panelInstanceId,
                    callId:context.entry.callId, payload:context.payload || {}};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.domain === domain
                    && data.panel === panel
                    && data.panelInstanceId === entry.session.panelInstanceId
                    && data.callId === entry.callId && data.cmd === entry.cmd
                    && (domain !== 'npcshop' || validateBusinessResponse(data, entry));
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', domain:domain, panel:panel, cmd:context.entry.cmd,
                    panelInstanceId:context.session.panelInstanceId,
                    callId:context.entry.callId, success:false, error:context.error,
                    clientSynthetic:true};
            },
            onDiagnostic:function(record, entry) {
                diagnostic({domain:domain, event:record.event, cmd:record.cmd,
                    callId:record.callId, generation:record.generation,
                    panelInstanceId:entry && entry.session
                        ? entry.session.panelInstanceId : '',
                    error:record.error});
            }
        });
    }

    RequestMux.prototype.openSession = function(session) { return this._mux.openSession(session || {}); };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, callback) {
        if (this._domain === 'npcshop' && !NPC_COMMANDS[String(cmd || '')]) {
            if (typeof callback === 'function') callback({
                success:false,error:'unsupported_cmd',clientSynthetic:true
            });
            return null;
        }
        var frozenPayload;
        try { frozenPayload = JSON.parse(JSON.stringify(payload || {})); }
        catch (_) { return null; }
        return this._mux.request(cmd, payload, {sendError:'disconnected',
            metadata:{payload:frozenPayload}}, callback);
    };
    RequestMux.prototype.handleResponse = function(data) { return this._mux.handleResponse(data); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {domain:this._domain, generation:state.generation, sequence:state.sequence,
            active:state.active, pendingCount:state.pendingCount};
    };

    function createOwnerChannels(send, options) {
        options = options || {};
        function muxOptions(domain, callPrefix) {
            return {send:send,
                timeoutMs:options.timeoutMs == null ? options.requestTimeoutMs : options.timeoutMs,
                sessionNonce:options.sessionNonce, setTimer:options.setTimer,
                clearTimer:options.clearTimer, router:options.router,
                domain:domain, panel:'npcshop', callPrefix:callPrefix,
                diagnostic:options.diagnostic};
        }
        var business = new RequestMux(muxOptions('npcshop', 'npc'));
        var inventory = new RequestMux(muxOptions('inventory', 'npc-inv'));
        return {business:business, inventory:inventory,
            owner:new OwnerLifecycle({panel:'npcshop', muxes:[business, inventory]})};
    }

    function PhysicalInventoryAdapter(options) {
        options = options || {};
        var runtime = options.inventoryRuntime;
        if (!runtime || typeof runtime.InventoryCoordinator !== 'function'
                || typeof runtime.readPhysicalInventorySurface !== 'function'
                || typeof options.request !== 'function' || !options.owner) {
            throw new Error('NPC physical Inventory dependencies are required');
        }
        var request = options.request, owner = options.owner;
        this._onApplied = typeof options.onApplied === 'function' ? options.onApplied : function() {};
        this._surfaceReceipt = null;
        this.coordinator = new runtime.InventoryCoordinator({
            request:request,
            readPhysicalSurface:function(isActive, callback) {
                return runtime.readPhysicalInventorySurface(request,
                    {isActive:isActive, expectedPanel:'npcshop',
                        expectedPanelInstanceId:owner.panelInstanceId}, callback);
            },
            requests:[
                {containerId:'背包', offset:0, limit:50, filterKey:'all'},
                {containerId:'战备箱', offset:0, limit:40, filterKey:'all'}
            ],
            onStateChange:options.onStateChange
        });
    }

    PhysicalInventoryAdapter.prototype.refresh = function(callback) {
        var self = this, coordinator = this.coordinator;
        coordinator.open(function(result) {
            result = result || {success:false};
            self._surfaceReceipt = result.success && result.surface
                ? JSON.parse(JSON.stringify(result.surface)) : null;
            self._onApplied(result);
            if (typeof callback === 'function') callback(result);
        });
        return true;
    };

    PhysicalInventoryAdapter.prototype.resetSession = function() {
        var coordinator = this.coordinator;
        if (coordinator.debugState().opened) return false;
        var backpack = coordinator.getRequest('背包');
        var battlebox = coordinator.getRequest('战备箱');
        if (!backpack || !battlebox) return false;
        this._surfaceReceipt = null;
        return coordinator.configureRequests([
            {containerId:'背包', offset:backpack.offset, limit:50, filterKey:'all'},
            {containerId:'战备箱', offset:battlebox.offset, limit:40, filterKey:'all'}
        ]);
    };

    PhysicalInventoryAdapter.prototype.close = function() {
        this.coordinator.close();
        this._surfaceReceipt = null;
    };

    PhysicalInventoryAdapter.prototype.getReceipt = function() {
        return this._surfaceReceipt ? JSON.parse(JSON.stringify(this._surfaceReceipt)) : null;
    };

    function createPhysicalInventoryAdapter(options) {
        return new PhysicalInventoryAdapter(options);
    }

    function createReturnCraftingMaterialsMessage(input) {
        input = input || {};
        if (!NAVIGATION_CALL_ID_PATTERN.test(String(input.callId || ''))
                || !PANEL_INSTANCE_PATTERN.test(String(input.panelInstanceId || ''))) return null;
        return {type:'panel', panel:'npcshop', cmd:'return_crafting_materials',
            callId:String(input.callId), panelInstanceId:String(input.panelInstanceId)};
    }

    function validateReturnCraftingMaterialsFailure(data, expected) {
        expected = expected || {};
        return exactKeys(data, ['type', 'panel', 'cmd', 'callId',
                'panelInstanceId', 'success', 'error'])
            && data.type === 'panel_resp'
            && data.panel === 'npcshop'
            && data.cmd === 'return_crafting_materials'
            && data.success === false
            && NAVIGATION_CALL_ID_PATTERN.test(String(data.callId || ''))
            && PANEL_INSTANCE_PATTERN.test(String(data.panelInstanceId || ''))
            && !!RETURN_FAILURE_ERRORS[String(data.error || '')]
            && (!expected.callId || data.callId === expected.callId)
            && (!expected.panelInstanceId
                || data.panelInstanceId === expected.panelInstanceId);
    }

    return {RequestMux:RequestMux, OwnerLifecycle:OwnerLifecycle,
        createOwnerChannels:createOwnerChannels,
        createPhysicalInventoryAdapter:createPhysicalInventoryAdapter,
        validateBusinessResponse:validateBusinessResponse,
        createDiagnosticMessage:createDiagnosticMessage,
        createSnapshotDiagnostic:createSnapshotDiagnostic,
        createDiagnosticEmitter:createDiagnosticEmitter,
        identityTriple:identityTriple,
        SHOP_CATALOG_INDEX_MAX:SHOP_CATALOG_INDEX_MAX,
        NAVIGATION_WATCHDOG_MS:NAVIGATION_WATCHDOG_MS,
        parseInitData:parseInitData,
        validateInitData:function(value) { return !!parseInitData(value); },
        isShopCatalogIndex:shopCatalogIndex,
        isNavigationCallId:function(value) {
            return typeof value === 'string' && NAVIGATION_CALL_ID_PATTERN.test(value);
        },
        createReturnCraftingMaterialsMessage:createReturnCraftingMaterialsMessage,
        validateReturnCraftingMaterialsFailure:validateReturnCraftingMaterialsFailure,
        isCloseReason:function(value) { return !!CLOSE_REASONS[String(value || '')]; },
        isPanelInstanceId:function(value) {
            return typeof value === 'string' && PANEL_INSTANCE_PATTERN.test(value);
        },
        isSupportedCommand:function(cmd) { return !!NPC_COMMANDS[String(cmd || '')]; }};
});
