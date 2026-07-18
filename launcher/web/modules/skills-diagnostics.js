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

    return {redact:redact, buildRecord:buildRecord, copyText:copyText};
});
