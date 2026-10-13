/**
 * composition-intelligence.js — 情报档案组合页（只读消费者）的胶水层
 *
 * 职责：
 *   1. 记录 Host panel_cmd:open(intelligence) 下发的 initData.panelInstanceId，
 *      供出站 close 补全精确实例身份（intelligence-panel.js 的 doClose 缺省无 instanceId）。
 *      本脚本在 panels.js 之前加载，因此本 handler 先于 Panels 的 panel_cmd 分发执行。
 *   2. 过滤 Bridge.send 出站：只放行
 *        { type:'composition_intelligence_ready' }
 *        { type:'panel', panel:'intelligence', cmd:'close', panelInstanceId:<记录的实例> }
 *          ——reason 仅透传 navigate_character_build（返回装备），其余 reason 剥除；
 *        { type:'panel', panel:'intelligence', cmd:<只读查询>, callId:<string> }
 *          ——白名单：bundle/catalog/snapshot/state/tooltip/glossary_catalog/glossary_snapshot；
 *        { type:'panel-toast', html:<string ≤4096> }
 *      其余（task / viewportMetrics / gpuInfo / 诊断 / 其他面板命令）全部丢弃。
 *   3. Bridge.task 整体禁用：字体包下载（font_pack download_group）是写业务，
 *      本页不加载 font-pack-banner.js，条幅结构性缺席，Bridge.task 兜底拒绝。
 *   4. window load 后先 Panels.init()，再发 composition_intelligence_ready——
 *      init 未完成不发，Host 不会在 ready 之前授予 open。
 *
 * 不做的事：
 *   - 不监听 keydown；ESC 由 Host 侧 surface accelerator / panel_esc 链路处理。
 *   - 不模拟输入、不调 CDP、不拦导航（外链拦截归 Host / compositionController）。
 *   - 不实现任何写业务；本页没有 finishTask/abandon/navigateFinish 一类命令可放行。
 */
(function() {
    'use strict';

    if (typeof Bridge === 'undefined' || !Bridge) return;

    var PANEL = 'intelligence';
    var _panelInstanceId = '';
    var READ_ONLY_COMMANDS = {
        bundle: true, catalog: true, snapshot: true, state: true,
        tooltip: true, glossary_catalog: true, glossary_snapshot: true
    };

    // 先于 Panels 的 panel_cmd handler 执行（本脚本先加载、先 Bridge.on）。
    Bridge.on('panel_cmd', function(data) {
        if (!data || data.panel !== PANEL) return;
        if (data.cmd === 'open' && data.initData
                && typeof data.initData.panelInstanceId === 'string') {
            _panelInstanceId = data.initData.panelInstanceId;
        } else if (data.cmd === 'close' || data.cmd === 'force_close') {
            _panelInstanceId = '';
        }
    });

    // Bridge.task captures its original send function; disable that separate RPC entry.
    Bridge.task = function() { return false; };
    var _origSend = Bridge.send;
    Bridge.send = function(msg) {
        if (!msg || !msg.type) return true;
        if (msg.type === 'composition_intelligence_ready') {
            return _origSend.call(Bridge, msg);
        }
        if (msg.type === 'panel' && msg.panel === PANEL && msg.cmd === 'close') {
            var out = { type:'panel', cmd:'close', panel:PANEL };
            var instance = typeof msg.panelInstanceId === 'string' && msg.panelInstanceId
                ? msg.panelInstanceId : _panelInstanceId;
            if (!instance || instance !== _panelInstanceId) return false;
            out.panelInstanceId = instance;
            if (msg.reason === 'navigate_character_build') out.reason = msg.reason;
            return _origSend.call(Bridge, out);
        }
        if (msg.type === 'panel' && msg.panel === PANEL
                && READ_ONLY_COMMANDS[msg.cmd] === true
                && typeof msg.callId === 'string' && msg.callId.length > 0
                && msg.callId.length <= 160) {
            return _origSend.call(Bridge, msg);
        }
        if (msg.type === 'panel-toast'
                && typeof msg.html === 'string' && msg.html.length <= 4096) {
            return _origSend.call(Bridge, msg);
        }
        // 丢所有诊断 / task / viewportMetrics / gpuInfo / 其他面板命令。
        // 返回 true：面板层不需要为被丢弃的消息保留重试状态。
        return true;
    };

    window.addEventListener('load', function() {
        Panels.init();
        Bridge.send({ type: 'composition_intelligence_ready' });
    });
})();
