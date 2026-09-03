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
        root.KShopProtocol = api.KShopProtocol;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');
    var NAVIGATION_CALL_ID_PATTERN = /^[A-Za-z0-9._-]{1,96}$/;
    var PANEL_INSTANCE_PATTERN = /^[A-Za-z0-9._~-]{1,128}$/;
    var NAVIGATION_WATCHDOG_MS = 6500;
    var NAVIGATION_FAILURES = {
        invalid_payload:true, stale_source:true, navigation_unavailable:true,
        access_denied:true, source_not_settled:true, admission_failed:true,
        timeout:true, busy:true, return_unavailable:true
    };

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
            validateSession:function(session) {
                return !!session && session.ownerPanel === 'kshop'
                    && /^[A-Za-z0-9._~-]{1,128}$/.test(String(session.panelInstanceId || ''));
            },
            createMessage:function(context) {
                var message = PanelRuntime.copyOwn(context.payload);
                message.type = 'panel';
                message.panel = 'kshop';
                message.panelInstanceId = context.session.panelInstanceId;
                message.cmd = context.entry.cmd;
                message.callId = context.entry.callId;
                if (context.entry.metadata.channel === 'inventory') message.domain = 'inventory';
                else if (Object.prototype.hasOwnProperty.call(message, 'domain')) delete message.domain;
                return message;
            },
            validateResponse:function(data, entry) {
                if (!data || data.type !== 'panel_resp' || data.callId !== entry.callId) return false;
                if (entry.metadata.channel === 'inventory') {
                    return data.domain === 'inventory' && data.panel === 'kshop'
                        && data.panelInstanceId === entry.session.panelInstanceId
                        && data.cmd === entry.cmd;
                }
                return !Object.prototype.hasOwnProperty.call(data, 'domain')
                    && data.panel === 'kshop'
                    && data.panelInstanceId === entry.session.panelInstanceId
                    && data.cmd === entry.cmd;
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', panel:'kshop',
                    panelInstanceId:context.session.panelInstanceId,
                    callId:context.entry.callId, cmd:context.entry.cmd,
                    success:false, error:context.error, clientSynthetic:true};
            }
        });
    }

    KShopRequestMux.prototype.openSession = function(session) {
        return this._mux.openSession(session || {});
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

    function isInteger(value) {
        return isFiniteNumber(value) && Math.floor(value) === value;
    }

    function safeText(value, maximum, allowEmpty) {
        return typeof value === 'string' && value.length <= maximum
            && (allowEmpty || value.length > 0) && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function identityText(value, maximum) {
        return safeText(value, maximum, false)
            && value.trim().length > 0 && value.trim().toLowerCase() !== 'undefined';
    }

    function validToken(value) {
        return typeof value === 'string' && /^[A-Za-z0-9._-]{1,160}$/.test(value);
    }

    function exactKeys(value, required, optional) {
        if (!value || Object.prototype.toString.call(value) !== '[object Object]') return false;
        optional = optional || [];
        var allowed = {};
        for (var i = 0; i < required.length; i++) {
            allowed[required[i]] = true;
            if (!Object.prototype.hasOwnProperty.call(value, required[i])) return false;
        }
        for (var j = 0; j < optional.length; j++) allowed[optional[j]] = true;
        var keys = Object.keys(value);
        for (var k = 0; k < keys.length; k++) if (!allowed[keys[k]]) return false;
        return true;
    }

    function cloneJson(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function normalizeCartPayload(value, minimum) {
        if (!Array.isArray(value) || value.length < minimum || value.length > 40) return null;
        var result = [];
        for (var i = 0; i < value.length; i++) {
            var line = value[i];
            if (!exactKeys(line, ['idx','qty']) || !isInteger(line.idx) || !isInteger(line.qty)) return null;
            result.push({idx:line.idx, qty:line.qty});
        }
        return result;
    }

    function normalizeRequest(cmd, payload) {
        payload = payload || {};
        if (cmd === 'bulkQuery') return exactKeys(payload, []) ? {} : null;
        if (cmd === 'tooltip') return exactKeys(payload, ['idx']) && isInteger(payload.idx)
            ? {idx:payload.idx} : null;
        if (cmd === 'saveCart' || cmd === 'checkout') {
            var saved = exactKeys(payload, ['cart']) ? normalizeCartPayload(payload.cart, 0) : null;
            return saved ? {cart:saved} : null;
        }
        if (cmd === 'checkoutPreview') {
            var preview = exactKeys(payload, ['v','cart']) && payload.v === 1
                ? normalizeCartPayload(payload.cart, 0) : null;
            return preview ? {v:1, cart:preview} : null;
        }
        if (cmd === 'checkoutCommit') return exactKeys(payload, ['v','expectedCheckoutToken'])
            && payload.v === 1 && validToken(payload.expectedCheckoutToken)
            ? {v:1, expectedCheckoutToken:payload.expectedCheckoutToken} : null;
        if (cmd === 'claim') return exactKeys(payload, ['purchasedIdx','expectedPurchasedToken'])
            && isInteger(payload.purchasedIdx) && validToken(payload.expectedPurchasedToken)
            ? {purchasedIdx:payload.purchasedIdx,
                expectedPurchasedToken:payload.expectedPurchasedToken} : null;
        return null;
    }

    function sanitizeBalanceSummary(value) {
        if (!exactKeys(value, ['state','weightLayers','formula','level'])
                || value.state !== 'confirmed' || !isInteger(value.weightLayers)
                || value.formula !== 1 || !isInteger(value.level) || value.level < 0) return null;
        return {state:'confirmed',weightLayers:value.weightLayers,formula:1,level:value.level};
    }

    function validRecipeId(value) {
        return typeof value === 'string' && value.length <= 96
            && /^craft\.[a-z0-9.-]+$/.test(value);
    }

    function parseProcurementNavigationInit(value) {
        value = value || {};
        if (value.navigationOrigin !== 'crafting_recipe'
                || value.canReturnCraftingRecipe !== true
                || !PANEL_INSTANCE_PATTERN.test(String(value.panelInstanceId || ''))
                || !identityText(value.preferredItemName, 128)
                || !Number.isSafeInteger(value.preferredCatalogIndex)
                || value.preferredCatalogIndex < 0 || value.preferredCatalogIndex > 10000
                || !identityText(value.preferredEntryId, 256)
                || !identityText(value.preferredKShopCategory, 512)
                || !identityText(value.returnRecipeCategory, 256)
                || !Number.isSafeInteger(value.returnRecipeIndex)
                || value.returnRecipeIndex < 0 || value.returnRecipeIndex > 999) return null;
        return {
            panelInstanceId:String(value.panelInstanceId),
            preferredItemName:String(value.preferredItemName),
            preferredCatalogIndex:Number(value.preferredCatalogIndex),
            preferredEntryId:String(value.preferredEntryId),
            preferredKShopCategory:String(value.preferredKShopCategory),
            returnRecipeCategory:String(value.returnRecipeCategory),
            returnRecipeIndex:Number(value.returnRecipeIndex)
        };
    }

    function createReturnCraftingRecipeMessage(input) {
        input = input || {};
        if (!NAVIGATION_CALL_ID_PATTERN.test(String(input.callId || ''))
                || !PANEL_INSTANCE_PATTERN.test(String(input.panelInstanceId || '')))
            return null;
        return {type:'panel', panel:'kshop', cmd:'return_crafting_recipe',
            callId:String(input.callId),
            panelInstanceId:String(input.panelInstanceId)};
    }

    function validateReturnCraftingRecipeFailure(data, expected) {
        expected = expected || {};
        return exactKeys(data, ['type','panel','cmd','callId','panelInstanceId',
                'success','error'])
            && data.type === 'panel_resp' && data.panel === 'kshop'
            && data.cmd === 'return_crafting_recipe' && data.success === false
            && NAVIGATION_CALL_ID_PATTERN.test(String(data.callId || ''))
            && PANEL_INSTANCE_PATTERN.test(String(data.panelInstanceId || ''))
            && !!NAVIGATION_FAILURES[String(data.error || '')]
            && (!expected.callId || data.callId === expected.callId)
            && (!expected.panelInstanceId
                || data.panelInstanceId === expected.panelInstanceId);
    }

    function nonNegativeSafeInteger(value) {
        return Number.isSafeInteger(value) && value >= 0;
    }

    function sanitizeProcurementDemand(value, expectedItemName) {
        var fields = ['itemName','required','requiredEnhancement','usableOwned',
            'equippedOwned','battleBoxOwned','totalOwned','usableMaxEnhancement',
            'equippedMaxEnhancement','battleBoxMaxEnhancement','totalMaxEnhancement',
            'obtainMissing','relocateMissing',
            'needsEnhancement','craftRequired','taskRequired','plannedRecipeCount',
            'activeTaskCount','reasons','sources'];
        var numbers = ['required','requiredEnhancement','usableOwned','equippedOwned',
            'battleBoxOwned','totalOwned','usableMaxEnhancement',
            'equippedMaxEnhancement','battleBoxMaxEnhancement','totalMaxEnhancement',
            'obtainMissing','relocateMissing','craftRequired','taskRequired',
            'plannedRecipeCount','activeTaskCount'];
        if (!exactKeys(value, fields) || value.itemName !== expectedItemName
                || !identityText(value.itemName,128)
                || typeof value.needsEnhancement !== 'boolean'
                || !numbers.every(function(field) {
                    return nonNegativeSafeInteger(value[field]);
                }) || value.totalOwned !== value.usableOwned
                    + value.equippedOwned + value.battleBoxOwned
                || value.totalMaxEnhancement < value.usableMaxEnhancement
                || value.totalMaxEnhancement < value.equippedMaxEnhancement
                || value.totalMaxEnhancement < value.battleBoxMaxEnhancement
                || value.equippedOwned === 0 && value.equippedMaxEnhancement !== 0
                || value.battleBoxOwned === 0 && value.battleBoxMaxEnhancement !== 0
                || value.obtainMissing > Math.max(1,value.required)
                || value.relocateMissing > Math.max(1,value.required)
                || value.relocateMissing > value.equippedOwned + value.battleBoxOwned
                || !Array.isArray(value.reasons) || value.reasons.length < 1
                || value.reasons.length > 64 || !Array.isArray(value.sources)
                || value.sources.length > 32) return null;
        for (var r = 0; r < value.reasons.length; r++) {
            var reason = value.reasons[r];
            if (!exactKeys(reason,['kind','sourceId','label','required','mode'])
                    || (reason.kind !== 'craft' && reason.kind !== 'task')
                    || !identityText(reason.sourceId,128) || !identityText(reason.label,256)
                    || !Number.isSafeInteger(reason.required) || reason.required < 1
                    || ['consume','retain','submit','contain'].indexOf(reason.mode) < 0) return null;
        }
        var seen = {};
        for (var s = 0; s < value.sources.length; s++) {
            var source = value.sources[s], key;
            if (source && source.kind === 'npcshop') {
                if (!exactKeys(source,['kind','shopId','catalogIndex','label'])
                        || !identityText(source.shopId,80)
                        || !Number.isSafeInteger(source.catalogIndex)
                        || source.catalogIndex < 0 || source.catalogIndex > 10000
                        || !identityText(source.label,256)) return null;
                key = source.kind + '\u0000' + source.shopId + '\u0000' + source.catalogIndex;
            } else if (source && source.kind === 'kshop') {
                if (!exactKeys(source,['kind','catalogIndex','entryId','category','label'])
                        || !Number.isSafeInteger(source.catalogIndex)
                        || source.catalogIndex < 0 || source.catalogIndex > 10000
                        || !identityText(source.entryId,256)
                        || !safeText(source.category,128,true)
                        || !identityText(source.label,256)) return null;
                key = source.kind + '\u0000' + source.catalogIndex
                    + '\u0000' + source.entryId;
            } else return null;
            if (seen[key]) return null;
            seen[key] = true;
        }
        return cloneJson(value);
    }

    function sanitizeCatalog(value) {
        if (!Array.isArray(value) || value.length > 10000) return null;
        var result = [], seen = {};
        var fields = ['idx','id','item','type','price','displayname','majorType','subType',
            'actionType','weaponType','setId','setName','setOrder','level','icon','maxQuantity'];
        for (var i = 0; i < value.length; i++) {
            var item = value[i];
            if (!exactKeys(item, fields, ['balanceSummary','procurement']) || !isInteger(item.idx)
                    || item.idx < 0 || item.idx > 10000 || seen[item.idx]
                    || !safeText(item.id,128,false) || !identityText(item.item,128)
                    || !safeText(item.type,128,false) || !isFiniteNumber(item.price) || item.price < 0
                    || !identityText(item.displayname,256) || !safeText(item.majorType,128,true)
                    || !safeText(item.subType,128,true) || !safeText(item.actionType,128,true)
                    || !safeText(item.weaponType,128,true) || !safeText(item.setId,128,true)
                    || !safeText(item.setName,256,true) || !isInteger(item.setOrder) || item.setOrder < 0
                    || !isInteger(item.level) || item.level < 0 || !identityText(item.icon,256)
                    || !isInteger(item.maxQuantity) || item.maxQuantity < 0
                    || item.maxQuantity > 999999) return null;
            var clean = {};
            for (var f = 0; f < fields.length; f++) clean[fields[f]] = item[fields[f]];
            if (Object.prototype.hasOwnProperty.call(item,'balanceSummary')) {
                clean.balanceSummary = sanitizeBalanceSummary(item.balanceSummary);
                if (!clean.balanceSummary) return null;
            }
            if (Object.prototype.hasOwnProperty.call(item,'procurement')) {
                clean.procurement = sanitizeProcurementDemand(item.procurement, item.item);
                if (!clean.procurement) return null;
            }
            seen[item.idx] = true;
            result.push(clean);
        }
        return result;
    }

    function catalogMap(catalog) {
        var result = {};
        for (var i = 0; i < catalog.length; i++) result[catalog[i].idx] = catalog[i];
        return result;
    }

    function sanitizeCartSnapshot(value, catalog) {
        var clean = normalizeCartPayload(value, 0);
        if (!clean) return null;
        var byIndex = catalogMap(catalog), seen = {};
        for (var i = 0; i < clean.length; i++) {
            if (clean[i].idx < 0 || clean[i].qty < 1 || clean[i].qty > 999999
                    || seen[clean[i].idx] || !byIndex[clean[i].idx]) return null;
            seen[clean[i].idx] = true;
        }
        return clean;
    }

    function sanitizePurchased(value) {
        if (!Array.isArray(value) || value.length > 10000) return null;
        var result = [];
        for (var i = 0; i < value.length; i++) {
            var item = value[i];
            if (!exactKeys(item,['purchasedIdx','item','displayname','icon','quantity'])
                    || item.purchasedIdx !== i || !identityText(item.item,128)
                    || !identityText(item.displayname,256) || !identityText(item.icon,256)
                    || !isInteger(item.quantity) || item.quantity < 1) return null;
            result.push({purchasedIdx:i,item:item.item,displayname:item.displayname,
                icon:item.icon,quantity:item.quantity});
        }
        return result;
    }

    function expectedLines(catalog, cart) {
        if (!Array.isArray(catalog) || !Array.isArray(cart) || !cart.length) return null;
        var byIndex = catalogMap(catalog), seen = {}, result = [];
        for (var i = 0; i < cart.length; i++) {
            var selector = cart[i], item = byIndex[selector.idx];
            if (!item || seen[selector.idx] || selector.qty < 1 || selector.qty > 999999) return null;
            seen[selector.idx] = true;
            result.push({catalogIndex:selector.idx,itemName:item.item,displayName:item.displayname,
                icon:item.icon,quantity:selector.qty,unitPrice:item.price,
                total:item.price*selector.qty,maxQuantity:item.maxQuantity});
        }
        return result;
    }

    function sumLineTotals(lines) {
        var result = 0;
        for (var i = 0; i < lines.length; i++) result += lines[i].total;
        return result;
    }

    function sanitizeLines(value, expected, balance) {
        if (!Array.isArray(value) || !expected || value.length !== expected.length || !value.length) return null;
        var result = [];
        var fields = ['catalogIndex','itemName','displayName','icon','quantity','unitPrice','total',
            'maxQuantity','maxAffordable','maxByCapacity','maxPurchasable','itemKind'];
        for (var i = 0; i < value.length; i++) {
            var line = value[i], selector = expected[i];
            if (!exactKeys(line,fields) || !isInteger(line.catalogIndex)
                    || !identityText(line.itemName,128) || !identityText(line.displayName,256)
                    || !identityText(line.icon,256) || !isInteger(line.quantity)
                    || !isFiniteNumber(line.unitPrice) || line.unitPrice < 0
                    || !isFiniteNumber(line.total) || line.total < 0
                    || !isInteger(line.maxQuantity) || line.maxQuantity < 1 || line.maxQuantity > 999999
                    || !isInteger(line.maxAffordable) || line.maxAffordable < 0
                    || !isInteger(line.maxByCapacity) || line.maxByCapacity < 0
                    || !isInteger(line.maxPurchasable) || line.maxPurchasable < 0
                    || ['equipment','information','stack'].indexOf(line.itemKind) < 0
                    || line.catalogIndex !== selector.catalogIndex || line.itemName !== selector.itemName
                    || line.displayName !== selector.displayName || line.icon !== selector.icon
                    || line.quantity !== selector.quantity || line.unitPrice !== selector.unitPrice
                    || line.total !== selector.total || line.maxQuantity !== selector.maxQuantity
                    || line.quantity > line.maxQuantity
                    || line.maxPurchasable !== Math.min(line.maxQuantity,line.maxAffordable,line.maxByCapacity)) return null;
            result.push(cloneJson(line));
        }
        var orderTotal = sumLineTotals(result);
        for (var j = 0; j < result.length; j++) {
            var current = result[j], other = orderTotal-current.total;
            var affordable = current.unitPrice <= 0 ? current.maxQuantity
                : Math.max(0,Math.min(current.maxQuantity,Math.floor((balance-other)/current.unitPrice)));
            if (current.maxAffordable !== affordable) return null;
        }
        return result;
    }

    function consistentCommitState(lines, balance, total, canCommit, blocking) {
        var capacity = true, information = false;
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].maxByCapacity < lines[i].quantity) {
                capacity = false;
                if (lines[i].itemKind === 'information') information = true;
            }
        }
        var expected = balance < total ? 'insufficient_kpoints'
            : capacity ? '' : information ? 'destination_full' : 'inventory_full';
        return blocking === expected && canCommit === (expected === '');
    }

    var ROUTE_KEYS = {type:true,panel:true,panelInstanceId:true,cmd:true,callId:true};
    function businessPart(response) {
        if (!response || typeof response !== 'object'
                || Object.prototype.hasOwnProperty.call(response,'domain')) return null;
        var result = {}, keys = Object.keys(response);
        for (var i = 0; i < keys.length; i++) {
            if (!ROUTE_KEYS[keys[i]]) result[keys[i]] = response[keys[i]];
        }
        return result;
    }

    function sanitizeFailure(business) {
        if (!business || business.success !== false || !safeText(business.error,80,false)
                || !exactKeys(business,['success','error'],
                    ['cause','balance','purchasedToken','clientSynthetic'])) return null;
        if (Object.prototype.hasOwnProperty.call(business,'cause') && !safeText(business.cause,80,false)) return null;
        if (Object.prototype.hasOwnProperty.call(business,'balance')
                && (!isFiniteNumber(business.balance) || business.balance < 0)) return null;
        if (Object.prototype.hasOwnProperty.call(business,'purchasedToken')
                && !validToken(business.purchasedToken)) return null;
        if (Object.prototype.hasOwnProperty.call(business,'clientSynthetic')
                && business.clientSynthetic !== true) return null;
        return cloneJson(business);
    }

    function sanitizeBulkBusiness(business) {
        if (!exactKeys(business,['success','catalog','playerLevel','reverseLevel','kpoints',
                'cart','cartAdjusted','purchased','purchasedToken']) || business.success !== true
                || !isInteger(business.playerLevel) || business.playerLevel < 0
                || !isInteger(business.reverseLevel) || business.reverseLevel < 0
                || !isFiniteNumber(business.kpoints) || business.kpoints < 0
                || typeof business.cartAdjusted !== 'boolean' || !validToken(business.purchasedToken)) return null;
        var catalog = sanitizeCatalog(business.catalog);
        var cart = catalog && sanitizeCartSnapshot(business.cart,catalog);
        var purchased = sanitizePurchased(business.purchased);
        if (!catalog || !cart || !purchased) return null;
        return {success:true,catalog:catalog,playerLevel:business.playerLevel,
            reverseLevel:business.reverseLevel,kpoints:business.kpoints,cart:cart,
            cartAdjusted:business.cartAdjusted,purchased:purchased,
            purchasedToken:business.purchasedToken};
    }

    function sanitizePreviewBusiness(business, payload, authority) {
        if (!exactKeys(business,['success','v','checkoutToken','purchaseLines','total','balance',
                'projectedBalance','canCommit','blockingError']) || business.success !== true
                || business.v !== 1 || !validToken(business.checkoutToken)
                || !isFiniteNumber(business.total) || business.total < 0
                || !isFiniteNumber(business.balance) || business.balance < 0
                || !isFiniteNumber(business.projectedBalance)
                || typeof business.canCommit !== 'boolean'
                || ['','insufficient_kpoints','inventory_full','destination_full'].indexOf(business.blockingError) < 0
                || !authority || business.balance !== authority.balance
                || business.projectedBalance !== business.balance-business.total) return null;
        var expected = expectedLines(authority.catalog,payload.cart);
        var lines = sanitizeLines(business.purchaseLines,expected,business.balance);
        if (!lines || business.total !== sumLineTotals(lines)
                || !consistentCommitState(lines,business.balance,business.total,
                    business.canCommit,business.blockingError)) return null;
        return {success:true,v:1,checkoutToken:business.checkoutToken,purchaseLines:lines,
            total:business.total,balance:business.balance,projectedBalance:business.projectedBalance,
            canCommit:business.canCommit,blockingError:business.blockingError};
    }

    function purchasedEqual(left,right) {
        return JSON.stringify(left) === JSON.stringify(right);
    }

    function catalogMatchesDelivered(catalog, delivered) {
        var byIndex = catalogMap(catalog || []);
        for (var i = 0; i < delivered.length; i++) {
            var line = delivered[i], current = byIndex[line.catalogIndex];
            if (!current || current.item !== line.itemName
                    || current.displayname !== line.displayName
                    || current.icon !== line.icon
                    || current.price !== line.unitPrice) return false;
        }
        return true;
    }

    function sanitizeSavedCartBusiness(business, payload, authority) {
        if (!exactKeys(business,['success','v','cart','adjusted'])
                || business.success !== true || business.v !== 1
                || typeof business.adjusted !== 'boolean'
                || !authority || !Array.isArray(authority.catalog)) return null;
        var cart = sanitizeCartSnapshot(business.cart,authority.catalog);
        var requested = normalizeCartPayload(payload.cart,0);
        if (!cart || !requested) return null;
        var catalog = catalogMap(authority.catalog), expected = {}, positions = {};
        for (var i = 0; i < requested.length; i++) {
            if (Object.prototype.hasOwnProperty.call(expected,requested[i].idx)) return null;
            expected[requested[i].idx] = requested[i];
            positions[requested[i].idx] = i;
        }
        var previous = -1;
        for (var j = 0; j < cart.length; j++) {
            var line = cart[j], bound = expected[line.idx], current = catalog[line.idx];
            if (!bound || !current || positions[line.idx] <= previous
                    || line.qty > bound.qty || line.qty > current.maxQuantity) return null;
            previous = positions[line.idx];
        }
        var adjusted = !cartEquals(cart,requested);
        if (business.adjusted !== adjusted) return null;
        return {success:true,v:1,cart:cart,adjusted:adjusted};
    }

    function sanitizeCheckoutBusiness(business, cmd, payload, authority) {
        if (!exactKeys(business,['success','v','newBalance','delivered','cart','purchased',
                'purchasedToken','catalog']) || business.success !== true || business.v !== 1
                || !isFiniteNumber(business.newBalance) || business.newBalance < 0
                || !Array.isArray(business.cart) || business.cart.length !== 0
                || !validToken(business.purchasedToken) || !authority) return null;
        var expected = expectedLines(authority.catalog,authority.cart);
        var lines = sanitizeLines(business.delivered,expected,authority.balance);
        var purchased = sanitizePurchased(business.purchased);
        var catalog = sanitizeCatalog(business.catalog);
        if (!lines || !purchased || !catalog || !catalogMatchesDelivered(catalog,lines)
                || business.purchasedToken !== authority.purchasedToken
                || !purchasedEqual(purchased,authority.purchased)) return null;
        if (cmd === 'checkoutCommit') {
            if (!authority.preview || payload.expectedCheckoutToken !== authority.preview.checkoutToken
                    || JSON.stringify(lines) !== JSON.stringify(authority.preview.purchaseLines)
                    || business.newBalance !== authority.preview.projectedBalance) return null;
        } else if (business.newBalance !== authority.balance-sumLineTotals(lines)) return null;
        return {success:true,v:1,newBalance:business.newBalance,delivered:lines,cart:[],
            purchased:purchased,purchasedToken:business.purchasedToken,catalog:catalog};
    }

    function sanitizeClaimBusiness(business, payload, authority) {
        if (!exactKeys(business,['success','catalog','purchased','purchasedToken'])
                || business.success !== true || !authority || !validToken(business.purchasedToken)
                || business.purchasedToken === authority.purchasedToken
                || payload.expectedPurchasedToken !== authority.purchasedToken
                || payload.purchasedIdx < 0 || payload.purchasedIdx >= authority.purchased.length) return null;
        var catalog = sanitizeCatalog(business.catalog);
        var purchased = sanitizePurchased(business.purchased);
        var expected = cloneJson(authority.purchased);
        expected.splice(payload.purchasedIdx,1);
        for (var i = 0; i < expected.length; i++) expected[i].purchasedIdx = i;
        if (!catalog || !purchased || !purchasedEqual(purchased,expected)) return null;
        return {success:true,catalog:catalog,purchased:purchased,purchasedToken:business.purchasedToken};
    }

    function sanitizeResponse(cmd, payload, response, authority) {
        var business = businessPart(response);
        if (!business) return null;
        if (business.success === false) return sanitizeFailure(business);
        if (cmd === 'bulkQuery') return sanitizeBulkBusiness(business);
        if (cmd === 'saveCart') return sanitizeSavedCartBusiness(
            business,payload,authority);
        if (cmd === 'tooltip') {
            if (!exactKeys(business,['success','descHTML','introHTML','itemName','displayname','iconName'])
                    || business.success !== true || typeof business.descHTML !== 'string'
                    || typeof business.introHTML !== 'string' || !authority) return null;
            var byIndex = catalogMap(authority.catalog || []), expected = byIndex[payload.idx];
            return expected && business.itemName === expected.item
                && business.displayname === expected.displayname && business.iconName === expected.icon
                ? cloneJson(business) : null;
        }
        if (cmd === 'checkoutPreview') return sanitizePreviewBusiness(business,payload,authority);
        if (cmd === 'checkoutCommit' || cmd === 'checkout')
            return sanitizeCheckoutBusiness(business,cmd,payload,authority);
        if (cmd === 'claim') return sanitizeClaimBusiness(business,payload,authority);
        return null;
    }

    var KShopProtocol = {
        normalizeRequest:normalizeRequest,
        sanitizeResponse:sanitizeResponse,
        sanitizeCatalog:sanitizeCatalog,
        sanitizePurchased:sanitizePurchased,
        NAVIGATION_WATCHDOG_MS:NAVIGATION_WATCHDOG_MS,
        parseProcurementNavigationInit:parseProcurementNavigationInit,
        createReturnCraftingRecipeMessage:createReturnCraftingRecipeMessage,
        validateReturnCraftingRecipeFailure:validateReturnCraftingRecipeFailure,
        sanitizeBulkSnapshot:function(response) {
            return sanitizeBulkBusiness(businessPart(response) || response);
        }
    };

    function isValidBulkSnapshot(response) {
        return !!KShopProtocol.sanitizeBulkSnapshot(response);
    }

    function KShopWriteCoordinator(options) {
        options = options || {};
        this._request = options.request;
        this._getCart = options.getCart || function() { return []; };
        this._acceptSavedCart = options.acceptSavedCart || function() {};
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
                if (self._revision === entry.revision
                        && cartEquals(self._getCart(),entry.cart)) {
                    self._acceptSavedCart(cloneCart(response.cart),response.adjusted === true);
                }
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
                && Array.isArray(response.catalog)
                && typeof response.purchasedToken === 'string' && response.purchasedToken.length > 0;
            if (cmd === 'claim') return Array.isArray(response.purchased)
                && Array.isArray(response.catalog)
                && typeof response.purchasedToken === 'string' && response.purchasedToken.length > 0;
            return false;
        }
        if (response.error === 'busy') return true;
        if (cmd === 'checkoutCommit') return response.error === 'insufficient_kpoints'
            || response.error === 'inventory_full' || response.error === 'stale_state';
        // destination_full 与 inventory_full 同为容量类零写拒绝（singleAcquire 的 require
        // 预检在任何 mutate 前 return false），必须直接定论，避免白走一轮 bulkQuery 对账。
        if (cmd === 'claim') return response.error === 'inventory_full'
            || response.error === 'destination_full'
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
        KShopProtocol: KShopProtocol,
        cartEquals: cartEquals,
        isValidBulkSnapshot: isValidBulkSnapshot
    };
});
