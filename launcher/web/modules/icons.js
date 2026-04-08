/**
 * Icons — 物品图标 manifest 加载与 URL 解析
 *
 * manifest.json 结构: {"物品名": {"f1": "hash_1.png", "f2": "hash_2.png"}, ...}
 * 仅使用 f1（第一帧缩略图）
 */
var Icons = (function() {
    'use strict';

    var _map = null, _loading = false, _queue = [];

    return {
        load: function(cb) {
            if (_map) { cb(); return; }
            _queue.push(cb);
            if (_loading) return;
            _loading = true;
            fetch('icons/manifest.json')
                .then(function(r) { return r.json(); })
                .then(function(d) { _map = d; for (var i = 0; i < _queue.length; i++) _queue[i](); _queue = []; })
                .catch(function() { _map = {}; for (var i = 0; i < _queue.length; i++) _queue[i](); _queue = []; });
        },
        resolve: function(name) {
            if (!_map || !_map[name] || !_map[name].f1) return null;
            return 'icons/' + _map[name].f1;
        }
    };
})();
