/* U7 地铁线路选关的 wire 边界；门槛与进关权威在 AS2，这里只验证并转发。 */
(function(root, factory) {
    'use strict';
    var api = factory(typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SubwaySelectRuntime = api;
})(typeof window !== 'undefined' ? window : null, function(PanelRuntime) {
    'use strict';
    var ENTRY_IDS = ['clean_stationA', 'raid_stationB', 'defend_stationC', 'explore_stationD'];
    var STATION_IDS = ['总备处站', '新市场站', '自由广场站', '环线东北站'];
    var DIFFICULTIES = ['简单', '冒险', '修罗', '地狱'];
    var DEFINITIVE_ERRORS = ['unsupported_cmd', 'unsupported_version', 'invalid_payload', 'unknown_entry',
        'not_enterable', 'locked', 'stage_config_unavailable', 'stage_config_failed',
        'pending_stage_settlement', 'enter_refused'];
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
        if (!Array.isArray(v.stations) || v.stations.length !== 4) return null;
        var stations = [], i;
        for (i = 0; i < 4; i++) {
            var station = v.stations[i];
            if (!station || !exact(station, ['id', 'name', 'frame']) || STATION_IDS.indexOf(station.id) < 0
                || station.name !== station.id || !integer(station.frame, 1, 4)) return null;
            stations.push({ id: station.id, name: station.name, frame: station.frame, locked: station.frame === 1 });
        }
        if (!Array.isArray(v.entries) || v.entries.length > 4) return null;
        var entries = [], seen = {};
        for (i = 0; i < v.entries.length; i++) {
            var entry = v.entries[i];
            if (!entry || !exact(entry, ['id', 'name', 'description', 'stageName', 'difficulty', 'enterable', 'highlighted'])
                || ENTRY_IDS.indexOf(entry.id) < 0 || seen[entry.id]) return null;
            if (!text(entry.name, 64) || !text(entry.description, 512)
                || typeof entry.enterable !== 'boolean' || typeof entry.highlighted !== 'boolean') return null;
            if (entry.enterable) {
                if (!text(entry.stageName, 96) || !entry.stageName || DIFFICULTIES.indexOf(entry.difficulty) < 0) return null;
            } else if (entry.stageName !== '' || entry.difficulty !== '') return null;
            seen[entry.id] = true;
            entries.push({ id: entry.id, name: entry.name, description: entry.description,
                stageName: entry.stageName, difficulty: entry.difficulty,
                enterable: entry.enterable, highlighted: entry.highlighted });
        }
        return { v: 1, operation: 'snapshot', success: true,
            progress: { main: v.progress.main, egg: v.progress.egg },
            stations: stations, entries: entries };
    }
    function normalizeEnter(v) {
        if (!v || v.v !== 1 || v.operation !== 'enter') return null;
        if (v.success === true) {
            if (v.closePanel !== true || !text(v.stageName, 96) || !v.stageName
                || DIFFICULTIES.indexOf(v.difficulty) < 0 || ENTRY_IDS.indexOf(v.entryId) < 0) return null;
            return { v: 1, operation: 'enter', success: true, closePanel: true,
                entryId: v.entryId, stageName: v.stageName, difficulty: v.difficulty };
        }
        if (v.success === false && DEFINITIVE_ERRORS.indexOf(v.error) >= 0) {
            return { v: 1, operation: 'enter', success: false, error: v.error };
        }
        return null;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send: options.send, timeoutMs: options.timeoutMs || 12000, callPrefix: 'subway',
            router: options.router || PanelRuntime.sharedResponseRouter,
            createMessage: function(context) {
                return { type: 'panel', panel: 'subway', domain: 'subway', cmd: context.entry.cmd,
                    panelInstanceId: instance, callId: context.entry.callId, payload: context.payload };
            },
            validateResponse: function(data, entry) {
                return data && data.type === 'panel_resp' && data.panel === 'subway' && data.domain === 'subway'
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
    return { ENTRY_IDS: ENTRY_IDS, STATION_IDS: STATION_IDS, normalizeState: normalizeState,
        normalizeEnter: normalizeEnter, RequestMux: RequestMux };
});
