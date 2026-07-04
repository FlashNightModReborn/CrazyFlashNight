(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.ArenaCustomUndo = factory();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
    'use strict';

    function parametersApi() {
        return typeof ArenaCustomParameters !== 'undefined' ? ArenaCustomParameters : null;
    }

    function plainObject(value) {
        if (!value || typeof value !== 'object') return {};
        var out = {};
        for (var key in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) out[key] = value[key];
        }
        return out;
    }

    function cloneParameters(value) {
        var api = parametersApi();
        if (!api || !api.has(value)) return null;
        return api.clone(value);
    }

    function cloneRoster(roster) {
        var out = [];
        roster = roster || [];
        for (var i = 0; i < roster.length; i++) {
            if (!roster[i]) continue;
            var entry = {
                id: Number(roster[i].id) || 0,
                type: roster[i].type || ('兵种' + (Number(roster[i].id) || 0)),
                level: Number(roster[i].level) || 1,
                count: Number(roster[i].count) || 1
            };
            var parameters = roster[i].parameters || roster[i].Parameters || roster[i]['参数'];
            if (cloneParameters(parameters)) entry.parameters = cloneParameters(parameters);
            if (roster[i].presetId) entry.presetId = roster[i].presetId;
            if (roster[i].presetLabel) entry.presetLabel = roster[i].presetLabel;
            out.push(entry);
        }
        return out;
    }

    function snapshot(editor, options) {
        options = options || {};
        editor = editor || {};
        return {
            mode: editor.mode === 'pve' ? 'pve' : 'mvm',
            seed: editor.seed || 0,
            timeoutFrames: editor.timeoutFrames || options.defaultTimeoutFrames || 3600,
            blue: cloneRoster(editor.blue || []),
            red: cloneRoster(editor.red || []),
            query: editor.query || '',
            filter: editor.filter || 'all',
            expandedFactions: plainObject(editor.expandedFactions),
            unitVisibleRows: editor.unitVisibleRows || options.browserBatchSize || 80,
            unitScrollableRows: editor.unitScrollableRows || 0
        };
    }

    function capture(editor, state, options) {
        state = state || {};
        return {
            label: state.label || '上一步',
            editor: snapshot(editor, options),
            selectedSide: state.selectedSide === 'red' ? 'red' : 'blue',
            editorPage: state.editorPage || 'config'
        };
    }

    function restore(undo, options) {
        if (!undo) return null;
        var editor = snapshot(undo.editor, options);
        var selectedSide = undo.selectedSide === 'red' ? 'red' : 'blue';
        if (editor.mode === 'pve') selectedSide = 'red';
        return {
            label: undo.label || '上一步',
            editor: editor,
            selectedSide: selectedSide,
            editorPage: undo.editorPage === 'params' ? 'side' : (undo.editorPage || 'config')
        };
    }

    function renderButton(button, undo, options) {
        if (!button) return;
        options = options || {};
        var disabled = !undo || !!options.disabled;
        var truncate = typeof options.truncateText === 'function'
            ? options.truncateText
            : function(text) { return String(text || '').slice(0, 10); };
        button.disabled = disabled;
        button.textContent = undo ? ('撤销：' + truncate(undo.label, 10)) : '撤销';
        button.title = undo ? ('撤销 ' + undo.label) : '暂无可撤销操作';
    }

    return {
        capture: capture,
        restore: restore,
        renderButton: renderButton,
        snapshot: snapshot,
        cloneRoster: cloneRoster
    };
});
