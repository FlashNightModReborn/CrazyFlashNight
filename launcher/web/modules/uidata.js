/**
 * UiData — 帧同步 UI 状态分发器
 *
 * 数据流: AS2 watch → FrameBroadcaster \x03 段 → C# 透传 → JS
 * 格式: "key:value|key:value|..."  紧凑 KV 对
 *
 * Key 映射:
 *   g = gold (金钱)
 *   k = kpoint (虚拟币/K点)
 *   p = paused (暂停状态, 0/1)
 *   q = quest (主线任务进度)
 *
 * 注册: UiData.on('g', function(newValue, oldValue){ ... })
 * 对比: 仅在值变化时触发 handler，JS 端维护 last known state
 *
 * 也保留旧的 type|field1|field2 格式兼容（U 前缀独立推送仍可工作）
 */
var UiData = (function() {
    'use strict';

    var handlers = {};
    var legacyHandlers = {};  // 旧格式: type → [handler(fields)]
    var lastState = {};  // key → last known value string

    function on(key, handler) {
        if (!handlers[key]) handlers[key] = [];
        handlers[key].push(handler);
    }

    /**
     * 分发帧数据。
     * @param raw KV 格式: "g:1200690|k:1492490|p:1"
     */
    function dispatch(raw) {
        var pairs = raw.split('|');

        // 格式检测：新 KV 格式 "g:1200690|k:1492490" 或旧格式 "currency|gold|1200690|500"
        if (pairs.length > 0 && pairs[0].indexOf(':') < 0 && pairs.length >= 2) {
            // 旧格式兼容：第一段是 type，其余是 fields
            dispatchLegacy(pairs[0], pairs.slice(1));
            return;
        }

        for (var i = 0; i < pairs.length; i++) {
            var sep = pairs[i].indexOf(':');
            if (sep < 0) continue;
            var key = pairs[i].substring(0, sep);
            var val = pairs[i].substring(sep + 1);

            if (lastState[key] === val) continue;
            var oldVal = lastState[key];
            lastState[key] = val;

            fire(key, val, oldVal);
        }
    }

    // 旧 U 前缀格式兼容：type + fields 数组
    function dispatchLegacy(type, fields) {
        if (legacyHandlers[type]) {
            var list = legacyHandlers[type];
            for (var i = 0; i < list.length; i++) {
                try { list[i](fields); } catch(e) { console.error('[UiData:legacy]', type, e); }
            }
        }
    }

    function fire(key, val, oldVal) {
        if (handlers[key]) {
            var list = handlers[key];
            for (var j = 0; j < list.length; j++) {
                try { list[j](val, oldVal); } catch(e) { console.error('[UiData]', key, e); }
            }
        }
    }

    /** 注册旧格式处理器（兼容 U 前缀独立推送） */
    function onLegacy(type, handler) {
        if (!legacyHandlers[type]) legacyHandlers[type] = [];
        legacyHandlers[type].push(handler);
    }

    return { on: on, onLegacy: onLegacy, dispatch: dispatch };
})();
