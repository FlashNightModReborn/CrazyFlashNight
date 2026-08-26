/** 设置面板的纯协议、35 键校验和草稿比较。 */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SettingsRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var COMMAND = /^(snapshot|preview|apply|cancel|save|cheat|return_base|try_revive|host_set|hit_number_ledger)$/;
    var KEY_IDS = [
        '上键','下键','左键','右键','A键','B键','C键','键1','键2','键3','键4','键5',
        '快捷物品栏键1','快捷物品栏键2','快捷物品栏键3','快捷物品栏键4',
        '快捷技能栏键1','快捷技能栏键2','快捷技能栏键3','快捷技能栏键4',
        '快捷技能栏键5','快捷技能栏键6','快捷技能栏键7','快捷技能栏键8',
        '快捷技能栏键9','快捷技能栏键10','快捷技能栏键11','快捷技能栏键12',
        '切换武器键','互动键','武器技能键','飞行键','武器变形键','奔跑键','组合键'
    ];

    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function validOpaque(value) { return /^[A-Za-z0-9._~-]{1,160}$/.test(String(value || '')); }
    function requiresAuthorityReconcile(cmd) {
        return cmd !== 'snapshot' && cmd !== 'preview' && cmd !== 'hit_number_ledger';
    }
    function integer(value, min, max) {
        return typeof value === 'number' && isFinite(value) && Math.floor(value) === value
            && value >= min && value <= max;
    }
    function isReserved(code) { return code === 27 || (code >= 112 && code <= 123); }
    function usableLabel(value, fallback) {
        var label = typeof value === 'string' ? value.trim() : '';
        if (!label || label.toLowerCase() === 'undefined' || label.toLowerCase() === 'null')
            return String(fallback || '');
        return label;
    }

    function normalizeFlashPreview(value) {
        var width = value && value.width;
        var height = value && value.height;
        var aspectError = integer(width, 1, 4096) && integer(height, 1, 2304)
            ? Math.abs(width * 9 - height * 16) : Infinity;
        if (!value || typeof value !== 'object' || value.v !== 1
            || value.source !== 'entry_flash_snapshot'
            || aspectError > 16
            || typeof value.dataUrl !== 'string' || value.dataUrl.length > 8388608
            || !/^data:image\/(?:jpeg|png);base64,[A-Za-z0-9+/=]+$/.test(value.dataUrl)) return null;
        return {v:1, source:value.source, width:width, height:height,
            dataUrl:value.dataUrl};
    }

    function selectCheatHelpMarkdown(text, challengeMode) {
        text = String(text || '');
        if (!challengeMode) return text;
        var startMarker = '<!-- challenge-help:start -->';
        var endMarker = '<!-- challenge-help:end -->';
        var start = text.indexOf(startMarker);
        var end = text.indexOf(endMarker);
        if (start < 0 || end <= start) return '';
        return text.substring(start + startMarker.length, end).trim();
    }

    function RequestMux(options) {
        options = options || {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:Number(options.timeoutMs) >= 100 ? Number(options.timeoutMs) : 12000,
            sessionNonce:String(options.sessionNonce || '').replace(/[^A-Za-z0-9._~-]/g, '').slice(0, 48) || undefined,
            callPrefix:'settings',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) { return validOpaque(session.panelInstanceId); },
            createMessage:function(context) {
                var payload = PanelRuntime.copyOwn(context.payload);
                payload.v = 1;
                return {type:'panel', panel:'settings', domain:'settings', cmd:context.entry.cmd,
                    callId:context.entry.callId, panelInstanceId:context.session.panelInstanceId,
                    payload:payload};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.domain === 'settings'
                    && data.cmd === entry.cmd && data.callId === entry.callId
                    && data.panelInstanceId === entry.session.panelInstanceId;
            },
            transformResponse:function(data, entry) {
                if (typeof data.success === 'boolean') return data;
                return {type:'panel_resp', panel:'settings', domain:'settings', cmd:entry.cmd,
                    callId:entry.callId, panelInstanceId:entry.session.panelInstanceId,
                    success:false, error:'malformed_response', clientSynthetic:true};
            },
            createSynthetic:function(context) {
                var response = {type:'panel_resp', panel:'settings', domain:'settings',
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    success:false, error:context.error, clientSynthetic:true};
                if (context.error === 'client_timeout'
                    && requiresAuthorityReconcile(context.entry.cmd)) {
                    response.requiresReconcile = true;
                }
                return response;
            }
        });
    }
    RequestMux.prototype.openSession = function(panelInstanceId) {
        return this._mux.openSession({panelInstanceId:String(panelInstanceId || '')});
    };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, options, callback) {
        cmd = String(cmd || '');
        if (!COMMAND.test(cmd)) return null;
        options = options || {};
        return this._mux.request(cmd, payload || {}, {
            kind:options.kind || cmd,
            latestWins:options.latestWins === true,
            singleFlight:options.singleFlight !== false,
            write:requiresAuthorityReconcile(cmd),
            sendError:'not_sent'
        }, callback);
    };
    RequestMux.prototype.handleResponse = function(data) { return this._mux.handleResponse(data); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() { return this._mux.debugState(); };

    function validateKeyDraft(rows, allowedCodes) {
        if (!Array.isArray(rows) || rows.length !== KEY_IDS.length)
            return {valid:false, error:'invalid_count', indexes:[]};
        var allowed = null;
        if (Array.isArray(allowedCodes)) {
            allowed = {};
            for (var a = 0; a < allowedCodes.length; a++) {
                var item = allowedCodes[a];
                var code = item && typeof item === 'object' ? item.code : item;
                if (integer(code, 0, 255)) allowed[code] = true;
            }
        }
        var seen = {}, invalid = [], reserved = [], conflicts = [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            if (!row || row.id !== KEY_IDS[i] || !integer(row.keyCode, 0, 255)) {
                invalid.push(i); continue;
            }
            if (isReserved(row.keyCode) || (allowed && allowed[row.keyCode] !== true))
                reserved.push(i);
            if (seen[row.keyCode] !== undefined) {
                conflicts.push(seen[row.keyCode]); conflicts.push(i);
            }
            seen[row.keyCode] = i;
        }
        var error = invalid.length ? 'invalid_binding'
            : reserved.length ? 'reserved_key' : conflicts.length ? 'key_conflict' : '';
        var affected = invalid.concat(reserved, conflicts).filter(function(value, index, all) {
            return all.indexOf(value) === index;
        }).sort(function(a, b) { return a - b; });
        if (error) return {valid:false, error:error, indexes:affected};
        return {valid:true, error:'', indexes:[]};
    }

    function validateKeyCandidate(rows, index, code, allowedCodes) {
        if (!Array.isArray(rows) || rows.length !== KEY_IDS.length
            || !integer(index, 0, KEY_IDS.length - 1) || !integer(code, 0, 255))
            return {valid:false, error:'invalid_binding', indexes:integer(index, 0, KEY_IDS.length - 1) ? [index] : []};
        var allowed = null;
        if (Array.isArray(allowedCodes)) {
            allowed = {};
            for (var a = 0; a < allowedCodes.length; a++) {
                var item = allowedCodes[a];
                var candidateCode = item && typeof item === 'object' ? item.code : item;
                if (integer(candidateCode, 0, 255)) allowed[candidateCode] = true;
            }
        }
        if (isReserved(code) || (allowed && allowed[code] !== true))
            return {valid:false, error:'reserved_key', indexes:[index]};
        for (var i = 0; i < rows.length; i++) {
            if (i !== index && rows[i] && integer(rows[i].keyCode, 0, 255)
                && rows[i].keyCode === code)
                return {valid:false, error:'key_conflict', indexes:[i,index].sort(function(a,b){return a-b;})};
        }
        return {valid:true, error:'', indexes:[]};
    }

    function normalizeSnapshot(response) {
        if (!response || response.success !== true || response.v !== 1
            || !integer(response.revision, 0, 2147483647)
            || !response.settings || typeof response.settings !== 'object'
            || !Array.isArray(response.keys) || response.keys.length !== KEY_IDS.length
            || !Array.isArray(response.defaultKeys) || response.defaultKeys.length !== KEY_IDS.length
            || !Array.isArray(response.allowedKeyCodes)
            || !response.hostPrefs || typeof response.hostPrefs !== 'object') return null;
        var keys = [];
        for (var i = 0; i < KEY_IDS.length; i++) {
            var row = response.keys[i];
            if (!row || row.id !== KEY_IDS[i] || !integer(row.keyCode, 0, 255)) return null;
            keys.push({id:row.id, label:usableLabel(row.label, row.id), keyCode:row.keyCode,
                keyName:String(row.keyName || row.keyCode)});
            var defaultRow = response.defaultKeys[i];
            if (!defaultRow || defaultRow.id !== KEY_IDS[i]
                || !integer(defaultRow.keyCode, 0, 255)) return null;
        }
        for (var a = 0; a < response.allowedKeyCodes.length; a++) {
            var allowedRow = response.allowedKeyCodes[a];
            if (!allowedRow || !integer(allowedRow.code, 0, 255)
                || typeof allowedRow.name !== 'string') return null;
        }
        var settings = copy(response.settings);
        settings['性能等级上限'] = Number(settings['性能等级上限']) <= 0 ? 0 : 1;
        return {revision:response.revision, settings:settings, keys:keys,
            defaultKeys:copy(response.defaultKeys), allowedKeyCodes:copy(response.allowedKeyCodes),
            hostPrefs:copy(response.hostPrefs), challengeMode:response.challengeMode === true,
            modeLabel:String(response.modeLabel || '未知'),
            cheatHelp:Array.isArray(response.cheatHelp) ? copy(response.cheatHelp) : [],
            forceControls:response.forceControls && typeof response.forceControls === 'object'
                ? copy(response.forceControls) : {}, previewActive:response.previewActive === true,
            migrationPending:response.migrationPending === true};
    }

    function gameDraft(snapshot) {
        return {settings:copy(snapshot.settings), keys:copy(snapshot.keys)};
    }
    function applyPayload(snapshot, draft) {
        return {v:1, expectedRevision:snapshot.revision, settings:copy(draft.settings),
            keys:draft.keys.map(function(row) { return {id:row.id, keyCode:row.keyCode}; })};
    }
    function hasGameChanges(snapshot, draft) {
        return JSON.stringify(snapshot.settings) !== JSON.stringify(draft.settings)
            || JSON.stringify(snapshot.keys.map(function(row) { return [row.id,row.keyCode]; }))
                !== JSON.stringify(draft.keys.map(function(row) { return [row.id,row.keyCode]; }));
    }
    function keyLabel(code, allowedCodes) {
        for (var i = 0; i < (allowedCodes || []).length; i++)
            if (Number(allowedCodes[i].code) === Number(code)) return String(allowedCodes[i].name || code);
        return String(code);
    }

    return {RequestMux:RequestMux, KEY_IDS:KEY_IDS.slice(), isReservedKey:isReserved,
        validateKeyDraft:validateKeyDraft, validateKeyCandidate:validateKeyCandidate,
        normalizeSnapshot:normalizeSnapshot, normalizeFlashPreview:normalizeFlashPreview,
        selectCheatHelpMarkdown:selectCheatHelpMarkdown,
        gameDraft:gameDraft, applyPayload:applyPayload, hasGameChanges:hasGameChanges,
        keyLabel:keyLabel, copy:copy};
});
