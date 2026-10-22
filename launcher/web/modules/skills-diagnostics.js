/** Redacted skills diagnostics and clipboard transport, independent of panel state. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsDiagnostics = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function redact(value) {
        if (Array.isArray(value)) return value.map(redact);
        if (!value || typeof value !== 'object') return value;
        var result = {};
        Object.keys(value).forEach(function(key) {
            if (/session|token/i.test(key)) return;
            result[key] = redact(value[key]);
        });
        return result;
    }

    function buildRecord(input) {
        input = input || {};
        var state = input.coordinator || {};
        var snapshot = input.snapshot || null;
        var entry = input.entry || null;
        return {
            v:1,
            area:'skills',
            reason:String(input.reason || 'unknown'),
            view:String(input.view || ''),
            panelInstanceId:String(state.panelInstanceId || ''),
            revision:snapshot ? Number(snapshot.revision) : Number(state.lastAppliedRevision),
            writeState:String(state.state || ''),
            writeEpoch:Number(state.lastAppliedWriteEpoch),
            activeWrite:state.activeWrite || null,
            activeReconcile:state.activeReconcile || null,
            pendingCount:state.mux ? Number(state.mux.pendingCount || 0) : 0,
            selectedSkill:String(entry && entry.skillKey || input.selectedKey || ''),
            entryHealth:entry ? String(entry.stateHealth || '') : '',
            trainerExpired:input.trainerExpired === true,
            schemaError:String(input.schemaError || ''),
            lastError:input.lastError || null,
            snapshotDiagnostics:redact(snapshot && Array.isArray(snapshot.diagnostics) ? snapshot.diagnostics : [])
        };
    }

    function fallbackCopyText(value, documentRef) {
        return new Promise(function(resolve, reject) {
            if (!documentRef || !documentRef.body || typeof documentRef.createElement !== 'function') {
                reject(new Error('copy_unavailable'));
                return;
            }
            var area = documentRef.createElement('textarea'); area.value = value;
            area.setAttribute('readonly', 'readonly'); area.style.position = 'fixed'; area.style.left = '-9999px';
            documentRef.body.appendChild(area); area.select();
            var copied = false;
            try { copied = documentRef.execCommand('copy'); } catch (error) { copied = false; }
            documentRef.body.removeChild(area);
            if (copied) resolve(); else reject(new Error('copy_failed'));
        });
    }

    function copyText(value, options) {
        options = options || {};
        if (typeof options.copyText === 'function') {
            try { return Promise.resolve(options.copyText(value)); }
            catch (error) { return Promise.reject(error); }
        }
        var navigatorRef = options.navigator;
        if (navigatorRef && navigatorRef.clipboard && navigatorRef.clipboard.writeText) {
            return navigatorRef.clipboard.writeText(value).catch(function() {
                return fallbackCopyText(value, options.document);
            });
        }
        return fallbackCopyText(value, options.document);
    }

    /** Bounded, best-effort response observations; never a write acknowledgement. */
    function createResponseTrace(options) {
        options = options || {};
        var owner = '', generation = 0, frames = [];
        var commands = /^(snapshot|learnPreview|learnCommit|equip|unequip|moveSlot|setPassive|reorder)$/;
        function clock() {
            try { return Number(options.now()); } catch (error) { return 0; }
        }
        function valid(response) {
            return !!(owner && response && response.type === 'panel_resp' && response.panel === 'skills'
                && response.domain === 'skills' && response.panelInstanceId === owner
                && typeof response.callId === 'string' && typeof response.cmd === 'string'
                && /^[A-Za-z0-9._-]{1,96}$/.test(response.callId || '') && commands.test(response.cmd || '')
                && typeof response.writeEpoch === 'number' && isFinite(response.writeEpoch)
                && response.writeEpoch >= 0 && response.writeEpoch <= 2147483647 && response.writeEpoch % 1 === 0);
        }
        function send(response, stage, elapsed) {
            if (!valid(response) || typeof options.send !== 'function') return;
            elapsed = Math.max(0, Math.min(600000, Number(elapsed) || 0));
            try {
                options.send({type:'skill_response_diag', panel:'skills', panelInstanceId:owner,
                    callId:response.callId, cmd:response.cmd, writeEpoch:response.writeEpoch,
                    stage:stage, durationMs:elapsed});
            } catch (error) {} // A diagnostic failure cannot interrupt presentation or replay a write.
        }
        function cancel(frame) {
            try { if (typeof options.cancelFrame === 'function') options.cancelFrame(frame.handle); } catch (error) {}
        }
        function close() {
            generation++; owner = '';
            frames.forEach(cancel); frames = [];
        }
        return {
            open:function(instance) { close(); owner = String(instance || ''); },
            close:close,
            received:function(response) { send(response, 'web_received', 0); },
            refresh:function(response, render) {
                // Keep only correlation metadata alive until RAF, never the full snapshot.
                response = valid(response) ? {type:'panel_resp',panel:'skills',domain:'skills',
                    panelInstanceId:response.panelInstanceId,callId:response.callId,
                    cmd:response.cmd,writeEpoch:response.writeEpoch} : null;
                var started = clock(), capturedGeneration = generation;
                send(response, 'dom_refresh_begin', 0);
                try { render(); }
                catch (error) { send(response, 'dom_refresh_failed', clock() - started); throw error; }
                send(response, 'dom_refresh_end', clock() - started);
                if (!valid(response) || typeof options.requestFrame !== 'function') return;
                if (frames.length >= 8) cancel(frames.shift());
                var frame = {handle:null}; frames.push(frame);
                try {
                    frame.handle = options.requestFrame(function() {
                        var index = frames.indexOf(frame);
                        if (index < 0 || capturedGeneration !== generation) return;
                        frames.splice(index, 1);
                        // RAF callback execution is not proof of pixels being presented.
                        send(response, 'frame_callback', clock() - started);
                    });
                } catch (error) {
                    var index = frames.indexOf(frame); if (index >= 0) frames.splice(index, 1);
                }
            }
        };
    }

    return {redact:redact, buildRecord:buildRecord, copyText:copyText, createResponseTrace:createResponseTrace};
});
