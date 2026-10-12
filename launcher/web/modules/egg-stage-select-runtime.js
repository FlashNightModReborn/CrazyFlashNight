/* U7 彩蛋地图选关的 wire 边界；彩蛋/主线进度门与进关权威在 AS2，这里只验证并转发。 */
(function(root, factory) {
    'use strict';
    var api = factory(typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EggStageSelectRuntime = api;
})(typeof window !== 'undefined' ? window : null, function(PanelRuntime) {
    'use strict';
    var DESTINATION_IDS = ['forest_depth', 'machine_zone', 'forest_center'];
    var DIFFICULTIES = ['简单', '冒险', '修罗', '地狱'];
    var DEFINITIVE_ERRORS = ['unsupported_cmd', 'unsupported_version', 'invalid_payload', 'unknown_destination',
        'locked', 'stage_config_unavailable', 'stage_config_failed', 'pending_stage_settlement', 'enter_refused'];
    function text(value, max) { return typeof value === 'string' && value.length <= max && !/[\x00-\x1f]/.test(value); }
    function integer(value, min, max) { return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max; }
    function exact(value, keys) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var own = Object.keys(value);
        return own.length === keys.length && keys.every(function(key) { return Object.prototype.hasOwnProperty.call(value, key); });
    }
    function normalizeState(v) {
        if (!v || v.v !== 1 || v.operation !== 'snapshot' || v.success !== true) return null;
        if (!v.progress || !integer(v.progress.main, 0, Number.MAX_SAFE_INTEGER)
            || !integer(v.progress.egg, 0, Number.MAX_SAFE_INTEGER)) return null;
        if (!Array.isArray(v.destinations) || v.destinations.length !== 3) return null;
        var destinations = [], seen = {};
        for (var i = 0; i < 3; i++) {
            var destination = v.destinations[i];
            if (!destination || !exact(destination, ['id', 'name', 'stageName', 'difficulty', 'unlocked', 'hintLocked', 'lockReason'])
                || DESTINATION_IDS.indexOf(destination.id) < 0 || seen[destination.id]) return null;
            if (!text(destination.name, 64) || !text(destination.stageName, 96) || !destination.stageName
                || DIFFICULTIES.indexOf(destination.difficulty) < 0
                || typeof destination.unlocked !== 'boolean' || typeof destination.hintLocked !== 'boolean'
                || !text(destination.lockReason, 256)) return null;
            if (destination.unlocked && destination.lockReason !== '') return null;
            seen[destination.id] = true;
            destinations.push({ id: destination.id, name: destination.name, stageName: destination.stageName,
                difficulty: destination.difficulty, unlocked: destination.unlocked,
                hintLocked: destination.hintLocked, lockReason: destination.lockReason });
        }
        return { v: 1, operation: 'snapshot', success: true,
            progress: { main: v.progress.main, egg: v.progress.egg }, destinations: destinations };
    }
    function normalizeEnter(v) {
        if (!v || v.v !== 1 || v.operation !== 'enter') return null;
        if (v.success === true) {
            if (v.closePanel !== true || !text(v.stageName, 96) || !v.stageName
                || DIFFICULTIES.indexOf(v.difficulty) < 0 || DESTINATION_IDS.indexOf(v.destinationId) < 0) return null;
            return { v: 1, operation: 'enter', success: true, closePanel: true,
                destinationId: v.destinationId, stageName: v.stageName, difficulty: v.difficulty };
        }
        if (v.success === false && DEFINITIVE_ERRORS.indexOf(v.error) >= 0) {
            return { v: 1, operation: 'enter', success: false, error: v.error };
        }
        return null;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send: options.send, timeoutMs: options.timeoutMs || 12000, callPrefix: 'eggselect',
            router: options.router || PanelRuntime.sharedResponseRouter,
            createMessage: function(context) {
                return { type: 'panel', panel: 'egg-stage-select', domain: 'egg_stage_select', cmd: context.entry.cmd,
                    panelInstanceId: instance, callId: context.entry.callId, payload: context.payload };
            },
            validateResponse: function(data, entry) {
                return data && data.type === 'panel_resp' && data.panel === 'egg-stage-select'
                    && data.domain === 'egg_stage_select'
                    && data.cmd === entry.cmd && data.callId === entry.callId && data.panelInstanceId === instance;
            },
            createSynthetic: function(context) {
                return { success: false, error: context.error, clientSynthetic: true,
                    enterUnknown: context.entry.write === true && context.error === 'client_timeout' };
            }
        });
        this._mux.openSession({});
    }
    RequestMux.prototype.request = function(cmd, payload, callback) {
        if (!/^(snapshot|enter)$/.test(cmd)) return null;
        return this._mux.request(cmd, payload, { kind: cmd, singleFlight: true, write: cmd === 'enter', sendError: 'not_sent' }, callback);
    };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    return { DESTINATION_IDS: DESTINATION_IDS, normalizeState: normalizeState,
        normalizeEnter: normalizeEnter, RequestMux: RequestMux };
});
