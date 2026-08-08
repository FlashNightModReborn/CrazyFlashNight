/**
 * LazyLoader — 按需注入 <script>，promise-cached、保序、去重。
 *
 * 用法：
 *   LazyLoader.load(['a.js','b.js']).then(function(){ ... });
 *
 * 设计：
 *  - 同一个 url 重复 load 返回同一 promise（host-bridge.js 被多 panel 共用）
 *  - 给定 url 数组**串行保序**注入：前一项 onload 后才创建下一项 script
 *  - 失败时 reject 并清失败项缓存；后续项尚未注入，下一次调用可从失败项继续
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
        // 不能用 Promise.all 一次插入整组 script：中间项网络失败时，后置 facade
        // 仍可能执行、因依赖缺失抛错，却被 load 事件记入缓存；重试只补中间项，
        // facade 不再执行，lazy panel 会永久停在 lazy_register_missing。
        // 串行链既兑现依赖顺序，也保证失败之后的脚本在本轮完全没有被注入。
        return urls.reduce(function(chain, url) {
            return chain.then(function() { return loadOne(url); });
        }, Promise.resolve());
    }

    function isLoaded(url) {
        return !!_cache[url];
    }

    return {
        load: load,
        isLoaded: isLoaded
    };
})();
