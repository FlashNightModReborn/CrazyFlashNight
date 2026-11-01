(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.ModifierRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';

    var TOKEN = /^modifier\.[A-Za-z0-9._~-]{1,80}$/;
    var OPERATION = /^mod\.[A-Za-z0-9._~-]{1,80}$/;
    var LEVEL_ACTIONS = ['unlock_stages', 'kill_all', 'finish_wave', 'finish_map', 'finish_stage', 'test_space'];
    var WRITE_COMMANDS = ['grantMoney', 'grantKCoin', 'spawnItem', 'levelAction', 'grantTask', 'spawnUnit', 'spawnMerc'];
    var READ_COMMANDS = ['snapshot', 'items', 'units', 'query'];

    function int(value, min, max) {
        return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max;
    }
    function text(value, min, max) {
        return typeof value === 'string' && value.length >= min && value.length <= max;
    }
    function exact(value, keys) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var actual = Object.keys(value);
        if (actual.length !== keys.length) return false;
        for (var i = 0; i < keys.length; i++) if (actual.indexOf(keys[i]) < 0) return false;
        return true;
    }
    function copy(value) { return JSON.parse(JSON.stringify(value)); }

    function normalizeItem(value) {
        if (!exact(value, ['id', 'name', 'displayName', 'icon', 'type', 'use'])) return null;
        if (!int(value.id, 0, 9007199254740991) || !text(value.name, 1, 128)
            || !text(value.displayName, 1, 256) || !text(value.icon, 1, 256)
            || !text(value.type, 0, 64) || !text(value.use, 0, 64)) return null;
        return {id:value.id, name:value.name, displayName:value.displayName, icon:value.icon,
            type:value.type, use:value.use};
    }
    function normalizeUnit(value) {
        if (!exact(value, ['id', 'name', 'spriteName', 'key', 'level', 'hostile'])) return null;
        if (!int(value.id, 0, 999999) || !text(value.name, 0, 128)
            || !text(value.spriteName, 1, 256) || !text(value.key, 0, 256)
            || !int(value.level, 0, 999999) || typeof value.hostile !== 'boolean') return null;
        return {id:value.id, name:value.name, spriteName:value.spriteName, key:value.key,
            level:value.level, hostile:value.hostile};
    }
    function normalizeSnapshot(value, token) {
        if (!value || value.v !== 1 || value.operation !== 'snapshot' || value.token !== token
            || value.success !== true || !int(value.revision, 0, 9007199254740991)
            || ['editing', 'reconcile', 'closed', 'expired'].indexOf(value.phase) < 0
            || !int(value.itemCount, 0, 1000000) || !int(value.unitCount, 0, 1000000)
            || !int(value.itemPageSize, 1, 1000) || !int(value.unitPageSize, 1, 1000)) return null;
        var s = value.state;
        if (!exact(s, ['money', 'kcoin', 'maxLevel', 'inWorld', 'stageActive', 'challengeMode', 'saveAvailable'])
            || !int(s.money, 0, 9007199254740991) || !int(s.kcoin, 0, 9007199254740991)
            || !int(s.maxLevel, 0, 999999) || typeof s.inWorld !== 'boolean'
            || typeof s.challengeMode !== 'boolean' || typeof s.saveAvailable !== 'boolean'
            || ['none', 'Active', 'Finished', 'Failed'].indexOf(s.stageActive) < 0) return null;
        return copy(value);
    }
    function normalizeItems(value, token) {
        if (!value || value.v !== 1 || value.operation !== 'items' || value.token !== token
            || value.success !== true || !int(value.revision, 0, 9007199254740991)
            || !text(value.query, 0, 64) || !int(value.page, 1, 9999)
            || !int(value.pageSize, 1, 1000) || !int(value.total, 0, 1000000)
            || !Array.isArray(value.items) || value.items.length > value.pageSize) return null;
        var items = [];
        for (var i = 0; i < value.items.length; i++) {
            var item = normalizeItem(value.items[i]);
            if (!item) return null;
            items.push(item);
        }
        return {v:1, operation:'items', token:token, success:true, revision:value.revision,
            query:value.query, page:value.page, pageSize:value.pageSize, total:value.total, items:items};
    }
    function normalizeUnits(value, token) {
        if (!value || value.v !== 1 || value.operation !== 'units' || value.token !== token
            || value.success !== true || !int(value.revision, 0, 9007199254740991)
            || !text(value.query, 0, 64) || !int(value.page, 1, 9999)
            || !int(value.pageSize, 1, 1000) || !int(value.total, 0, 1000000)
            || !Array.isArray(value.units) || value.units.length > value.pageSize) return null;
        var units = [];
        for (var i = 0; i < value.units.length; i++) {
            var unit = normalizeUnit(value.units[i]);
            if (!unit) return null;
            units.push(unit);
        }
        return {v:1, operation:'units', token:token, success:true, revision:value.revision,
            query:value.query, page:value.page, pageSize:value.pageSize, total:value.total, units:units};
    }
    function normalizeWrite(value, cmd, token, operationId) {
        if (!value || value.v !== 1 || value.operation !== cmd || value.token !== token
            || typeof value.success !== 'boolean' || !int(value.revision, 0, 9007199254740991)) return null;
        if (WRITE_COMMANDS.indexOf(cmd) >= 0 && value.operationId !== operationId) return null;
        if (cmd === 'query' && value.queriedOperation !== operationId) return null;
        var result = {v:1, operation:cmd, token:token, success:value.success, revision:value.revision};
        if (value.operationId !== undefined) result.operationId = value.operationId;
        if (value.queriedOperation !== undefined) result.queriedOperation = value.queriedOperation;
        if (value.error !== undefined) {
            if (!text(value.error, 1, 128)) return null;
            result.error = value.error;
        }
        if (value.success === true && result.error) return null;
        if (value.success === false && !result.error) return null;
        if (value.message !== undefined) {
            if (!text(value.message, 0, 256)) return null;
            result.message = value.message;
        }
        if (value.requiresReconcile !== undefined) {
            if (typeof value.requiresReconcile !== 'boolean') return null;
            result.requiresReconcile = value.requiresReconcile;
        }
        if (value.closeAfter !== undefined) {
            if (typeof value.closeAfter !== 'boolean') return null;
            result.closeAfter = value.closeAfter;
        }
        var numeric = ['money', 'kcoin', 'quantity', 'taskId', 'spawned', 'failed', 'changed'];
        for (var i = 0; i < numeric.length; i++) {
            var key = numeric[i];
            if (value[key] === undefined) continue;
            if (!int(value[key], -9007199254740991, 9007199254740991)) return null;
            result[key] = value[key];
        }
        if (value.success === false && !result.requiresReconcile
            && ['timeout', 'disconnected', 'client_timeout', 'delivery_unknown', 'malformed_response',
                'apply_ambiguous', 'reconcile_required', 'not_sent'].indexOf(result.error) >= 0) {
            result.requiresReconcile = true;
        }
        return result;
    }
    function isLevelAction(value) { return LEVEL_ACTIONS.indexOf(value) >= 0; }

    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs || 12000,
            callPrefix:'modifier',
            router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(context) {
                return {type:'panel', panel:'modifier', domain:'modifier', cmd:context.entry.cmd,
                    panelInstanceId:instance, callId:context.entry.callId, payload:context.payload};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.panel === 'modifier'
                    && data.domain === 'modifier' && data.cmd === entry.cmd
                    && data.callId === entry.callId
                    && (!data.panelInstanceId || data.panelInstanceId === instance);
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', panel:'modifier', domain:'modifier',
                    cmd:context.entry.cmd, callId:context.entry.callId, success:false,
                    error:context.error, clientSynthetic:true,
                    requiresReconcile:context.entry.write === true
                        && (context.error === 'client_timeout' || context.error === 'delivery_unknown')};
            }
        });
        this._mux.openSession({});
    }
    RequestMux.prototype.request = function(cmd, payload, callback) {
        if (READ_COMMANDS.indexOf(cmd) < 0 && WRITE_COMMANDS.indexOf(cmd) < 0) return null;
        var write = WRITE_COMMANDS.indexOf(cmd) >= 0;
        return this._mux.request(cmd, payload, {
            kind:write ? 'write' : cmd,
            singleFlight:true,
            write:write,
            sendError:'not_sent'
        }, callback);
    };
    RequestMux.prototype.cancelKind = function(kind) { return this._mux.cancelKind(kind); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };

    return {
        TOKEN:TOKEN, OPERATION:OPERATION, LEVEL_ACTIONS:LEVEL_ACTIONS,
        WRITE_COMMANDS:WRITE_COMMANDS, READ_COMMANDS:READ_COMMANDS,
        int:int, text:text, exact:exact,
        normalizeItem:normalizeItem, normalizeUnit:normalizeUnit,
        normalizeSnapshot:normalizeSnapshot, normalizeItems:normalizeItems,
        normalizeUnits:normalizeUnits, normalizeWrite:normalizeWrite,
        isLevelAction:isLevelAction, RequestMux:RequestMux
    };
});
