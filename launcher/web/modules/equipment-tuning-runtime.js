/** Equipment tuning request/session primitives backed by shared PanelRuntime. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var TOKEN = /^[A-Za-z0-9._-]{1,160}$/;
    var COMMAND = /^(snapshot|preview|commit|tooltip|detach)$/;
    var OPERATION = /^(enhance|convert|install_tier|install_mod|replace_mod|detach_mod|detach_all_mods)$/;
    var own = Object.prototype.hasOwnProperty;

    function safeToken(value) {
        value = String(value || '');
        return TOKEN.test(value) ? value : '';
    }

    function isObject(value) {
        return !!value && Object.prototype.toString.call(value) === '[object Object]';
    }

    function hasExactKeys(value, required, optional) {
        if (!isObject(value)) return false;
        var allowed = Object.create(null);
        var index;
        for (index = 0; index < required.length; index++) {
            allowed[required[index]] = true;
            if (!own.call(value, required[index])) return false;
        }
        optional = optional || [];
        for (index = 0; index < optional.length; index++) allowed[optional[index]] = true;
        var keys = Object.keys(value);
        for (index = 0; index < keys.length; index++) {
            if (!allowed[keys[index]]) return false;
        }
        return true;
    }

    function identityText(value, maximum) {
        if (typeof value !== 'string' || !value.length || value.length > maximum
                || /[\u0000-\u001f\u007f]/.test(value)) return false;
        var trimmed = value.replace(/^[\s\u00a0]+|[\s\u00a0]+$/g, '');
        return !!trimmed && trimmed.toLowerCase() !== 'undefined';
    }

    function text(value, maximum, allowEmpty) {
        return typeof value === 'string' && value.length <= maximum
            && (allowEmpty || value.length > 0);
    }

    function integer(value, minimum, maximum) {
        return typeof value === 'number' && isFinite(value)
            && Math.floor(value) === value && value >= minimum && value <= maximum;
    }

    function finiteNumber(value, minimum, maximum) {
        return typeof value === 'number' && isFinite(value)
            && value >= minimum && value <= maximum;
    }

    function deepEqual(left, right) {
        if (left === right) return true;
        if (left instanceof Array || right instanceof Array) {
            if (!(left instanceof Array) || !(right instanceof Array)
                    || left.length !== right.length) return false;
            for (var arrayIndex = 0; arrayIndex < left.length; arrayIndex++) {
                if (!deepEqual(left[arrayIndex], right[arrayIndex])) return false;
            }
            return true;
        }
        if (!isObject(left) || !isObject(right)) return false;
        var leftKeys = Object.keys(left).sort();
        var rightKeys = Object.keys(right).sort();
        if (leftKeys.length !== rightKeys.length) return false;
        for (var keyIndex = 0; keyIndex < leftKeys.length; keyIndex++) {
            if (leftKeys[keyIndex] !== rightKeys[keyIndex]
                    || !deepEqual(left[leftKeys[keyIndex]], right[rightKeys[keyIndex]])) return false;
        }
        return true;
    }

    function sourceRef(value) {
        if (!isObject(value) || typeof value.sourceKind !== 'string') return false;
        if (value.sourceKind === 'inventory') {
            return hasExactKeys(value,
                ['sourceKind', 'containerId', 'slot', 'expectedLease'])
                && value.containerId === '背包'
                && integer(value.slot, 0, 49)
                && !!safeToken(value.expectedLease);
        }
        if (value.sourceKind === 'loadout') {
            return hasExactKeys(value,
                ['sourceKind', 'sessionGeneration', 'slotKey', 'expectedLoadoutRevision'])
                && integer(value.sessionGeneration, 0, 2147483647)
                && identityText(value.slotKey, 128)
                && integer(value.expectedLoadoutRevision, 0, 2147483647);
        }
        return false;
    }

    function identityArray(value, maximum) {
        if (!(value instanceof Array) || value.length > maximum) return false;
        var seen = Object.create(null);
        for (var index = 0; index < value.length; index++) {
            if (!identityText(value[index], 256) || seen[value[index]]) return false;
            seen[value[index]] = true;
        }
        return true;
    }

    function tokenArray(value, maximum) {
        if (!(value instanceof Array) || value.length > maximum) return false;
        var seen = Object.create(null);
        for (var index = 0; index < value.length; index++) {
            var normalized = safeToken(value[index]);
            if (!normalized || seen[normalized]) return false;
            seen[normalized] = true;
        }
        return true;
    }

    function statRows(value) {
        if (!(value instanceof Array) || value.length > 64) return false;
        var seen = Object.create(null);
        for (var index = 0; index < value.length; index++) {
            var row = value[index];
            if (!hasExactKeys(row, ['key', 'label', 'value'])) return false;
            if (!identityText(row.key, 64) || seen[row.key]) return false;
            seen[row.key] = true;
            if (!identityText(row.label, 128)) return false;
            if (!finiteNumber(row.value, -1e9, 1e9)) return false;
        }
        return true;
    }

    function equipment(value) {
        if (!hasExactKeys(value,
                ['name', 'displayName', 'icon', 'type', 'use', 'level', 'tier',
                    'mods', 'lastUpdate', 'maxLevel', 'hardMaxLevel'],
                ['modSlotCapacity', 'stats'])) return false;
        if (!identityText(value.name, 256)
                || !identityText(value.displayName, 256)
                || !identityText(value.icon, 256)
                || (value.type !== '武器' && value.type !== '防具')
                || !identityText(value.use, 128)
                || (value.tier !== '' && !identityText(value.tier, 128))
                || !integer(value.level, 1, 2147483647)
                || !integer(value.maxLevel, 1, 2147483647)
                || !integer(value.hardMaxLevel, 1, 2147483647)
                || value.maxLevel > value.hardMaxLevel
                || value.level > value.hardMaxLevel
                || !finiteNumber(value.lastUpdate, 0, 9007199254740991)
                || !identityArray(value.mods, 64)) return false;
        if (own.call(value, 'modSlotCapacity')
                && !integer(value.modSlotCapacity, 0, 64)) return false;
        return !own.call(value, 'stats') || statRows(value.stats);
    }

    function enhanceProjection(value, current) {
        return hasExactKeys(value,
            ['currentLevel', 'maxLevel', 'availableMaxLevel', 'hardMaxLevel'])
            && integer(value.currentLevel, 1, 2147483647)
            && integer(value.maxLevel, 1, 2147483647)
            && integer(value.availableMaxLevel, 1, 2147483647)
            && integer(value.hardMaxLevel, 1, 2147483647)
            && value.currentLevel === current.level
            && value.maxLevel === current.maxLevel
            && value.availableMaxLevel === value.maxLevel
            && value.hardMaxLevel === current.hardMaxLevel;
    }

    function candidate(value, isMod) {
        var required = isMod
            ? ['candidateKey', 'itemName', 'displayName', 'icon', 'owned',
                'installed', 'available', 'availabilityCode', 'reason',
                'replaceableFrom', 'grade', 'scope', 'role']
            : ['candidateKey', 'itemName', 'displayName', 'icon', 'tierName',
                'owned', 'available', 'reason'];
        var optional = isMod
            ? ['gradeLabel', 'gradeColor', 'scopeLabel', 'roleLabel', 'symbol'] : [];
        if (!hasExactKeys(value, required, optional)
                || !safeToken(value.candidateKey)
                || !identityText(value.itemName, 256)
                || !identityText(value.displayName, 256)
                || !identityText(value.icon, 256)
                || !integer(value.owned, 0, 2147483647)
                || typeof value.available !== 'boolean'
                || !text(value.reason, 256, true)) return false;
        if (!isMod) return identityText(value.tierName, 64);
        if (typeof value.installed !== 'boolean'
                || !integer(value.availabilityCode, -100, 100)
                || !tokenArray(value.replaceableFrom, 512)
                || !identityText(value.grade, 64)
                || !identityText(value.scope, 64)
                || !identityText(value.role, 64)) return false;
        for (var index = 0; index < optional.length; index++) {
            if (own.call(value, optional[index])
                    && !identityText(value[optional[index]], 128)) return false;
        }
        return true;
    }

    function candidateArray(value, isMod) {
        if (!(value instanceof Array) || value.length > 512) return false;
        var keys = Object.create(null);
        for (var index = 0; index < value.length; index++) {
            if (!candidate(value[index], isMod) || keys[value[index].candidateKey]) return false;
            keys[value[index].candidateKey] = true;
        }
        return true;
    }

    function snapshotMaterials(value) {
        if (!(value instanceof Array) || value.length > 512) return false;
        var names = Object.create(null);
        for (var index = 0; index < value.length; index++) {
            var row = value[index];
            if (!hasExactKeys(row, ['itemName', 'displayName', 'icon', 'count'])
                    || !identityText(row.itemName, 256)
                    || !identityText(row.displayName, 256)
                    || !identityText(row.icon, 256)
                    || names[row.itemName]
                    || !integer(row.count, 0, 2147483647)) return false;
            names[row.itemName] = true;
        }
        return true;
    }

    function snapshot(value) {
        if (!hasExactKeys(value,
                ['gender', 'source', 'equipment', 'enhance', 'tierCandidates',
                    'modCandidates', 'materials', 'materialRevision', 'inventoryRevision'])
                || (value.gender !== '男' && value.gender !== '女')
                || !sourceRef(value.source)
                || !equipment(value.equipment)
                || !enhanceProjection(value.enhance, value.equipment)
                || !candidateArray(value.tierCandidates, false)
                || !candidateArray(value.modCandidates, true)
                || !snapshotMaterials(value.materials)
                || !integer(value.materialRevision, 0, 2147483647)
                || !integer(value.inventoryRevision, 0, 2147483647)) return false;
        var installed = Object.create(null);
        for (var index = 0; index < value.modCandidates.length; index++) {
            if (value.modCandidates[index].installed) {
                installed[value.modCandidates[index].itemName] = true;
            }
        }
        if (Object.keys(installed).length !== value.equipment.mods.length) return false;
        for (index = 0; index < value.equipment.mods.length; index++) {
            if (!installed[value.equipment.mods[index]]) return false;
        }
        return true;
    }

    function materialPlan(value) {
        if (!(value instanceof Array) || value.length > 512) return false;
        var names = Object.create(null);
        for (var index = 0; index < value.length; index++) {
            var row = value[index];
            if (!hasExactKeys(row,
                    ['itemName', 'displayName', 'icon', 'before', 'delta', 'after'])
                    || !identityText(row.itemName, 256)
                    || !identityText(row.displayName, 256)
                    || !identityText(row.icon, 256)
                    || names[row.itemName]
                    || !integer(row.before, 0, 2147483647)
                    || !integer(row.delta, -2147483648, 2147483647)
                    || row.delta === 0
                    || !integer(row.after, 0, 2147483647)
                    || row.before + row.delta !== row.after) return false;
            names[row.itemName] = true;
        }
        return true;
    }

    function snapshotMaterialsMatchPlan(snapshotRows, planRows) {
        var snapshotByName = Object.create(null);
        for (var snapshotIndex = 0; snapshotIndex < snapshotRows.length; snapshotIndex++) {
            snapshotByName[snapshotRows[snapshotIndex].itemName] =
                snapshotRows[snapshotIndex];
        }
        for (var planIndex = 0; planIndex < planRows.length; planIndex++) {
            var plan = planRows[planIndex];
            var current = snapshotByName[plan.itemName];
            if (!current
                    || current.displayName !== plan.displayName
                    || current.icon !== plan.icon
                    || current.count !== plan.after) return false;
        }
        return true;
    }

    function subject(value) {
        return hasExactKeys(value, ['source', 'equipment'])
            && sourceRef(value.source) && equipment(value.equipment);
    }

    function projection(value, expectTarget) {
        return hasExactKeys(value, expectTarget ? ['source', 'target'] : ['source'])
            && subject(value.source) && (!expectTarget || subject(value.target));
    }

    function inventorySnapshotIdentities(value) {
        if (!(value instanceof Array)) return false;
        for (var snapshotIndex = 0; snapshotIndex < value.length; snapshotIndex++) {
            var current = value[snapshotIndex];
            if (!isObject(current) || !(current.slots instanceof Array)) return false;
            for (var slotIndex = 0; slotIndex < current.slots.length; slotIndex++) {
                var slot = current.slots[slotIndex];
                if (!isObject(slot) || slot.occupied !== true) continue;
                var item = slot.item;
                var confirm = slot.confirmProjection;
                if (!isObject(item)
                        || !identityText(item.name, 256)
                        || !identityText(item.displayName, 256)
                        || !identityText(item.icon, 256)
                        || own.call(item, 'displayname')
                        || own.call(item, 'iconName')) return false;
                if (confirm != null && (!isObject(confirm)
                        || !identityText(confirm.name, 256)
                        || !identityText(confirm.displayName, 256)
                        || own.call(confirm, 'displayname'))) return false;
            }
        }
        return true;
    }

    function validateTuningProjectionResponse(data, isCommit) {
        var operation = data.operation;
        var expectTarget = operation === 'convert';
        return OPERATION.test(String(operation || ''))
            && !!safeToken(data.tuningToken)
            && typeof data.noOp === 'boolean'
            && data.canCommit === !isCommit
            && projection(data.before, expectTarget)
            && projection(data.after, expectTarget)
            && materialPlan(data.materials)
            && identityArray(data.removedMods, 64);
    }

    function validateSuccessResponse(data, cmd, payload) {
        if (!data || data.success !== true) return false;
        payload = payload || {};
        if (cmd === 'snapshot') return snapshot(data.snapshot)
            && (!sourceRef(payload.source) || deepEqual(data.snapshot.source, payload.source));
        if (cmd === 'preview') return validateTuningProjectionResponse(data, false)
            && data.operation === payload.operation;
        if (cmd === 'commit') {
            if (!validateTuningProjectionResponse(data, true)
                    || !safeToken(data.transactionId)
                    || !snapshot(data.snapshot)
                    || !deepEqual(
                        data.snapshot.source,
                        data.after.source.source)
                    || !deepEqual(
                        data.snapshot.equipment,
                        data.after.source.equipment)
                    || !snapshotMaterialsMatchPlan(
                        data.snapshot.materials, data.materials)
                    || !inventorySnapshotIdentities(data.inventorySnapshots)) return false;
            var sourceKind = data.after.source.source.sourceKind;
            return data.tuningToken === payload.expectedTuningToken
                && (sourceKind === 'loadout'
                ? (data.operation === 'convert' && data.noOp !== true
                    ? data.inventorySnapshots.length === 1
                    : data.inventorySnapshots.length === 0)
                : data.inventorySnapshots.length === 1);
        }
        if (cmd === 'tooltip') {
            return !!safeToken(data.candidateKey)
                && data.candidateKey === payload.candidateKey
                && text(data.introHTML, 262144, true)
                && text(data.descHTML, 262144, true)
                && text(data.itemType, 256, true)
                && text(data.itemUse, 256, true)
                && identityText(data.text, 256)
                && (!own.call(data, 'statsBefore') || statRows(data.statsBefore))
                && (!own.call(data, 'statsAfter') || statRows(data.statsAfter))
                && own.call(data, 'statsBefore') === own.call(data, 'statsAfter');
        }
        return cmd === 'detach';
    }

    function validateFailureResponse(data) {
        return !!data && data.success === false
            && identityText(data.error, 64)
            && (!own.call(data, 'requiresReconcile')
                || typeof data.requiresReconcile === 'boolean')
            && (!own.call(data, 'transactionId')
                || !!safeToken(data.transactionId));
    }

    function RequestMux(options) {
        options = options || {};
        var diagnostic = typeof options.diagnostic === 'function'
            ? options.diagnostic : function() {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            callPrefix:'tune',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!safeToken(session.panelInstanceId) && !!safeToken(session.viewSessionId);
            },
            createMessage:function(context) {
                var payload = PanelRuntime.copyOwn(context.payload);
                payload.v = 1;
                payload.viewSessionId = context.session.viewSessionId;
                return {type:'panel', panel:'workbench', domain:'equipment_tuning',
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId, payload:payload};
            },
            validateResponse:function(data, entry, session) {
                var mismatches = [];
                if (!data || data.type !== 'panel_resp') mismatches.push('type');
                if (!data || data.domain !== 'equipment_tuning') mismatches.push('domain');
                if (!data || data.callId !== entry.callId) mismatches.push('callId');
                if (!data || data.cmd !== entry.cmd) mismatches.push('cmd');
                if (!data || data.panelInstanceId !== session.panelInstanceId) {
                    mismatches.push('panelInstanceId');
                }
                if (!data || data.viewSessionId !== session.viewSessionId) {
                    mismatches.push('viewSessionId');
                }
                if (!mismatches.length && !(data.success === true
                        ? validateSuccessResponse(data, entry.cmd,
                            entry.metadata && entry.metadata.payload)
                        : validateFailureResponse(data))) {
                    mismatches.push('businessShape');
                }
                if (mismatches.length) {
                    diagnostic({event:'response_tuple_mismatch', cmd:entry.cmd,
                        webCallId:entry.callId,
                        panelInstanceId:session.panelInstanceId,
                        viewSessionId:session.viewSessionId,
                        mismatchFields:mismatches});
                    return false;
                }
                return true;
            },
            createSynthetic:function(context) {
                var commitUnknown = context.entry.cmd === 'commit' && context.error === 'client_timeout';
                return {type:'panel_resp', panel:'workbench', domain:'equipment_tuning',
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    viewSessionId:context.session.viewSessionId,
                    success:false, error:context.error, requiresReconcile:commitUnknown,
                    clientSynthetic:true};
            }
        });
    }

    RequestMux.prototype.openSession = function(panelInstanceId, viewSessionId) {
        return this._mux.openSession({
            panelInstanceId:safeToken(panelInstanceId),
            viewSessionId:safeToken(viewSessionId)
        });
    };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, callback, hooks) {
        cmd = String(cmd || '');
        if (!COMMAND.test(cmd)) return null;
        hooks = hooks || {};
        return this._mux.request(cmd, payload, {
            write:cmd === 'commit',
            sendError:'not_sent',
            metadata:{payload:PanelRuntime.copyOwn(payload)},
            onIssued:typeof hooks.onIssued === 'function' ? hooks.onIssued : null
        }, callback);
    };
    RequestMux.prototype.handleResponse = function(data) { return this._mux.handleResponse(data); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {active:state.active, generation:state.generation, sequence:state.sequence,
            panelInstanceId:state.session.panelInstanceId || '',
            viewSessionId:state.session.viewSessionId || '', pendingCount:state.pendingCount,
            pendingKinds:state.pendingKinds instanceof Array ? state.pendingKinds.slice() : []};
    };

    function isAmbiguous(response) {
        var error = response && response.error;
        // A disconnected preflight is definitive when Host explicitly says that the
        // command never entered its write watermark. Do not manufacture a barrier for
        // a callId that AS2 never observed.
        if (error === 'disconnected') return !!(response && response.requiresReconcile === true);
        return !!(response && response.requiresReconcile)
            || error === 'timeout' || error === 'client_timeout'
            || error === 'malformed_response' || error === 'reconcile_required';
    }

    return {RequestMux:RequestMux, isAmbiguous:isAmbiguous, safeToken:safeToken,
        validateSuccessResponse:validateSuccessResponse,
        identityText:identityText};
});
