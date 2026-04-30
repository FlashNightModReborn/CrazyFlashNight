/**
 * LazyLoader — 按需注入 <script>，promise-cached、保序、去重。
 *
 * 用法：
 *   LazyLoader.load(['a.js','b.js']).then(function(){ ... });
 *
 * 设计：
 *  - 同一个 url 重复 load 返回同一 promise（host-bridge.js 被多 panel 共用）
 *  - 给定 url 数组**保序**注入：用 script.async=false 让浏览器保证执行顺序
 *  - 失败时 reject 并清缓存，下一次调用允许重试
 *  - 不处理 CSS（CSS 在 overlay.html head 里 boot 加载，先不动）
 */
var LazyLoader = (function() {
    'use strict';

    var _cache = {}; // url → Promise<void>

    function loadOne(url) {
        if (_cache[url]) return _cache[url];
        var p = new Promise(function(resolve, reject) {
            var s = document.createElement('script');
            s.src = url;
            // async=false 让浏览器在多个动态注入的 <script> 之间保证执行顺序
            s.async = false;
            s.onload = function() { resolve(); };
            s.onerror = function() {
                delete _cache[url]; // 允许重试
                reject(new Error('[LazyLoader] failed to load: ' + url));
            };
            document.head.appendChild(s);
        });
        _cache[url] = p;
        return p;
    }

    function load(urls) {
        if (!urls || urls.length === 0) return Promise.resolve();
        return Promise.all(urls.map(loadOne));
    }

    function isLoaded(url) {
        return !!_cache[url];
    }

    return {
        load: load,
        isLoaded: isLoaded
    };
})();
