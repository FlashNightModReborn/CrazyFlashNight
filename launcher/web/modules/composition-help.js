/**
 * composition-help.js — 只读 Help 试点页（composition-help.html）的胶水层
 *
 * 职责：
 *   1. 记录 Host panel_cmd:open(help) 下发的 initData.panelInstanceId，
 *      供出站 close 补全精确实例身份（help-panel.js 自带的 close 缺省无 instanceId）。
 *      本脚本在 panels.js 之前加载，因此本 handler 先于 Panels 的 panel_cmd 分发执行。
 *   2. 过滤 Bridge.send 出站：只放行
 *        { type:'composition_help_ready' }
 *        { type:'panel', cmd:'close', panel:'help', panelInstanceId:<记录的实例> }
 *      其余（task / viewportMetrics / gpuInfo / 诊断等）全部丢弃。
 *   3. window load 后先 Panels.init()，再发 composition_help_ready——init 未完成不发，
 *      Host 不会在 ready 之前授予 open。
 *
 * 不做的事：
 *   - 不监听 keydown；ESC 由 Host KeyUp → panel_esc → Panels.onRequestClose 链路处理，
 *     页面不重复 close。
 *   - 不模拟输入、不调 CDP、不拦导航（外链拦截归 Host / compositionController）。
 *   - Panels.init 的 required-assets 门走 Icons 缺失分支：Icons 未加载时
 *     ensureRequiredAssets 记录 error 并立即 finishRequiredAssets，open 不被门阻塞。
 */
(function() {
    'use strict';

    if (typeof Bridge === 'undefined' || !Bridge) return;

    var _helpInstanceId = '';

    // 先于 Panels 的 panel_cmd handler 执行（本脚本先加载、先 Bridge.on）。
    Bridge.on('panel_cmd', function(data) {
        if (!data || data.panel !== 'help') return;
        if (data.cmd === 'open' && data.initData
                && typeof data.initData.panelInstanceId === 'string') {
            _helpInstanceId = data.initData.panelInstanceId;
        } else if (data.cmd === 'close' || data.cmd === 'force_close') {
            _helpInstanceId = '';
        }
    });

    // Bridge.task captures its original send function; disable that separate RPC entry.
    Bridge.task = function() { return false; };
    var _origSend = Bridge.send;
    Bridge.send = function(msg) {
        if (!msg || !msg.type) return true;
        if (msg.type === 'composition_help_ready') {
            return _origSend.call(Bridge, msg);
        }
        if (msg.type === 'panel' && msg.cmd === 'close' && msg.panel === 'help') {
            var out = { type:'panel', cmd:'close', panel:'help' };
            if (!_helpInstanceId) return false;
            out.panelInstanceId = _helpInstanceId;
            return _origSend.call(Bridge, out);
        }
        // 丢所有诊断 / task / viewportMetrics / gpuInfo / 其他 panel 命令。
        // 返回 true：面板层不需要为被丢弃的消息保留重试状态。
        return true;
    };

    window.addEventListener('load', function() {
        Panels.init();
        Bridge.send({ type: 'composition_help_ready' });
    });
})();
