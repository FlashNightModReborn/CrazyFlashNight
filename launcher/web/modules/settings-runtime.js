/** 设置面板的纯协议、36 键校验和草稿比较。 */
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

    var COMMAND = /^(snapshot|preview|apply|cancel|save|reconcile|cheat|return_base|try_revive|host_set|hit_number_ledger)$/;
    var CONTROL_CHARACTERS = /[\u0000-\u001f\u007f-\u009f]/;
    var PERFORMANCE_HEIGHTS = [0,360,540,720,900,1080,1440,2160];
    var KEY_IDS = [
        '上键','下键','左键','右键','A键','B键','C键','键1','键2','键3','键4','键5',
        '药剂组切换键',
        '快捷物品栏键1','快捷物品栏键2','快捷物品栏键3','快捷物品栏键4',
        '快捷技能栏键1','快捷技能栏键2','快捷技能栏键3','快捷技能栏键4',
        '快捷技能栏键5','快捷技能栏键6','快捷技能栏键7','快捷技能栏键8',
        '快捷技能栏键9','快捷技能栏键10','快捷技能栏键11','快捷技能栏键12',
        '切换武器键','互动键','武器技能键','飞行键','武器变形键','奔跑键','组合键'
    ];

    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function validOpaque(value) { return typeof value==='string' && value.length>0 && value.length<=160 && !/[^A-Za-z0-9._~-]/.test(value); }
    function requiresAuthorityReconcile(cmd) {
        return cmd !== 'snapshot' && cmd !== 'preview' && cmd !== 'reconcile' && cmd !== 'hit_number_ledger';
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

    function exactProperties(value, names) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var keys = Object.keys(value);
        return keys.length === names.length && names.every(function(name) {
            return Object.prototype.hasOwnProperty.call(value, name);
        });
    }
    function normalizePerformanceConfig(value) {
        if (!exactProperties(value, ['preset','mode','maxRenderHeight'])
            || ['balanced','performance','quality'].indexOf(value.preset) < 0
            || ['auto','fixed'].indexOf(value.mode) < 0
            || PERFORMANCE_HEIGHTS.indexOf(value.maxRenderHeight) < 0) return null;
        return {preset:value.preset, mode:value.mode, maxRenderHeight:value.maxRenderHeight};
    }
    function normalizePerformanceState(value) {
        if (!exactProperties(value, ['v','current','previous']) || value.v !== 1) return null;
        var current = normalizePerformanceConfig(value.current);
        var previous = value.previous === null ? null : normalizePerformanceConfig(value.previous);
        if (!current || (value.previous !== null && !previous)) return null;
        return {v:1, current:current, previous:previous};
    }
    function hasPerformanceChanges(state, draft) {
        return !!(state && draft && (state.current.preset !== draft.preset
            || state.current.mode !== draft.mode
            || state.current.maxRenderHeight !== draft.maxRenderHeight));
    }
    function recommendedPerformanceConfig(draft) {
        var value = normalizePerformanceConfig(draft);
        if (value) value.mode = 'auto';
        return value;
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
                if (data.v === 2) {
                    var authority = parseAuthority(data);
                    if (authority) {
                        var flat = data.snapshot ? copy(data.snapshot) : {};
                        Object.keys(data).forEach(function(key) { flat[key] = data[key]; });
                        if (authority.state) { flat.revision=authority.state.revision;flat.migrationPending=authority.state.migrationPending; }
                        flat.applied=authority.outcome.applied;flat.durable=authority.outcome.durable;
                        flat.error=data.error || authority.outcome.error;flat.authorityFacts=authority;
                        return flat;
                    }
                    return {type:'panel_resp',panel:'settings',domain:'settings',cmd:entry.cmd,callId:entry.callId,
                        panelInstanceId:entry.session.panelInstanceId,success:false,error:'malformed_response',
                        requiresReconcile:requiresAuthorityReconcile(entry.cmd),clientSynthetic:true};
                }
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

    function parseAuthority(response) {
        if (!response || response.v!==2 || !validOpaque(response.contextId) || !validOpaque(response.saveOwnerId)
            || !validOpaque(response.authorityEpoch) || typeof response.success!=='boolean' || typeof response.requiresReconcile!=='boolean'
            || ['allowed','blocked_by_operation','blocked_by_metadata','blocked_by_context'].indexOf(response.writeAdmission)<0
            || !Array.isArray(response.warnings) || !response.outcome) return null;
        var state=response.state, out=response.outcome;
        if (['none','not_applied','applied','unknown'].indexOf(out.applyState)<0 || typeof out.durable!=='boolean'
            || ['none','not_sent','in_flight','returned_unconfirmed','confirmed','unknown'].indexOf(out.attemptState)<0
            || ['none','flush_true','cold_read_exact','cold_read_current'].indexOf(out.confirmation)<0
            || ['none','applied','not_applied','unresolved'].indexOf(out.resolution)<0
            || (out.error!==null && typeof out.error!=='string')) return null;
        if (out.applyState==='applied' ? out.applied!==true : out.applyState==='not_applied' ? out.applied!==false : out.applied!==null) return null;
        if (out.applyState==='none') {
            if (out.operationToken!==null || out.targetStateToken!==null || out.saveAttemptId!==null || out.sourceAuthorityEpoch!==null
                || out.originMutationRequestDigest!==null || out.durable || out.attemptState!=='none' || out.confirmation!=='none') return null;
        } else if (!validOpaque(out.operationToken) || !validOpaque(out.targetStateToken) || !validOpaque(out.saveAttemptId)
            || !validOpaque(out.sourceAuthorityEpoch) || !/^[0-9a-f]{64}$/.test(out.originMutationRequestDigest || '')) return null;
        if (out.durable ? (out.applyState!=='applied' || ['confirmed','not_sent'].indexOf(out.attemptState)<0 || out.confirmation==='none')
            : (out.attemptState==='confirmed' || out.confirmation!=='none')) return null;
        if (out.applyState==='unknown' && (out.durable || out.resolution!=='unresolved')
            || out.applyState==='not_applied' && (out.resolution!=='not_applied' || ['none','not_sent'].indexOf(out.attemptState)<0)
            || out.applyState==='applied' && out.resolution!=='applied') return null;
        if (state!==null && (!state || !integer(state.revision,0,9007199254740991) || !validOpaque(state.stateToken)
            || typeof state.durable!=='boolean' || typeof state.needsSaveRetry!=='boolean' || typeof state.migrationPending!=='boolean'
            || ['confirmed','unconfirmed','unknown'].indexOf(state.persistenceState)<0
            || ['none','flush_true','cold_read_exact','cold_read_current'].indexOf(state.confirmation)<0
            || state.durable!==(state.persistenceState==='confirmed') || state.durable===(state.confirmation==='none'))) return null;
        if (state===null && (response.snapshot!==null || response.warnings.indexOf('current_authority_unavailable')<0)) return null;
        if (state && ((response.requiresReconcile || response.writeAdmission!=='allowed') && state.needsSaveRetry
            || out.applyState!=='none' && state.stateToken===out.targetStateToken && state.durable!==out.durable)) return null;
        return {contextId:response.contextId,saveOwnerId:response.saveOwnerId,authorityEpoch:response.authorityEpoch,
            state:copy(state),outcome:copy(out),requiresReconcile:response.requiresReconcile,
            writeAdmission:response.writeAdmission,warnings:copy(response.warnings),operation:response.operation || response.cmd};
    }
    function reduceAuthority(previous, response) {
        var next=response && (response.authorityFacts || parseAuthority(response));
        if (!next) {
            if (previous && response && response.requiresReconcile===true) {
                next=copy(previous);next.requiresReconcile=true;next.writeAdmission='blocked_by_operation';
                if(next.state)next.state.needsSaveRetry=false;return next;
            }
            return previous;
        }
        next=copy(next);
        var same=previous && previous.contextId===next.contextId && previous.saveOwnerId===next.saveOwnerId
            && previous.authorityEpoch===next.authorityEpoch;
        if (same) {
            if (previous.state && next.state && (next.state.revision<previous.state.revision
                || next.state.stateToken===previous.state.stateToken && previous.state.durable && !next.state.durable)) next.state=copy(previous.state);
            if (previous.outcome.durable && previous.outcome.operationToken===next.outcome.operationToken && !next.outcome.durable)
                next.outcome=copy(previous.outcome);
            if (next.operation!=='reconcile' && previous.requiresReconcile)next.requiresReconcile=true;
        }
        if(next.requiresReconcile && next.state)next.state.needsSaveRetry=false;
        return next;
    }
    function persistenceView(authority) {
        if (!authority) return {text:'设置已同步；此版本未提供保存确认。',canApply:true,canSave:false,canReconcile:false};
        var state=authority.state, allowed=authority.writeAdmission==='allowed' && !authority.requiresReconcile;
        var confirmed=state && state.durable===true;
        var retry=state && state.needsSaveRetry===true && allowed;
        var exactKnown=confirmed && authority.outcome.durable && authority.outcome.targetStateToken===state.stateToken;
        var text=authority.requiresReconcile && !exactKnown ? '上次操作结果尚未核对；请先核对状态。'
            : confirmed ? (allowed ? '当前设置已保存。' : '设置已保存；状态通知尚未完成。')
            : retry ? '设置已生效，保存尚未确认；可只重试保存。'
            : !allowed ? '当前保存入口已锁定；可查看并核对状态。' : '当前设置尚未取得保存确认。';
        return {text:text,canApply:!!(allowed && state && !state.needsSaveRetry),canSave:!!retry,
            canReconcile:authority.requiresReconcile || !allowed};
    }
    function normalizeSnapshot(response) {
        if (response && response.v===2 && response.snapshot && parseAuthority(response)) {
            var projected=copy(response.snapshot);projected.v=1;projected.success=true;
            projected.revision=response.state.revision;projected.migrationPending=response.state.migrationPending;
            projected.hostPrefs=response.hostPrefs;response=projected;
        }
        if (!response || response.success !== true || response.v !== 1
            || response.keySchemaVersion !== 2
            || !integer(response.revision, 0, 9007199254740991)
            || !response.settings || typeof response.settings !== 'object'
            || !Array.isArray(response.keys) || response.keys.length !== KEY_IDS.length
            || !Array.isArray(response.defaultKeys) || response.defaultKeys.length !== KEY_IDS.length
            || !Array.isArray(response.allowedKeyCodes)
            || !response.hostPrefs || typeof response.hostPrefs !== 'object'
            || typeof response.keyMigrationNotice !== 'string'
            || response.keyMigrationNotice.length > 160
            || CONTROL_CHARACTERS.test(response.keyMigrationNotice)) return null;
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
        var hostPrefs = copy(response.hostPrefs);
        hostPrefs.imageEnhancementAvailable = typeof hostPrefs.casEnabled === 'boolean'
            && typeof hostPrefs.motionFeedbackEnabled === 'boolean';
        hostPrefs.casEnabled = typeof hostPrefs.casEnabled === 'boolean' ? hostPrefs.casEnabled : true;
        hostPrefs.motionFeedbackEnabled = hostPrefs.motionFeedbackEnabled === true;
        hostPrefs.performance = normalizePerformanceState(response.hostPrefs.performance);
        return {revision:response.revision, settings:settings, keys:keys,
            defaultKeys:copy(response.defaultKeys), allowedKeyCodes:copy(response.allowedKeyCodes),
            hostPrefs:hostPrefs, challengeMode:response.challengeMode === true,
            modeLabel:String(response.modeLabel || '未知'),
            cheatHelp:Array.isArray(response.cheatHelp) ? copy(response.cheatHelp) : [],
            forceControls:response.forceControls && typeof response.forceControls === 'object'
                ? copy(response.forceControls) : {}, previewActive:response.previewActive === true,
            migrationPending:response.migrationPending === true,
            keyMigrationNotice:response.keyMigrationNotice};
    }

    function gameDraft(snapshot) {
        return {settings:copy(snapshot.settings), keys:copy(snapshot.keys)};
    }
    function applyPayload(snapshot, draft) {
        return {v:1, keySchemaVersion:2,
            expectedRevision:snapshot.revision, settings:copy(draft.settings),
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
        parseAuthority:parseAuthority,reduceAuthority:reduceAuthority,persistenceView:persistenceView,
        validateKeyDraft:validateKeyDraft, validateKeyCandidate:validateKeyCandidate,
        normalizeSnapshot:normalizeSnapshot, normalizeFlashPreview:normalizeFlashPreview,
        normalizePerformanceConfig:normalizePerformanceConfig,
        normalizePerformanceState:normalizePerformanceState,
        hasPerformanceChanges:hasPerformanceChanges,
        recommendedPerformanceConfig:recommendedPerformanceConfig,
        PERFORMANCE_HEIGHTS:PERFORMANCE_HEIGHTS.slice(),
        selectCheatHelpMarkdown:selectCheatHelpMarkdown,
        gameDraft:gameDraft, applyPayload:applyPayload, hasGameChanges:hasGameChanges,
        keyLabel:keyLabel, copy:copy};
});
