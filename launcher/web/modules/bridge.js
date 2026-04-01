var Bridge = (function() {
    var handlers = {};
    function on(type, handler) {
        if (!handlers[type]) handlers[type] = [];
        handlers[type].push(handler);
    }
    function send(msg) {
        if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(msg);
        }
    }
    if (window.chrome && window.chrome.webview) {
        window.chrome.webview.addEventListener('message', function(event) {
            var data = event.data;
            if (data && data.type && handlers[data.type]) {
                var list = handlers[data.type];
                for (var i = 0; i < list.length; i++) {
                    try { list[i](data); } catch(e) { console.error(e); }
                }
            }
        });
    }
    return { on: on, send: send };
})();
