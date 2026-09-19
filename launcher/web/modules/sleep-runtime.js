/* 睡眠面板的草稿数学与严格响应边界；不拥有游戏时钟。 */
(function(root, factory) {
    'use strict';
    var api = factory(typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SleepRuntime = api;
})(typeof window !== 'undefined' ? window : null, function(PanelRuntime) {
    'use strict';
    function minute(value) { return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value < 1440; }
    function wrap(value) { return ((value % 1440) + 1440) % 1440; }
    function format(value) { return String(Math.floor(wrap(value) / 60)).padStart(2, '0') + ':' + String(wrap(value) % 60).padStart(2, '0'); }
    function angles(value) { return {hour:(value % 720) / 2, minute:(value % 60) * 6}; }
    function angleDelta(previous, next) { return ((next - previous + 540) % 360) - 180; }
    function smooth(a, b, value) { var t = Math.max(0, Math.min(1, (value - a) / (b - a))); return t * t * (3 - 2 * t); }
    // 仅用于目标时刻的美术预览，不预测天气、光照等级或奖励倍率。
    function visualPhase(value) {
        var time = wrap(value), day = smooth(270, 390, time) * (1 - smooth(1020, 1170, time));
        return phaseAtDay(day);
    }
    function phaseAtDay(day) {
        return {day:day, twilight:4 * day * (1 - day), sun:smooth(.52, .82, day), moon:1 - smooth(.18, .48, day)};
    }
    // 颜色追随独立于闹钟吸附；限制追随速度，改向沿用当前画面，后台恢复也不补跳一大步。
    function followMood(current, target, elapsed, duration) {
        var delta = target - current, dt = Math.max(0, Math.min(50, elapsed));
        if (Math.abs(delta) < .0001) return target;
        var distance = Math.min(Math.abs(delta) * (1 - Math.exp(-8 * dt / duration)), 2 * dt / duration);
        return current + Math.sign(delta) * distance;
    }
    function mix(a, b, weight) { return a.map(function(v, i) { return Math.round(v + (b[i] - v) * weight); }); }
    function moodColor(night, twilight, day, weight) {
        return weight < .5 ? mix(night,twilight,smooth(0,.5,weight)) : mix(twilight,day,smooth(.5,1,weight));
    }
    function luminance(rgb) {
        return rgb.map(function(v) { v /= 255; return v <= .04045 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); })
            .reduce(function(total, v, i) { return total + v * [.2126,.7152,.0722][i]; }, 0);
    }
    function contrast(a, b) { var x=luminance(a), y=luminance(b); return (Math.max(x,y)+.05)/(Math.min(x,y)+.05); }
    function readable(backgrounds, dark, light, minimum) {
        minimum = minimum || 4.5;
        function score(color) { return Math.min.apply(null, backgrounds.map(function(bg) { return contrast(color, bg); })); }
        var useDark = score(dark) >= score(light), ink = useDark ? dark : light, edge = useDark ? [0,0,0] : [255,255,255];
        for (var i = 0; i <= 20; i++) { var candidate = mix(ink, edge, i / 20); if (score(candidate) >= minimum) return candidate; }
        return score([0,0,0]) >= score([255,255,255]) ? [0,0,0] : [255,255,255];
    }
    // 拖动按连续角差累计；跨 12 点不会跳回另一小时，分针带动时针。
    function dragPreview(start, hand, delta) { return wrap(start + (hand === 'hour' ? delta * 2 : delta / 6)); }
    function dragMinutes(start, hand, delta, fine) {
        var step = hand === 'hour' ? 60 : (fine ? 1 : 5);
        var units = hand === 'hour' ? delta * 2 : delta / 6;
        return wrap(hand === 'hour' ? start + Math.round(units / step) * step : Math.round((start + units) / step) * step);
    }
    function normalizeState(value) {
        if (!value || value.v !== 1 || !/^sleep\.[A-Za-z0-9._~-]{1,122}$/.test(value.token || '')
                || !/^(snapshot|commit|query)$/.test(value.operation || '')
                || !minute(value.currentMinutes) || !minute(value.targetMinutes)
                || ['success','changed','cycleEnabled','cyclePaused','canSleep'].some(function(key) { return typeof value[key] !== 'boolean'; })
                || typeof value.reason !== 'string') return null;
        var valid = value.phase === 'editing' && value.operation !== 'commit' && value.success && !value.changed
            && value.canSleep === value.cycleEnabled && value.reason === (value.canSleep ? '' : 'cycle_disabled');
        valid = valid || value.phase === 'applied' && value.success && value.changed && !value.canSleep
            && value.currentMinutes === value.targetMinutes && value.reason === '';
        valid = valid || value.phase === 'expired' && !value.success && !value.changed && !value.canSleep && value.reason === 'context_changed';
        return valid ? JSON.parse(JSON.stringify(value)) : null;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send, timeoutMs:options.timeoutMs || 12000, callPrefix:'sleep',
            router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(context) {
                return {type:'panel', panel:'sleep', domain:'sleep', cmd:context.entry.cmd,
                    panelInstanceId:instance, callId:context.entry.callId, payload:context.payload};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.panel === 'sleep' && data.domain === 'sleep'
                    && data.cmd === entry.cmd && data.callId === entry.callId && data.panelInstanceId === instance;
            },
            createSynthetic:function(context) {
                return {success:false, error:context.error, clientSynthetic:true,
                    requiresReconcile:context.entry.write === true && context.error === 'client_timeout'};
            }
        });
        this._mux.openSession({});
    }
    RequestMux.prototype.request = function(cmd, payload, callback) {
        return this._mux.request(cmd, payload, {kind:cmd, singleFlight:true, write:cmd === 'commit', sendError:'not_sent'}, function(response) {
            if (response && response.phase && (response.token !== payload.token || response.operation !== cmd
                    || cmd === 'commit' && response.phase === 'applied' && response.targetMinutes !== payload.targetMinutes)) {
                callback({success:false, error:'malformed_response', requiresReconcile:cmd === 'commit'});
            } else callback(response);
        });
    };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    return {minute:minute, wrap:wrap, format:format, angles:angles, angleDelta:angleDelta, dragMinutes:dragMinutes, dragPreview:dragPreview,
        visualPhase:visualPhase, phaseAtDay:phaseAtDay, followMood:followMood, mix:mix, moodColor:moodColor, contrast:contrast, readable:readable,
        normalizeState:normalizeState, RequestMux:RequestMux};
});
