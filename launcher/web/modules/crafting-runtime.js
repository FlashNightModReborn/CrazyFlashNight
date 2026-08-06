/** Crafting request facade backed by the shared panel runtime. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var inventory = typeof module !== 'undefined' && module.exports
        ? require('./inventory-runtime.js') : root && root.InventoryRuntime;
    var api = factory(shared, inventory);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CraftingRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime, InventoryRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');
    if (!InventoryRuntime || !InventoryRuntime.isValidItemProjection
            || !InventoryRuntime.isValidConfirmProjection
            || !InventoryRuntime.isValidStableConfirmProjection) {
        throw new Error('InventoryRuntime projection validators are required');
    }

    function strictText(value) {
        return typeof value === 'string' && value.length <= 256
            && value.trim().length > 0 && value.trim().toLowerCase() !== 'undefined'
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function identityTriple(value, internalField) {
        return !!value && typeof value === 'object'
            && strictText(value[internalField])
            && strictText(value.displayName)
            && strictText(value.icon);
    }

    function identityArray(value, internalField) {
        return Array.isArray(value) && value.every(function(item) {
            return identityTriple(item, internalField);
        });
    }

    function own(value, key) {
        return Object.prototype.hasOwnProperty.call(value || {}, key);
    }

    function exactKeys(value, keys) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var actual = Object.keys(value).sort();
        var expected = keys.slice().sort();
        return actual.length === expected.length && actual.every(function(key, index) {
            return key === expected[index];
        });
    }

    function same(left, right) {
        if (left === right) return true;
        if (Array.isArray(left) || Array.isArray(right)) {
            return Array.isArray(left) && Array.isArray(right)
                && left.length === right.length && left.every(function(value, index) {
                    return same(value, right[index]);
                });
        }
        if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
        var leftKeys = Object.keys(left).sort(), rightKeys = Object.keys(right).sort();
        return leftKeys.length === rightKeys.length
            && leftKeys.every(function(key, index) {
                return key === rightKeys[index] && same(left[key], right[key]);
            });
    }

    var RESPONSE_ENVELOPE = ['type', 'domain', 'panel', 'panelInstanceId', 'cmd', 'callId'];
    var ITEM_KEYS = ['name', 'displayName', 'icon', 'itemKind', 'value', 'quantity',
        'enhancementLevel', 'majorType', 'use', 'actionType', 'weaponType',
        'setId', 'setName', 'setOrder', 'requiredLevel'];
    var MATERIAL_KEYS = ['name', 'displayName', 'icon', 'itemKind', 'required', 'owned',
        'maxEnhancement', 'isQuantity', 'tier', 'consumed', 'enough', 'storageKind'];
    var STORAGE_KINDS = ['bag', 'drug', 'bag_and_drug', 'material_collection',
        'information_collection', 'unavailable'];

    function finiteNonNegative(value) {
        return typeof value === 'number' && isFinite(value) && value >= 0;
    }

    function validProjectedItem(value) {
        var valid = exactKeys(value, ITEM_KEYS) && identityTriple(value, 'name')
            && (value.itemKind === 'equipment' || value.itemKind === 'stack')
            && finiteNonNegative(value.value) && finiteNonNegative(value.quantity)
            && finiteNonNegative(value.enhancementLevel) && finiteNonNegative(value.requiredLevel)
            && typeof value.majorType === 'string' && typeof value.use === 'string'
            && typeof value.actionType === 'string' && typeof value.weaponType === 'string'
            && typeof value.setId === 'string' && typeof value.setName === 'string'
            && Number.isInteger(value.setOrder) && Number.isInteger(value.value)
            && Number.isInteger(value.quantity) && Number.isInteger(value.enhancementLevel)
            && value.value > 0 && value.quantity > 0;
        if (!valid) return false;
        return value.itemKind === 'equipment'
            ? value.quantity === 1 && value.enhancementLevel === value.value
            : value.enhancementLevel === 0 && value.quantity === value.value;
    }

    function validMaterial(value) {
        return exactKeys(value, MATERIAL_KEYS) && identityTriple(value, 'name')
            && (value.itemKind === 'equipment' || value.itemKind === 'stack')
            && finiteNonNegative(value.required) && finiteNonNegative(value.owned)
            && finiteNonNegative(value.maxEnhancement) && typeof value.isQuantity === 'boolean'
            && typeof value.tier === 'string' && typeof value.consumed === 'boolean'
            && typeof value.enough === 'boolean' && STORAGE_KINDS.indexOf(value.storageKind) >= 0;
    }

    function validCost(value) {
        return exactKeys(value, ['money', 'kpoints'])
            && finiteNonNegative(value.money) && finiteNonNegative(value.kpoints);
    }

    function validOutputDelivery(value, output) {
        if (!exactKeys(value, ['available', 'storageKind', 'mode', 'physicalSlot', 'quantity'])
                || typeof value.available !== 'boolean'
                || STORAGE_KINDS.indexOf(value.storageKind) < 0
                || !Number.isInteger(value.physicalSlot) || !finiteNonNegative(value.quantity)
                || value.quantity !== output.quantity) return false;
        if (!value.available) return value.storageKind === 'unavailable'
            && value.mode === 'none' && value.physicalSlot === -1;
        if (value.storageKind === 'bag') return (value.mode === 'insert'
                || value.mode === 'merge' && output.itemKind === 'stack')
            && value.physicalSlot >= 0 && value.physicalSlot < 50;
        if (value.storageKind === 'drug') return output.itemKind === 'stack'
            && value.mode === 'merge' && value.physicalSlot >= 0;
        return (value.storageKind === 'material_collection'
                || value.storageKind === 'information_collection')
            && output.itemKind === 'stack'
            && value.mode === 'increment' && value.physicalSlot === -1;
    }

    function validAcceptedPlan(plan, response, outputField) {
        return exactKeys(plan, ['category', 'recipeIndex', 'craftCount', 'output', 'materials',
            'outputDelivery', 'outputPrototype', 'cost'])
            && plan.category === response.category
            && plan.recipeIndex === response.recipeIndex
            && plan.craftCount === response.craftCount
            && same(plan.output, response[outputField])
            && Array.isArray(plan.materials) && plan.materials.every(validMaterial)
            && validProjectedItem(plan.output) && validCost(plan.cost)
            && validOutputDelivery(plan.outputDelivery, plan.output)
            && validOutputPrototype(plan.outputPrototype, plan.output, plan.outputDelivery);
    }

    function hasPhysicalReceipt(delivery) {
        return !!delivery && delivery.available === true
            && (delivery.storageKind === 'bag' || delivery.storageKind === 'drug');
    }

    function validOutputPrototype(value, output, delivery) {
        if (!hasPhysicalReceipt(delivery)) {
            return value === null && (delivery.storageKind === 'material_collection'
                || delivery.storageKind === 'information_collection');
        }
        if (!exactKeys(value, ['item', 'confirmProjection'])
                || !InventoryRuntime.isValidItemProjection(value.item)
                || !InventoryRuntime.isValidStableConfirmProjection(
                    value.confirmProjection, value.item)) return false;
        return value.item.name === output.name
            && value.item.displayName === output.displayName
            && value.item.icon === output.icon
            && value.item.itemKind === output.itemKind
            && value.item.quantity === output.quantity
            && value.item.enhancementLevel === output.enhancementLevel
            && value.item.quantity === delivery.quantity;
    }

    function validOutputReceipt(value, acceptedPlan, crafted) {
        var delivery = acceptedPlan && acceptedPlan.outputDelivery;
        if (!hasPhysicalReceipt(delivery)) {
            return value === null && delivery
                && (delivery.storageKind === 'material_collection'
                    || delivery.storageKind === 'information_collection');
        }
        var prototype = acceptedPlan.outputPrototype;
        if (!exactKeys(value, ['item', 'confirmProjection'])
                || !prototype || !prototype.item || !prototype.confirmProjection
                || !InventoryRuntime.isValidItemProjection(value.item)
                || !InventoryRuntime.isValidConfirmProjection(
                    value.confirmProjection, value.item)
                || !Number.isInteger(value.item.quantity)
                || value.item.quantity < 1) return false;
        if (delivery.mode === 'insert') {
            if (value.item.quantity !== crafted.quantity) return false;
        } else if (delivery.mode !== 'merge' || value.item.quantity < crafted.quantity) {
            return false;
        }
        var normalizedItem = JSON.parse(JSON.stringify(value.item));
        normalizedItem.quantity = prototype.item.quantity;
        var normalizedConfirm = JSON.parse(JSON.stringify(value.confirmProjection));
        delete normalizedConfirm.lastUpdate;
        normalizedConfirm.quantity = prototype.confirmProjection.quantity;
        return same(normalizedItem, prototype.item)
            && same(normalizedConfirm, prototype.confirmProjection);
    }

    function validSourceLabels(value) {
        return Array.isArray(value) && value.every(function(source) {
            if (!source || typeof source !== 'object') return false;
            if (source.kind === 'enemy') {
                return strictText(source.displayName)
                    && typeof source.enemyType === 'string';
            }
            if (source.kind === 'quest') {
                return strictText(source.title)
                    && typeof source.questId === 'string';
            }
            return true;
        });
    }

    // Crafting owns several distinct response shapes. Keep their identity-leaf
    // validation here instead of teaching a shared primitive to guess aliases.
    function validateBusinessResponse(data, entry) {
        if (!data || data.success !== true) return !!data && data.success === false;
        var cmd = entry && entry.cmd;
        var payload = entry && entry.metadata && entry.metadata.payload || {};
        if (cmd === 'snapshot') {
            return Array.isArray(data.recipes) && data.recipes.every(function(recipe) {
                return !!recipe && identityTriple(recipe.output, 'name');
            });
        }
        if (cmd === 'materials') return identityArray(data.materials, 'name');
        if (cmd === 'materialDetail') {
            return identityTriple(data.material, 'name')
                && identityArray(data.uses, 'name')
                && validSourceLabels(data.sources)
                && strictText(payload.itemName)
                && data.material.name === payload.itemName;
        }
        if (cmd === 'preview') {
            var previewKeys = RESPONSE_ENVELOPE.concat(['success', 'v', 'category', 'recipeIndex',
                'craftCount', 'batchEligible', 'maxCraftCount', 'output', 'materials', 'cost',
                'balance', 'skills', 'levelAllowed', 'enoughMaterials', 'enoughMoney',
                'enoughKpoints', 'enoughSpace', 'canCommit', 'blockingError', 'outputDelivery']);
            if (data.canCommit === true) previewKeys.push('craftToken', 'acceptedPlan');
            return exactKeys(data, previewKeys)
                && validProjectedItem(data.output) && Array.isArray(data.materials)
                && data.materials.every(validMaterial)
                && validOutputDelivery(data.outputDelivery, data.output)
                && data.outputDelivery.available === data.enoughSpace
                && (data.canCommit !== true || data.materials.every(function(material) {
                    return material.storageKind !== 'unavailable';
                }))
                && (data.canCommit !== true || strictText(data.craftToken)
                    && validAcceptedPlan(data.acceptedPlan, data, 'output')
                    && same(data.acceptedPlan.materials, data.materials)
                    && same(data.acceptedPlan.outputDelivery, data.outputDelivery)
                    && same(data.acceptedPlan.cost, data.cost));
        }
        if (cmd === 'commit') {
            return exactKeys(data, RESPONSE_ENVELOPE.concat(['success', 'v', 'operation',
                'category', 'recipeIndex', 'craftCount', 'crafted', 'acceptedPlan',
                'outputReceipt', 'balance']))
                && data.operation === 'commit' && validProjectedItem(data.crafted)
                && validAcceptedPlan(data.acceptedPlan, data, 'crafted')
                && validOutputReceipt(data.outputReceipt, data.acceptedPlan, data.crafted);
        }
        if (cmd === 'tooltip') {
            // Host has already translated the one allowed legacy displayname
            // profile. Web accepts only the canonical post-Host spelling.
            return strictText(data.itemName) && strictText(data.displayName)
                && strictText(payload.itemName) && data.itemName === payload.itemName;
        }
        return false;
    }

    function RequestMux(options) {
        options = options || {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            callPrefix:'craft',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!session && session.ownerPanel === 'crafting'
                    && /^[A-Za-z0-9._~-]{1,128}$/.test(String(session.panelInstanceId || ''));
            },
            createMessage:function(context) {
                return {type:'panel', domain:'crafting', panel:'crafting', cmd:context.entry.cmd,
                    panelInstanceId:context.session.panelInstanceId,
                    callId:context.entry.callId, payload:context.payload || {}};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.domain === 'crafting'
                    && data.panel === 'crafting'
                    && data.panelInstanceId === entry.session.panelInstanceId
                    && data.callId === entry.callId && data.cmd === entry.cmd
                    && validateBusinessResponse(data, entry);
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', domain:'crafting', panel:'crafting',
                    panelInstanceId:context.session.panelInstanceId, cmd:context.entry.cmd,
                    callId:context.entry.callId, success:false, error:context.error,
                    clientSynthetic:true};
            }
        });
    }

    RequestMux.prototype.openSession = function(session) { return this._mux.openSession(session || {}); };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, callback) {
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
        return {generation:state.generation, sequence:state.sequence, active:state.active,
            pendingCount:state.pendingCount};
    };

    return {RequestMux:RequestMux, validateBusinessResponse:validateBusinessResponse,
        identityTriple:identityTriple};
});
