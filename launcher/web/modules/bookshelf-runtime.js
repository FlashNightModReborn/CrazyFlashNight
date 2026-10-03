(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.BookshelfRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    var books = [
        {id:'dust', title:'尘都诡谈', subtitle:'原稿 · 十五页', pages:15},
        {id:'babylon', title:'光明巴比伦', subtitle:'原稿 · 十五页', pages:15},
        {id:'repair-campus', title:'修理大学', subtitle:'传奇经历 · 可玩小型副本', pages:0}
    ];
    function pageUrl(id, page) {
        var book = books.find(function(b) { return b.id === id; });
        return book && Number.isInteger(page) && page >= 1 && page <= book.pages
            ? 'assets/bookshelf/' + id + '/' + String(page).padStart(2, '0') + '.svg' : null;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId;
        this.mux = new PanelRuntime.PanelRequestMux({
            send:options.send, timeoutMs:options.timeoutMs || 18000, callPrefix:'bookshelf',
            router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(c) { return {type:'panel', panel:'bookshelf', domain:'bookshelf', cmd:c.entry.cmd,
                callId:c.entry.callId, panelInstanceId:instance, payload:c.payload}; },
            validateResponse:function(d, e) { return d && d.type === 'panel_resp' && d.panel === 'bookshelf'
                && d.domain === 'bookshelf' && d.cmd === e.cmd && d.callId === e.callId && d.panelInstanceId === instance; },
            createSynthetic:function(c) { return {success:false, error:c.error, clientSynthetic:true,
                requiresReconcile:c.entry.write && c.error === 'client_timeout'}; }
        });
        this.mux.openSession({});
    }
    RequestMux.prototype.request = function(cmd, payload, done) {
        if (!/^(snapshot|commit|query)$/.test(cmd)) return null;
        return this.mux.request(cmd, payload, {kind:cmd, singleFlight:true, write:cmd === 'commit', sendError:'not_sent'}, done);
    };
    RequestMux.prototype.destroy = function() { this.mux.destroy(); };
    return {books:books, pageUrl:pageUrl, RequestMux:RequestMux};
});
